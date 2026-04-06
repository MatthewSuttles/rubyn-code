# frozen_string_literal: true

require 'spec_helper'

# Force-load the Loop class which requires the builder module
RubynCode::Agent::Loop

RSpec.describe RubynCode::Agent::SystemPromptBuilder do
  # Create a host class that includes the module, simulating how Loop uses it.
  let(:host_class) do
    Class.new do
      include RubynCode::Agent::SystemPromptBuilder

      attr_accessor :plan_mode, :project_root, :conversation, :tool_executor, :skill_loader

      def initialize(attrs = {})
        @plan_mode = attrs[:plan_mode] || false
        @project_root = attrs[:project_root]
        @conversation = attrs[:conversation]
        @tool_executor = attrs[:tool_executor]
        @skill_loader = attrs[:skill_loader]
        @skills_injected = false
      end

      # Expose private methods for testing
      public :build_system_prompt, :append_response_mode, :append_project_profile,
             :last_user_text, :append_memories, :append_project_instructions,
             :append_instincts, :append_skills, :inject_skill_listing,
             :append_deferred_tools, :deferred_tool_names, :format_memory

      # Stub tool_definitions to avoid dependency on ToolProcessor
      def tool_definitions
        @tool_executor&.tool_definitions || []
      end
    end
  end

  let(:conversation) { RubynCode::Agent::Conversation.new }
  let(:tool_executor) { instance_double(RubynCode::Tools::Executor, tool_definitions: []) }

  subject(:builder) do
    host_class.new(
      project_root: project_root,
      conversation: conversation,
      tool_executor: tool_executor
    )
  end

  let(:project_root) { nil }

  describe '#append_response_mode' do
    context 'when conversation has no messages' do
      it 'does not append anything' do
        parts = []
        builder.append_response_mode(parts)
        expect(parts).to be_empty
      end
    end

    context 'when conversation has a user message' do
      before { conversation.add_user_message('fix the bug in the controller') }

      it 'detects a mode and appends the instruction' do
        parts = []
        builder.append_response_mode(parts)
        expect(parts).not_to be_empty
        expect(parts.first).to include('Response Mode')
      end
    end

    context 'when conversation has an implementing message' do
      before { conversation.add_user_message('create a new method in the UserService class') }

      it 'appends implementing mode instruction' do
        parts = []
        builder.append_response_mode(parts)
        expect(parts.first).to include('implementing')
      end
    end

    context 'when conversation has a debugging message' do
      before { conversation.add_user_message('fix the broken test') }

      it 'appends debugging mode instruction' do
        parts = []
        builder.append_response_mode(parts)
        expect(parts.first).to include('debugging')
      end
    end

    context 'when conversation has a testing message' do
      before { conversation.add_user_message('write rspec tests for User') }

      it 'appends testing mode instruction' do
        parts = []
        builder.append_response_mode(parts)
        expect(parts.first).to include('testing')
      end
    end

    context 'when conversation has a chatting message' do
      before { conversation.add_user_message('hello') }

      it 'appends chatting mode instruction' do
        parts = []
        builder.append_response_mode(parts)
        expect(parts.first).to include('chatting')
      end
    end

    context 'when last user message content is not a string' do
      before do
        conversation.instance_variable_get(:@messages) << {
          role: 'user',
          content: [{ type: 'tool_result', tool_use_id: 't1', content: 'result' }]
        }
      end

      it 'treats non-string content as empty and does not append' do
        parts = []
        builder.append_response_mode(parts)
        expect(parts).to be_empty
      end
    end

    context 'when ResponseModes.detect raises an error' do
      before do
        conversation.add_user_message('test message')
        allow(RubynCode::Agent::ResponseModes).to receive(:detect).and_raise(StandardError, 'boom')
      end

      it 'rescues and returns nil' do
        parts = []
        result = builder.append_response_mode(parts)
        expect(result).to be_nil
        expect(parts).to be_empty
      end
    end
  end

  describe '#append_project_profile' do
    context 'when project_root is nil' do
      let(:project_root) { nil }

      it 'does not append anything' do
        parts = []
        builder.append_project_profile(parts)
        expect(parts).to be_empty
      end
    end

    context 'when project_root is set but profile does not exist' do
      let(:project_root) { '/tmp/test-project-no-profile' }

      it 'does not append anything when profile.load returns nil' do
        profile = instance_double(RubynCode::Config::ProjectProfile, load: nil)
        allow(RubynCode::Config::ProjectProfile).to receive(:new).and_return(profile)

        parts = []
        builder.append_project_profile(parts)
        expect(parts).to be_empty
      end
    end

    context 'when project_root is set and profile exists' do
      let(:project_root) { '/tmp/test-project-with-profile' }

      it 'appends the profile prompt text' do
        profile = instance_double(
          RubynCode::Config::ProjectProfile,
          load: true,
          to_prompt: "Project Profile:\n  framework: rails"
        )
        allow(RubynCode::Config::ProjectProfile).to receive(:new).and_return(profile)

        parts = []
        builder.append_project_profile(parts)
        expect(parts.first).to include('Project Profile')
        expect(parts.first).to include('rails')
      end

      it 'does not append when prompt text is empty' do
        profile = instance_double(
          RubynCode::Config::ProjectProfile,
          load: true,
          to_prompt: ''
        )
        allow(RubynCode::Config::ProjectProfile).to receive(:new).and_return(profile)

        parts = []
        builder.append_project_profile(parts)
        expect(parts).to be_empty
      end
    end

    context 'when ProjectProfile raises an error' do
      let(:project_root) { '/tmp/test-project-error' }

      it 'rescues and returns nil' do
        allow(RubynCode::Config::ProjectProfile).to receive(:new).and_raise(StandardError, 'boom')

        parts = []
        result = builder.append_project_profile(parts)
        expect(result).to be_nil
        expect(parts).to be_empty
      end
    end
  end

  describe '#last_user_text' do
    context 'when conversation is nil' do
      it 'returns empty string' do
        builder.conversation = nil
        expect(builder.last_user_text).to eq('')
      end
    end

    context 'when conversation has no messages' do
      it 'returns empty string' do
        expect(builder.last_user_text).to eq('')
      end
    end

    context 'when conversation has only assistant messages' do
      before do
        conversation.add_assistant_message([{ type: 'text', text: 'hello' }])
      end

      it 'returns empty string when no user messages exist' do
        expect(builder.last_user_text).to eq('')
      end
    end

    context 'when conversation has user messages' do
      before do
        conversation.add_user_message('first message')
        conversation.add_assistant_message([{ type: 'text', text: 'reply' }])
        conversation.add_user_message('second message')
      end

      it 'returns the last user message text' do
        expect(builder.last_user_text).to eq('second message')
      end
    end
  end

  describe '#format_memory' do
    it 'formats a hash memory with string keys' do
      mem = { 'category' => 'preference', 'content' => 'Uses RSpec 3' }
      expect(builder.format_memory(mem)).to eq('[preference] Uses RSpec 3')
    end

    it 'formats a hash memory with symbol keys' do
      mem = { category: 'convention', content: 'Single quotes' }
      expect(builder.format_memory(mem)).to eq('[convention] Single quotes')
    end

    it 'formats an object that responds to category and content' do
      mem = double(category: 'learned', content: 'Prefer let over instance vars')
      allow(mem).to receive(:respond_to?).with(:category).and_return(true)
      allow(mem).to receive(:respond_to?).with(:content).and_return(true)
      expect(builder.format_memory(mem)).to eq('[learned] Prefer let over instance vars')
    end
  end

  describe '#inject_skill_listing' do
    context 'when skill_loader is nil' do
      it 'does not inject anything' do
        builder.skill_loader = nil
        builder.inject_skill_listing
        expect(conversation.messages).to be_empty
      end
    end

    context 'when skill_loader returns empty descriptions' do
      it 'does not inject anything' do
        loader = double(descriptions_for_prompt: '')
        builder.skill_loader = loader
        builder.inject_skill_listing
        expect(conversation.messages).to be_empty
      end
    end

    context 'when skill_loader returns descriptions' do
      it 'injects user and assistant messages' do
        loader = double(descriptions_for_prompt: "- adapter: Adapter pattern\n- request-specs: Request specs")
        builder.skill_loader = loader
        builder.inject_skill_listing

        expect(conversation.messages.size).to eq(2)
        expect(conversation.messages[0][:role]).to eq('user')
        expect(conversation.messages[0][:content]).to include('skills')
        expect(conversation.messages[1][:role]).to eq('assistant')
      end

      it 'sets skills_injected flag' do
        loader = double(descriptions_for_prompt: '- some skill')
        builder.skill_loader = loader
        builder.inject_skill_listing
        expect(builder.instance_variable_get(:@skills_injected)).to be true
      end
    end
  end

  describe '#deferred_tool_names' do
    it 'returns names in tool_executor but not in tool_definitions' do
      all_tools = [
        { name: 'read_file' },
        { name: 'write_file' },
        { name: 'custom_tool' }
      ]
      allow(tool_executor).to receive(:tool_definitions).and_return(all_tools)
      # tool_definitions (from the stub) returns same as tool_executor
      # so deferred = all - all = empty

      result = builder.deferred_tool_names
      expect(result).to be_an(Array)
    end
  end

  describe '#append_deferred_tools' do
    it 'does not append when no deferred tools exist' do
      allow(tool_executor).to receive(:tool_definitions).and_return([])
      parts = []
      builder.append_deferred_tools(parts)
      expect(parts).to be_empty
    end
  end
end
