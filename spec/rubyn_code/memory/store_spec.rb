# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Memory::Store do
  let(:db) { setup_test_db_with_tables }
  let(:project_path) { '/test/project' }

  subject(:store) { described_class.new(db, project_path: project_path) }

  describe '#write' do
    it 'creates a memory and returns a MemoryRecord' do
      record = store.write(content: 'Ruby is great')

      expect(record).to be_a(RubynCode::Memory::MemoryRecord)
      expect(record.content).to eq('Ruby is great')
      expect(record.tier).to eq('medium')
      expect(record.id).not_to be_nil
    end

    it 'accepts tier, category, and metadata' do
      record = store.write(
        content: 'pattern',
        tier: 'long',
        category: 'code_pattern',
        metadata: { source: 'test' }
      )

      expect(record.tier).to eq('long')
      expect(record.category).to eq('code_pattern')
      expect(record.metadata).to eq({ source: 'test' })
    end

    it 'rejects invalid tier' do
      expect { store.write(content: 'x', tier: 'forever') }
        .to raise_error(ArgumentError, /Invalid tier/)
    end
  end

  describe '#update' do
    it 'updates content' do
      record = store.write(content: 'original')
      store.update(record.id, content: 'updated')

      row = db.query('SELECT content FROM memories WHERE id = ?', [record.id]).first
      expect(row['content']).to eq('updated')
    end

    it 'updates tier with validation' do
      record = store.write(content: 'test')
      store.update(record.id, tier: 'long')

      row = db.query('SELECT tier FROM memories WHERE id = ?', [record.id]).first
      expect(row['tier']).to eq('long')
    end

    it 'rejects invalid tier on update' do
      record = store.write(content: 'test')
      expect { store.update(record.id, tier: 'invalid') }
        .to raise_error(ArgumentError, /Invalid tier/)
    end

    it 'does nothing with empty attrs' do
      record = store.write(content: 'test')
      expect { store.update(record.id) }.not_to raise_error
    end
  end

  describe '#delete' do
    it 'removes the memory' do
      record = store.write(content: 'goodbye')
      store.delete(record.id)

      rows = db.query('SELECT * FROM memories WHERE id = ?', [record.id])
      expect(rows).to be_empty
    end
  end

  describe '#expire_old!' do
    it 'deletes expired memories' do
      past = (Time.now.utc - 86_400).strftime('%Y-%m-%d %H:%M:%S')
      store.write(content: 'expired', expires_at: past)
      store.write(content: 'not expired')

      count = store.expire_old!

      expect(count).to eq(1)
      rows = db.query('SELECT * FROM memories WHERE project_path = ?', [project_path])
      expect(rows.size).to eq(1)
      expect(rows.first['content']).to eq('not expired')
    end

    it 'returns 0 when nothing is expired' do
      store.write(content: 'still fresh')
      expect(store.expire_old!).to eq(0)
    end
  end

  describe '#decay!' do
    it 'reduces relevance of old memories' do
      record = store.write(content: 'old memory')
      # Backdate the last_accessed_at
      db.execute(
        'UPDATE memories SET last_accessed_at = ? WHERE id = ?',
        [(Time.now.utc - (86_400 * 2)).strftime('%Y-%m-%d %H:%M:%S'), record.id]
      )

      store.decay!(decay_rate: 0.5)

      row = db.query('SELECT relevance_score FROM memories WHERE id = ?', [record.id]).first
      expect(row['relevance_score']).to be < 1.0
    end
  end

  describe '#update additional branches' do
    it 'updates category with validation and stores it' do
      record = store.write(content: 'categorized')
      store.update(record.id, category: 'code_pattern')

      row = db.query('SELECT category FROM memories WHERE id = ?', [record.id]).first
      expect(row['category']).to eq('code_pattern')
    end

    it 'updates metadata and stores as JSON' do
      record = store.write(content: 'with metadata')
      store.update(record.id, metadata: { key: 'value', nested: { a: 1 } })

      row = db.query('SELECT metadata FROM memories WHERE id = ?', [record.id]).first
      parsed = JSON.parse(row['metadata'])
      expect(parsed).to eq({ 'key' => 'value', 'nested' => { 'a' => 1 } })
    end

    it 'updates expires_at and stores it' do
      record = store.write(content: 'expiring')
      future = '2099-12-31 23:59:59'
      store.update(record.id, expires_at: future)

      row = db.query('SELECT expires_at FROM memories WHERE id = ?', [record.id]).first
      expect(row['expires_at']).to eq(future)
    end

    it 'updates relevance_score and stores it as float' do
      record = store.write(content: 'scored')
      store.update(record.id, relevance_score: '0.75')

      row = db.query('SELECT relevance_score FROM memories WHERE id = ?', [record.id]).first
      expect(row['relevance_score']).to eq(0.75)
    end

    it 'raises ArgumentError for invalid category on update' do
      record = store.write(content: 'bad category')
      expect { store.update(record.id, category: 'nonexistent_category') }
        .to raise_error(ArgumentError, /Invalid category/)
    end

    it 'allows nil category on update without validation error' do
      record = store.write(content: 'nil cat', category: 'code_pattern')
      expect { store.update(record.id, category: nil) }.not_to raise_error

      row = db.query('SELECT category FROM memories WHERE id = ?', [record.id]).first
      expect(row['category']).to be_nil
    end
  end

  describe '#write category validation' do
    it 'raises ArgumentError with helpful message for invalid category' do
      expect { store.write(content: 'bad', category: 'bogus') }
        .to raise_error(ArgumentError, /Invalid category.*bogus.*Must be one of/)
    end
  end
end
