# frozen_string_literal: true

require 'spec_helper'

MemorySearchTestRecord = Struct.new(:id, :tier, :category, :relevance_score, :access_count, :created_at, :content, keyword_init: true)

RSpec.describe RubynCode::Tools::MemorySearch do
  let(:project_root) { '/tmp/test_project' }

  def build_tool(search:)
    described_class.new(project_root: project_root, memory_search: search)
  end

  def make_record(attrs = {})
    MemorySearchTestRecord.new({
      id: 'mem-001',
      tier: 'medium',
      category: 'code_pattern',
      relevance_score: 0.95,
      access_count: 3,
      created_at: '2024-01-15',
      content: 'Use frozen_string_literal in all Ruby files'
    }.merge(attrs))
  end

  describe '#execute' do
    context 'when results are found' do
      it 'returns formatted results' do
        record = make_record
        search = Object.new
        search.define_singleton_method(:search) { |_query, **_opts| [record] }

        tool = build_tool(search: search)
        result = tool.execute(query: 'frozen string')

        expect(result).to include('Found 1 memory')
        expect(result).to include('mem-001')
        expect(result).to include('medium')
        expect(result).to include('code_pattern')
        expect(result).to include('Use frozen_string_literal')
      end

      it 'formats multiple results with indices' do
        records = [
          make_record(id: 'mem-001', content: 'First pattern'),
          make_record(id: 'mem-002', content: 'Second pattern')
        ]
        search = Object.new
        search.define_singleton_method(:search) { |_query, **_opts| records }

        tool = build_tool(search: search)
        result = tool.execute(query: 'patterns')

        expect(result).to include('Found 2 memories')
        expect(result).to include('Memory 1')
        expect(result).to include('Memory 2')
        expect(result).to include('mem-001')
        expect(result).to include('mem-002')
      end
    end

    context 'when no results are found' do
      it 'returns no memories found message' do
        search = Object.new
        search.define_singleton_method(:search) { |_query, **_opts| [] }

        tool = build_tool(search: search)
        result = tool.execute(query: 'nonexistent')

        expect(result).to include('No memories found')
        expect(result).to include('nonexistent')
      end
    end

    context 'with filter parameters' do
      it 'passes tier, category, and limit through to search' do
        received_params = {}
        search = Object.new
        search.define_singleton_method(:search) do |query, tier: nil, category: nil, limit: 10|
          received_params[:query] = query
          received_params[:tier] = tier
          received_params[:category] = category
          received_params[:limit] = limit
          []
        end

        tool = build_tool(search: search)
        tool.execute(query: 'test', tier: 'long', category: 'decision', limit: 5)

        expect(received_params[:query]).to eq('test')
        expect(received_params[:tier]).to eq('long')
        expect(received_params[:category]).to eq('decision')
        expect(received_params[:limit]).to eq(5)
      end
    end
  end

  describe '.tool_name' do
    it 'returns memory_search' do
      expect(described_class.tool_name).to eq('memory_search')
    end
  end
end
