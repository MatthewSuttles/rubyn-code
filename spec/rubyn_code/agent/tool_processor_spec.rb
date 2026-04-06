# frozen_string_literal: true

require 'spec_helper'

# Force-load the Loop class which requires the processor module
RubynCode::Agent::Loop

RSpec.describe RubynCode::Agent::ToolProcessor do
  # Create a host class that includes the module
  let(:host_class) do
    Class.new do
      include RubynCode::Agent::ToolProcessor

      attr_accessor :tool_executor, :discovered_tools, :conversation,
                    :stall_detector, :hook_runner, :on_tool_call, :on_tool_result,
                    :permission_tier, :deny_list

      def initialize(attrs = {})
        @tool_executor = attrs[:tool_executor]
        @discovered_tools = attrs[:discovered_tools]
        @conversation = attrs[:conversation]
        @stall_detector = attrs[:stall_detector]
        @hook_runner = attrs[:hook_runner]
        @on_tool_call = attrs[:on_tool_call]
        @on_tool_result = attrs[:on_tool_result]
        @permission_tier = attrs[:permission_tier] || RubynCode::Permissions::Tier::UNRESTRICTED
        @deny_list = attrs[:deny_list] || RubynCode::Permissions::DenyList.new
      end

      # Expose private methods for testing
      public :tool_definitions, :core_or_discovered?, :discover_tool,
             :read_only_tool_definitions, :truncate_tool_result,
             :execute_with_permission, :execute_tool, :process_tool_calls,
             :resolve_tool_risk

      # Required by ToolProcessor
      def field(obj, key)
        obj[key] || obj[key.to_s]
      end

      def symbolize_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym)
      end

      def prompt_user(_tool_name, _tool_input)
        true
      end
    end
  end

  let(:tool_executor) { instance_double(RubynCode::Tools::Executor, tool_definitions: all_tools) }
  let(:conversation) { RubynCode::Agent::Conversation.new }
  let(:stall_detector) { RubynCode::Agent::LoopDetector.new }
  let(:hook_runner) { instance_double(RubynCode::Hooks::Runner, fire: nil) }

  let(:core_tools) do
    RubynCode::Agent::ToolProcessor::CORE_TOOLS.map { |name| { name: name } }
  end

  let(:extra_tools) do
    [{ name: 'custom_linter' }, { name: 'deploy_tool' }]
  end

  let(:all_tools) { core_tools + extra_tools }

  subject(:processor) do
    host_class.new(
      tool_executor: tool_executor,
      conversation: conversation,
      stall_detector: stall_detector,
      hook_runner: hook_runner
    )
  end

  describe '#tool_definitions' do
    context 'when total tools exceed CORE_TOOLS size' do
      it 'returns only core tools initially (no discovered tools)' do
        defs = processor.tool_definitions
        names = defs.map { |t| t[:name] }
        expect(names).to include('read_file')
        expect(names).to include('bash')
        expect(names).not_to include('custom_linter')
        expect(names).not_to include('deploy_tool')
      end

      it 'includes discovered tools after they are discovered' do
        processor.discover_tool('custom_linter')
        defs = processor.tool_definitions
        names = defs.map { |t| t[:name] }
        expect(names).to include('custom_linter')
        expect(names).not_to include('deploy_tool')
      end
    end

    context 'when total tools do not exceed CORE_TOOLS size' do
      let(:all_tools) { [{ name: 'read_file' }, { name: 'bash' }] }

      it 'returns all tools without filtering' do
        defs = processor.tool_definitions
        expect(defs).to eq(all_tools)
      end
    end
  end

  describe '#core_or_discovered?' do
    it 'returns true for a core tool' do
      expect(processor.core_or_discovered?({ name: 'read_file' })).to be true
    end

    it 'returns true for a core tool with string key' do
      expect(processor.core_or_discovered?({ 'name' => 'bash' })).to be true
    end

    it 'returns falsy for an unknown tool' do
      expect(processor.core_or_discovered?({ name: 'custom_linter' })).to be_falsey
    end

    it 'returns true for a discovered tool' do
      processor.discover_tool('custom_linter')
      expect(processor.core_or_discovered?({ name: 'custom_linter' })).to be true
    end

    it 'returns falsy when discovered_tools is nil' do
      processor.discovered_tools = nil
      expect(processor.core_or_discovered?({ name: 'custom_linter' })).to be_falsey
    end
  end

  describe '#discover_tool' do
    it 'adds the tool name to the discovered set' do
      processor.discover_tool('my_tool')
      expect(processor.instance_variable_get(:@discovered_tools)).to include('my_tool')
    end

    it 'initializes discovered_tools if nil' do
      processor.discovered_tools = nil
      processor.discover_tool('new_tool')
      expect(processor.instance_variable_get(:@discovered_tools)).to be_a(Set)
      expect(processor.instance_variable_get(:@discovered_tools)).to include('new_tool')
    end

    it 'does not duplicate tool names' do
      processor.discover_tool('my_tool')
      processor.discover_tool('my_tool')
      expect(processor.instance_variable_get(:@discovered_tools).size).to eq(1)
    end
  end

  describe '#read_only_tool_definitions' do
    it 'returns only tools with :read risk level' do
      defs = processor.read_only_tool_definitions
      expect(defs).to be_an(Array)
      defs.each do |schema|
        tool_class = RubynCode::Tools::Registry.all.find { |t| t.tool_name == schema[:name] }
        expect(tool_class::RISK_LEVEL).to eq(:read) if tool_class
      end
    end

    it 'returns schemas (hashes with :name key)' do
      defs = processor.read_only_tool_definitions
      defs.each do |schema|
        expect(schema).to have_key(:name)
        expect(schema).to have_key(:description)
      end
    end
  end

  describe '#truncate_tool_result' do
    let(:budget) { 1000 }

    context 'when aggregate is under budget' do
      it 'returns the result unchanged' do
        result = 'short result'
        expect(processor.truncate_tool_result(result, 500, budget)).to eq(result)
      end
    end

    context 'when aggregate exceeds budget' do
      it 'truncates the result and appends a notice' do
        result = 'x' * 800
        truncated = processor.truncate_tool_result(result, 1200, budget)
        expect(truncated).to include('[truncated')
        expect(truncated.length).to be < result.length + 100
      end

      it 'preserves at least 500 chars of the result' do
        result = 'y' * 2000
        truncated = processor.truncate_tool_result(result, 3000, budget)
        # The remaining portion should be at least 500 chars
        first_line = truncated.split("\n\n[truncated").first
        expect(first_line.length).to be >= 500
      end
    end

    context 'when result is nil' do
      it 'handles nil result gracefully when under budget' do
        expect(processor.truncate_tool_result(nil, 500, budget)).to be_nil
      end

      it 'handles nil result when over budget' do
        truncated = processor.truncate_tool_result(nil, 1200, budget)
        expect(truncated).to include('[truncated')
      end
    end
  end

  describe '#execute_with_permission' do
    it 'returns denial message for :deny decision' do
      result, is_error = processor.execute_with_permission(:deny, 'bash', {})
      expect(is_error).to be true
      expect(result).to include('blocked')
    end

    it 'returns unknown message for unrecognized decision' do
      result, is_error = processor.execute_with_permission(:wat, 'bash', {})
      expect(is_error).to be true
      expect(result).to include('Unknown permission decision')
    end

    it 'executes the tool for :allow decision' do
      allow(tool_executor).to receive(:execute).and_return('output')
      result, is_error = processor.execute_with_permission(:allow, 'read_file', { path: 'foo.rb' })
      expect(is_error).to be false
      expect(result).to eq('output')
    end
  end

  describe '#resolve_tool_risk' do
    it 'returns a risk level symbol for a registered tool' do
      # Use a tool we know is registered
      registered_tool = RubynCode::Tools::Registry.tool_names.first
      if registered_tool
        risk = processor.resolve_tool_risk(registered_tool)
        expect(risk).to be_a(Symbol)
        expect(risk).not_to eq(:unknown)
      end
    end

    it 'returns :unknown for an unregistered tool' do
      risk = processor.resolve_tool_risk('nonexistent_tool_xyz')
      expect(risk).to eq(:unknown)
    end
  end

  describe '#process_tool_calls' do
    let(:tool_call) do
      { id: 'tc_1', name: 'read_file', input: { path: 'test.rb' } }
    end

    before do
      allow(RubynCode::Permissions::Policy).to receive(:check).and_return(:allow)
      allow(tool_executor).to receive(:execute).and_return('file contents')
    end

    it 'processes a tool call and records the result' do
      processor.process_tool_calls([tool_call])
      # The result should be added to conversation
      last_msg = conversation.messages.last
      expect(last_msg[:role]).to eq('user')
      expect(last_msg[:content].first[:type]).to eq('tool_result')
    end

    it 'calls on_tool_call callback if provided' do
      callback = double('callback')
      expect(callback).to receive(:call).with('read_file', { path: 'test.rb' })
      processor.on_tool_call = callback
      processor.process_tool_calls([tool_call])
    end

    it 'calls on_tool_result callback if provided' do
      callback = double('callback')
      expect(callback).to receive(:call).with('read_file', anything, false)
      processor.on_tool_result = callback
      processor.process_tool_calls([tool_call])
    end
  end
end
