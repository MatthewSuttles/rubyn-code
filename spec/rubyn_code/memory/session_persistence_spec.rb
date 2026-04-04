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
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: [{ role: 'user', content: 'v1' }], model: 'claude-sonnet')
      persistence.save_session(session_id: 'sess-1', project_path: '/test', messages: [{ role: 'user', content: 'v2' }], model: 'claude-sonnet')

      session = persistence.load_session('sess-1')
      expect(session[:messages]).to eq([{ role: 'user', content: 'v2' }])
    end

    it 'stores metadata as JSON' do
      persistence.save_session(
        session_id: 'sess-1',
        project_path: '/test',
        messages: [], model: "claude-sonnet",
        metadata: { cost: 0.05, tokens: 1000 }
      )

      session = persistence.load_session('sess-1')
      expect(session[:metadata]).to eq({ cost: 0.05, tokens: 1000 })
    end
  end

  describe '#load_session' do
    it 'returns nil for nonexistent session' do
      expect(persistence.load_session('nope')).to be_nil
    end

    it 'handles malformed JSON gracefully' do
      # Ensure table exists (persistence constructor calls ensure_table)
      persistence
      db.execute(
        'INSERT INTO sessions (id, project_path, messages, metadata, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['bad', '/test', '{bad json', '{also bad', 'active', '2024-01-01', '2024-01-01']
      )

      session = persistence.load_session('bad')
      expect(session[:messages]).to eq([])
      expect(session[:metadata]).to eq({})
    end
  end

  describe '#list_sessions' do
    before do
      persistence.save_session(session_id: 's1', project_path: '/a', messages: [], model: "claude-sonnet", title: 'A')
      persistence.save_session(session_id: 's2', project_path: '/a', messages: [], model: "claude-sonnet", title: 'B')
      persistence.save_session(session_id: 's3', project_path: '/b', messages: [], model: "claude-sonnet", title: 'C')
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
      persistence.save_session(session_id: 's1', project_path: '/test', messages: [], model: "claude-sonnet", title: 'Original')
    end

    it 'updates title' do
      persistence.update_session('s1', title: 'New Title')
      session = persistence.load_session('s1')
      expect(session[:title]).to eq('New Title')
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
      persistence.save_session(session_id: 's1', project_path: '/test', messages: [], model: "claude-sonnet")
      persistence.delete_session('s1')
      expect(persistence.load_session('s1')).to be_nil
    end

    it 'does nothing for nonexistent session' do
      expect { persistence.delete_session('nope') }.not_to raise_error
    end
  end
end
