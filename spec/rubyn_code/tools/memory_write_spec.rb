# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::MemoryWrite do
  let(:project_root) { '/tmp/test_project' }

  WriteRecord = Struct.new(:id, :tier, :category, keyword_init: true)

  def build_tool(store:)
    described_class.new(project_root: project_root, memory_store: store)
  end

  def make_store(record)
    store = Object.new
    store.define_singleton_method(:write) { |content:, tier:, category:| record }
    store
  end

  describe '#execute' do
    context 'when writing succeeds' do
      let(:record) { WriteRecord.new(id: 'mem-abc', tier: 'medium', category: 'code_pattern') }

      it 'writes to store and returns confirmation' do
        tool = build_tool(store: make_store(record))
        result = tool.execute(content: 'Always use let over instance variables')

        expect(result).to include('Memory saved')
      end

      it 'includes ID in output' do
        tool = build_tool(store: make_store(record))
        result = tool.execute(content: 'Some pattern')

        expect(result).to include('mem-abc')
      end

      it 'includes tier in output' do
        tool = build_tool(store: make_store(record))
        result = tool.execute(content: 'Some pattern')

        expect(result).to include('medium')
      end

      it 'includes category in output' do
        tool = build_tool(store: make_store(record))
        result = tool.execute(content: 'Some pattern')

        expect(result).to include('code_pattern')
      end
    end

    context 'when category is nil' do
      let(:record) { WriteRecord.new(id: 'mem-xyz', tier: 'short', category: nil) }

      it 'returns confirmation without category' do
        tool = build_tool(store: make_store(record))
        result = tool.execute(content: 'Quick note', tier: 'short')

        expect(result).to include('mem-xyz')
        expect(result).to include('short')
        expect(result).not_to include('category:')
      end
    end

    context 'with custom parameters' do
      it 'passes tier and category through to store' do
        received_params = {}
        store = Object.new
        store.define_singleton_method(:write) do |content:, tier:, category:|
          received_params[:content] = content
          received_params[:tier] = tier
          received_params[:category] = category
          WriteRecord.new(id: 'mem-1', tier: tier, category: category)
        end

        tool = build_tool(store: store)
        tool.execute(content: 'My content', tier: 'long', category: 'decision')

        expect(received_params[:content]).to eq('My content')
        expect(received_params[:tier]).to eq('long')
        expect(received_params[:category]).to eq('decision')
      end
    end
  end

  describe '.tool_name' do
    it 'returns memory_write' do
      expect(described_class.tool_name).to eq('memory_write')
    end
  end
end
