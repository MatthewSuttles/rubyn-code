# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Memory::Search do
  let(:db) { setup_test_db_with_tables }
  let(:project_path) { '/test/project' }
  let(:store) { RubynCode::Memory::Store.new(db, project_path: project_path) }

  subject(:search) { described_class.new(db, project_path: project_path) }

  before do
    store.write(content: 'Ruby guard clauses are great', tier: 'long', category: 'code_pattern')
    store.write(content: 'Use frozen_string_literal', tier: 'medium', category: 'project_convention')
    store.write(content: 'Rails uses MVC pattern', tier: 'short', category: 'code_pattern')
  end

  describe '#search' do
    it 'finds memories matching the query' do
      results = search.search('guard clauses')

      expect(results.size).to eq(1)
      expect(results.first.content).to include('guard clauses')
    end

    it 'returns empty array when nothing matches' do
      results = search.search('nonexistent unicorn')
      expect(results).to be_empty
    end

    it 'filters by tier' do
      results = search.search('Ruby', tier: 'long')

      expect(results.size).to eq(1)
      expect(results.first.tier).to eq('long')
    end

    it 'filters by category' do
      results = search.search('pattern', category: 'code_pattern')

      contents = results.map(&:content)
      expect(contents).to all(include('pattern').or(include('clauses')))
    end

    it 'respects limit' do
      results = search.search('', limit: 1)
      expect(results.size).to eq(1)
    end

    it 'updates access_count on returned records' do
      results = search.search('frozen_string_literal')
      record_id = results.first.id

      row = db.query('SELECT access_count FROM memories WHERE id = ?', [record_id]).first
      expect(row['access_count']).to eq(1)
    end
  end

  describe '#recent' do
    it 'returns most recent memories' do
      results = search.recent(limit: 2)

      expect(results.size).to eq(2)
    end
  end

  describe '#by_category' do
    it 'returns memories in the given category' do
      results = search.by_category('code_pattern')

      expect(results.size).to eq(2)
      expect(results.map(&:category)).to all(eq('code_pattern'))
    end
  end

  describe '#by_tier' do
    it 'returns memories in the given tier' do
      results = search.by_tier('medium')

      expect(results.size).to eq(1)
      expect(results.first.tier).to eq('medium')
    end
  end
end
