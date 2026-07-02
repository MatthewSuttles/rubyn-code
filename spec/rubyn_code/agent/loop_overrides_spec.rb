# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Agent::Loop per-turn overrides' do
  let(:agent_loop) do
    loop = RubynCode::Agent::Loop.allocate
    loop.instance_variable_set(:@allowed_tools_override, nil)
    loop.instance_variable_set(:@model_override, nil)
    loop
  end

  describe '#allowed_tools_override=' do
    it 'sets a non-empty array' do
      agent_loop.allowed_tools_override = %w[bash read]
      expect(agent_loop.instance_variable_get(:@allowed_tools_override)).to eq(%w[bash read])
    end

    it 'normalizes empty arrays to nil' do
      agent_loop.allowed_tools_override = []
      expect(agent_loop.instance_variable_get(:@allowed_tools_override)).to be_nil
    end

    it 'normalizes nil to nil' do
      agent_loop.allowed_tools_override = nil
      expect(agent_loop.instance_variable_get(:@allowed_tools_override)).to be_nil
    end
  end

  describe '#filtered_tool_definitions' do
    # Regression: PR #138 pointed build_llm_opts at this method without
    # defining it — every real LLM call raised NoMethodError. Calling it
    # on a real Loop (not a fake) is the point of these examples.
    let(:defs) { [{ name: 'bash' }, { name: 'read_file' }, { name: 'write_file' }] }

    before do
      agent_loop.instance_variable_set(:@plan_mode, false)
      allow(agent_loop).to receive_messages(tool_definitions: defs, read_only_tool_definitions: [defs[1]])
    end

    it 'returns full tool definitions with no plan mode or override' do
      expect(agent_loop.send(:filtered_tool_definitions)).to eq(defs)
    end

    it 'returns read-only definitions in plan mode' do
      agent_loop.instance_variable_set(:@plan_mode, true)
      expect(agent_loop.send(:filtered_tool_definitions)).to eq([defs[1]])
    end

    it 'filters by name when an allowed-tools override is set' do
      agent_loop.allowed_tools_override = %w[bash read_file]
      expect(agent_loop.send(:filtered_tool_definitions)).to eq(defs[0..1])
    end
  end

  describe '#model_override=' do
    it 'strips whitespace and stores' do
      agent_loop.model_override = '  claude-opus-4-8  '
      expect(agent_loop.instance_variable_get(:@model_override)).to eq('claude-opus-4-8')
    end

    it 'clears when given empty string' do
      agent_loop.model_override = '  '
      expect(agent_loop.instance_variable_get(:@model_override)).to be_nil
    end
  end
end

RSpec.describe RubynCode::CLI::Commands::Context do
  let(:fake_loop) do
    Class.new do
      attr_reader :over

      def initialize
        @over = { tools: nil, model: nil }
      end

      def allowed_tools_override=(value)
        @over[:tools] = value
      end

      def model_override=(value)
        @over[:model] = value
      end
    end.new
  end

  let(:ctx_base_attrs) do
    {
      renderer: nil, conversation: nil, agent_loop: nil,
      context_manager: nil, budget_enforcer: nil, llm_client: nil,
      db: nil, session_id: nil, project_root: nil, skill_loader: nil,
      session_persistence: nil, background_worker: nil, permission_tier: nil,
      plan_mode: false, message_handler: nil, hook_registry: nil,
      checkpoint_manager: nil
    }
  end

  let(:ctx) { described_class.new(**ctx_base_attrs, agent_loop: fake_loop) }

  describe '#with_allowed_tools' do
    it 'sets the override before yielding and clears it after' do
      captured = nil
      ctx.with_allowed_tools(%w[bash read]) do
        captured = fake_loop.over[:tools]
      end
      expect(captured).to eq(%w[bash read])
      expect(fake_loop.over[:tools]).to be_nil
    end

    it 'clears the override even if the block raises' do
      expect do
        ctx.with_allowed_tools(%w[bash]) { raise 'boom' }
      end.to raise_error('boom')
      expect(fake_loop.over[:tools]).to be_nil
    end
  end

  describe '#with_optional_model' do
    it 'sets and clears the model override' do
      captured = nil
      ctx.with_optional_model('claude-opus-4-8') do
        captured = fake_loop.over[:model]
      end
      expect(captured).to eq('claude-opus-4-8')
      expect(fake_loop.over[:model]).to be_nil
    end
  end

  it 'is a no-op when no agent_loop is wired' do
    ctx_no_loop = described_class.new(**ctx_base_attrs, agent_loop: nil)
    expect { ctx_no_loop.with_allowed_tools([:a]) { nil } }.not_to raise_error
  end
end
