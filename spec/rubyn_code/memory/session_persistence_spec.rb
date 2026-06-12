# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Memory::SessionPersistence do
  # Use bare DB — SessionPersistence.new(db) calls ensure_table which creates
  # the sessions table with its own schema (no CHECK constraints from migrations).
  let(:db) { setup_test_db }

  subject(:persistence) { described_class.new(db) }

  describe '#save_session' do
    it 'creates a new session' do
      persistence.save_session(
        session_id: 'sess-1',
        project_path: '/test',
        messages: [{ role: 'user', content: 'hello' }],
        title: 'Test Session',
        model: 'claude-sonnet'
      )

      session = persistence.load_session('sess-1')
      expect(session[:title]).to eq('Test Session')
      expect(session[:model]).to eq('claude-sonnet')
      expect(session[:messages]).to eq([{ role: 'user', content: 'hello' }])
      expect(session[:project_path]).to eq('/test')
      expect(session[:status]).to eq('active')
    end

    it 'upserts on duplicate session_id' do
      persistence.save_session(session_id: 'sess-1', project_path: '/test',
                               messages: [{ role: 'user', content: 'v1' }], model: 'claude-sonnet')
      persistence.save_session(session_id: 'sess-1', project_path: '/test',
                               messages: [{ role: 'user', content: 'v2' }], model: 'claude-sonnet')

      session = persistence.load_session('sess-1')
      expect(session[:messages]).to eq([{ role: 'user', content: 'v2' }])
    end

    it 'stores metadata as JSON' do
      persistence.save_session(
        session_id: 'sess-1',
        project_path: '/test',
        messages: [], model: 'claude-sonnet',
        metadata: { cost: 0.05, tokens: 1000 }
      )

      session = persistence.load_session('sess-1')
      expect(session[:metadata]).to eq({ cost: 0.05, tokens: 1000 })
    end
  end

  describe 'incremental saves' do
    let(:messages) { [{ role: 'user', content: 'hello' }] }

    def journal_rows(session_id)
      db.query('SELECT * FROM messages WHERE session_id = ? ORDER BY id', [session_id]).to_a
    end

    it 'round-trips messages appended across consecutive saves' do
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)
      messages << { role: 'assistant', content: [{ type: 'text', text: 'hi!' }] }
      messages << { role: 'user', content: 'follow-up' }
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)

      expect(persistence.load_session('sess-1')[:messages]).to eq(messages)
    end

    it 'journals appended messages instead of rewriting the blob' do
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)
      messages << { role: 'assistant', content: [{ type: 'text', text: 'hi!' }] }
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)

      blob = db.query('SELECT messages FROM sessions WHERE id = ?', ['sess-1']).first['messages']
      expect(JSON.parse(blob).length).to eq(1) # blob still holds only the first snapshot
      expect(journal_rows('sess-1').length).to eq(1)
    end

    it 'snapshots and clears the journal when history is rewritten' do
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)
      messages << { role: 'assistant', content: [{ type: 'text', text: 'hi!' }] }
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)

      compacted = [{ role: 'user', content: 'compacted summary' }]
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: compacted)

      expect(journal_rows('sess-1')).to be_empty
      expect(persistence.load_session('sess-1')[:messages]).to eq(compacted)
    end

    it 'consolidates the journal into the blob on the first save of a new instance' do
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)
      messages << { role: 'user', content: 'journaled' }
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)

      fresh = described_class.new(db)
      fresh.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)

      expect(journal_rows('sess-1')).to be_empty
      expect(fresh.load_session('sess-1')[:messages]).to eq(messages)
    end

    it 'updates title and updated_at on append saves' do
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)
      messages << { role: 'user', content: 'more' }
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages, title: 'Named')

      expect(persistence.load_session('sess-1')[:title]).to eq('Named')
    end

    it 'clears the journal when update_session rewrites messages' do
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)
      messages << { role: 'user', content: 'journaled' }
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)

      persistence.update_session('sess-1', messages: [{ role: 'user', content: 'rewritten' }])

      expect(journal_rows('sess-1')).to be_empty
      expect(persistence.load_session('sess-1')[:messages]).to eq([{ role: 'user', content: 'rewritten' }])
    end

    it 'removes journal rows when the session is deleted' do
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)
      messages << { role: 'user', content: 'journaled' }
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: messages)

      persistence.delete_session('sess-1')

      expect(journal_rows('sess-1')).to be_empty
    end
  end

  describe '#load_session' do
    it 'returns nil for nonexistent session' do
      expect(persistence.load_session('nope')).to be_nil
    end

    it 'handles malformed JSON gracefully' do
      persistence
      sql = <<~SQL.tr("\n", ' ').strip
        INSERT INTO sessions
          (id, project_path, messages, metadata, status,
           created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(
        sql,
        ['bad', '/test', '{bad json', '{also bad',
         'active', '2024-01-01', '2024-01-01']
      )

      session = persistence.load_session('bad')
      expect(session[:messages]).to eq([])
      expect(session[:metadata]).to eq({})
    end

    it 'handles empty string messages and metadata' do
      persistence
      sql = <<~SQL.tr("\n", ' ').strip
        INSERT INTO sessions
          (id, project_path, messages, metadata, status,
           created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(
        sql,
        ['empty-data', '/test', '', '',
         'active', '2024-01-01', '2024-01-01']
      )

      session = persistence.load_session('empty-data')
      expect(session[:messages]).to eq([])
      expect(session[:metadata]).to eq({})
    end

    it 'handles non-array JSON messages gracefully' do
      persistence
      sql = <<~SQL.tr("\n", ' ').strip
        INSERT INTO sessions
          (id, project_path, messages, metadata, status,
           created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(
        sql,
        ['obj-data', '/test', '{"not": "an array"}',
         '{"still": "ok"}', 'active', '2024-01-01', '2024-01-01']
      )

      session = persistence.load_session('obj-data')
      # metadata parses as hash, messages may be hash or wrapped
      expect(session[:metadata]).to include(still: 'ok')
      expect(session[:messages]).not_to be_nil
    end
  end

  describe '#list_sessions' do
    before do
      persistence.save_session(session_id: 's1', project_path: '/a', messages: [], model: 'claude-sonnet', title: 'A')
      persistence.save_session(session_id: 's2', project_path: '/a', messages: [], model: 'claude-sonnet', title: 'B')
      persistence.save_session(session_id: 's3', project_path: '/b', messages: [], model: 'claude-sonnet', title: 'C')
    end

    it 'lists all sessions' do
      sessions = persistence.list_sessions
      expect(sessions.size).to eq(3)
    end

    it 'filters by project_path' do
      sessions = persistence.list_sessions(project_path: '/a')
      expect(sessions.size).to eq(2)
      expect(sessions.map { |s| s[:project_path] }).to all(eq('/a'))
    end

    it 'filters by status' do
      persistence.update_session('s1', status: 'completed')
      sessions = persistence.list_sessions(status: 'completed')
      expect(sessions.size).to eq(1)
      expect(sessions.first[:id]).to eq('s1')
    end

    it 'respects limit' do
      sessions = persistence.list_sessions(limit: 1)
      expect(sessions.size).to eq(1)
    end

    it 'orders by updated_at descending' do
      sessions = persistence.list_sessions
      timestamps = sessions.map { |s| s[:updated_at] }
      expect(timestamps).to eq(timestamps.sort.reverse)
    end
  end

  describe '#update_session' do
    before do
      persistence.save_session(session_id: 's1', project_path: '/test', messages: [], model: 'claude-sonnet',
                               title: 'Original')
    end

    it 'updates title' do
      persistence.update_session('s1', title: 'New Title')
      session = persistence.load_session('s1')
      expect(session[:title]).to eq('New Title')
    end

    it 'updates model' do
      persistence.update_session('s1', model: 'claude-opus')
      session = persistence.load_session('s1')
      expect(session[:model]).to eq('claude-opus')
    end

    it 'updates status' do
      persistence.update_session('s1', status: 'paused')
      session = persistence.load_session('s1')
      expect(session[:status]).to eq('paused')
    end

    it 'updates metadata' do
      persistence.update_session('s1', metadata: { foo: 'bar' })
      session = persistence.load_session('s1')
      expect(session[:metadata]).to eq({ foo: 'bar' })
    end

    it 'updates messages' do
      new_msgs = [{ role: 'user', content: 'updated' }]
      persistence.update_session('s1', messages: new_msgs)
      session = persistence.load_session('s1')
      expect(session[:messages]).to eq([{ role: 'user', content: 'updated' }])
    end

    it 'does nothing with empty attrs' do
      expect { persistence.update_session('s1') }.not_to raise_error
    end
  end

  describe '#delete_session' do
    it 'permanently removes the session' do
      persistence.save_session(session_id: 's1', project_path: '/test', messages: [], model: 'claude-sonnet')
      persistence.delete_session('s1')
      expect(persistence.load_session('s1')).to be_nil
    end

    it 'does nothing for nonexistent session' do
      expect { persistence.delete_session('nope') }.not_to raise_error
    end
  end
end
