# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe RubynCode::Learning::Injector do
  let(:db) { setup_test_db_with_tables }
  let(:project_path) { '/test/project' }

  def insert_instinct(id:, pattern:, confidence: 0.7, tags: [], decay_rate: 0.01, updated_at: nil)
    now = (updated_at || Time.now).utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    db.execute(
      'INSERT INTO instincts (id, project_path, pattern, context_tags, confidence, decay_rate, times_applied, times_helpful, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, project_path, pattern, JSON.generate(tags), confidence, decay_rate, 0, 0, now, now]
    )
  end

  describe '.call' do
    it 'returns empty string when no instincts exist' do
      result = described_class.call(db: db, project_path: project_path)
      expect(result).to eq('')
    end

    it 'returns formatted instincts block' do
      insert_instinct(id: 'i1', pattern: 'Use guard clauses', confidence: 0.8)

      result = described_class.call(db: db, project_path: project_path)

      expect(result).to include('<instincts>')
      expect(result).to include('Use guard clauses')
      expect(result).to include('confident')
      expect(result).to include('</instincts>')
    end

    it 'filters instincts below MIN_CONFIDENCE' do
      insert_instinct(id: 'low', pattern: 'Low confidence', confidence: 0.1)

      result = described_class.call(db: db, project_path: project_path)

      expect(result).to eq('')
    end

    it 'sorts by confidence descending' do
      insert_instinct(id: 'i1', pattern: 'First', confidence: 0.5)
      insert_instinct(id: 'i2', pattern: 'Second', confidence: 0.9)

      result = described_class.call(db: db, project_path: project_path)

      first_idx = result.index('Second')
      second_idx = result.index('First')
      expect(first_idx).to be < second_idx
    end

    it 'limits to max_instincts' do
      5.times do |i|
        insert_instinct(id: "i#{i}", pattern: "Pattern #{i}", confidence: 0.8)
      end

      result = described_class.call(db: db, project_path: project_path, max_instincts: 2)

      expect(result.scan(/Pattern/).size).to eq(2)
    end

    it 'filters by context_tags when provided' do
      insert_instinct(id: 'i1', pattern: 'Ruby pattern', confidence: 0.8, tags: %w[ruby style])
      insert_instinct(id: 'i2', pattern: 'JS pattern', confidence: 0.8, tags: %w[javascript])

      result = described_class.call(db: db, project_path: project_path, context_tags: ['ruby'])

      expect(result).to include('Ruby pattern')
      expect(result).not_to include('JS pattern')
    end

    it 'applies time-based decay before filtering' do
      # Insert an instinct with confidence just above threshold, but old enough
      # that decay drops it below
      insert_instinct(
        id: 'decayed',
        pattern: 'Old pattern',
        confidence: 0.35,
        decay_rate: 0.5,
        updated_at: Time.now - (86_400 * 30) # 30 days ago
      )

      result = described_class.call(db: db, project_path: project_path)

      expect(result).to eq('')
    end

    it 'scopes to the given project_path' do
      insert_instinct(id: 'i1', pattern: 'My pattern', confidence: 0.8)

      result = described_class.call(db: db, project_path: '/different/project')

      expect(result).to eq('')
    end
  end
end
