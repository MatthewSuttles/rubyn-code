# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::Compact do
  let(:project_root) { '/tmp/test_project' }

  def build_tool(context_manager: nil)
    described_class.new(project_root: project_root, context_manager: context_manager)
  end

  describe '#execute' do
    context 'when no context_manager is provided' do
      it 'returns unavailable message' do
        tool = build_tool(context_manager: nil)
        result = tool.execute

        expect(result).to include('not available')
        expect(result).to include('No context manager was provided')
      end
    end

    context 'when context_manager does not respond to :compact' do
      let(:manager) { Object.new }

      it 'returns not-supported message' do
        tool = build_tool(context_manager: manager)
        result = tool.execute

        expect(result).to include('does not support compaction')
      end
    end

    context 'when context_manager supports compaction' do
      let(:manager) do
        obj = Object.new
        def obj.compact(**_opts)
          { before: 100, after: 20, tokens_saved: 5000 }
        end
        obj
      end

      it 'calls compact on manager and returns success message' do
        tool = build_tool(context_manager: manager)
        result = tool.execute

        expect(result).to include('Context compacted successfully')
      end

      it 'formats hash result with before/after/tokens_saved' do
        tool = build_tool(context_manager: manager)
        result = tool.execute

        expect(result).to include('Messages before: 100')
        expect(result).to include('Messages after: 20')
        expect(result).to include('Tokens saved: ~5000')
      end
    end

    context 'when focus is provided' do
      let(:manager) do
        obj = Object.new
        def obj.compact(**_opts)
          { before: 50, after: 10, tokens_saved: 2000 }
        end
        obj
      end

      it 'includes focus in output' do
        tool = build_tool(context_manager: manager)
        result = tool.execute(focus: 'the auth refactor')

        expect(result).to include('Focus: the auth refactor')
      end
    end

    context 'when compact returns a non-hash result' do
      let(:manager) do
        obj = Object.new
        def obj.compact(**_opts)
          'done'
        end
        obj
      end

      it 'returns success without detail lines' do
        tool = build_tool(context_manager: manager)
        result = tool.execute

        expect(result).to eq('Context compacted successfully.')
      end
    end
  end

  describe '.tool_name' do
    it 'returns compact' do
      expect(described_class.tool_name).to eq('compact')
    end
  end
end
