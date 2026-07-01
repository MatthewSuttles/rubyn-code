# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Resume do
  subject(:command) { described_class.new }

  let(:renderer) do
    Class.new do
      attr_reader :infos, :errors, :warnings

      def initialize
        @infos = []
        @errors = []
        @warnings = []
      end

      def info(msg)     = (@infos << msg)
      def error(msg)    = (@errors << msg)
      def warning(msg)  = (@warnings << msg)
      def ask(*_args) = true # rubocop:disable Naming/PredicateMethod -- prompt is a verb
    end.new
  end

  let(:conversation) do
    convo = RubynCode::Agent::Conversation.new
    convo.add_user_message('current')
    convo
  end

  let(:ctx) do
    RubynCode::CLI::Commands::Context.new(
      renderer: renderer,
      conversation: conversation,
      agent_loop: nil,
      context_manager: nil,
      budget_enforcer: nil,
      llm_client: nil,
      db: nil,
      session_id: 'current',
      project_root: '/tmp/test',
      skill_loader: nil,
      session_persistence: session_persistence,
      background_worker: nil,
      permission_tier: nil,
      plan_mode: false,
      message_handler: nil,
      hook_registry: nil,
      checkpoint_manager: nil
    )
  end

  let(:session_persistence) do
    double('SessionPersistence',
           load_session: nil,
           list_sessions: [])
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/resume') }
  end

  describe '#execute' do
    context 'with a session ID' do
      let(:session_data) { { messages: [{ role: 'user', content: 'hi' }], title: 'test' } }

      before do
        allow(session_persistence).to receive(:load_session)
          .with('abc12345').and_return(session_data)
      end

      it 'restores the conversation' do
        command.execute(['abc12345'], ctx)
        expect(conversation.messages.last[:content]).to eq('hi')
      end

      it 'reports success' do
        command.execute(['abc12345'], ctx)
        expect(renderer.infos).to include(/Resumed session abc12345/)
      end
    end

    context 'with unknown session ID' do
      it 'shows error' do
        command.execute(['unknown'], ctx)
        expect(renderer.errors).to include(/not found/)
      end
    end

    context 'without arguments' do
      it 'reports no sessions when list is empty' do
        command.execute([], ctx)
        expect(renderer.infos).to include(/No saved sessions yet/)
      end
    end

    context 'with sessions to list' do
      let(:sessions) do
        [{
          session_id: 'abc12345',
          title: 'My session',
          last_activity: Time.now - 300,
          message_count: 7
        }]
      end

      before do
        allow(session_persistence).to receive(:list_sessions).and_return(sessions)
      end

      it 'prints the title and metadata' do
        command.execute([], ctx)
        expect(renderer.infos.join).to include('My session').and include('7 msg')
      end
    end

    context 'confirmation prompt' do
      let(:session_data) { { messages: [{ role: 'user', content: 'x' }], title: 't' } }

      before do
        allow(session_persistence).to receive(:load_session)
          .with('abc').and_return(session_data)
      end

      it 'replaces when user confirms' do
        allow(renderer).to receive(:ask).and_return(true)
        command.execute(['abc'], ctx)
        expect(conversation.messages.size).to eq(1)
        expect(conversation.messages.first[:content]).to eq('x')
      end

      it 'cancels when user declines' do
        allow(renderer).to receive(:ask).and_return(false)
        command.execute(['abc'], ctx)
        expect(conversation.messages.first[:content]).to eq('current')
        expect(renderer.infos).to include(/cancelled/i)
      end
    end

    context 'with --force' do
      let(:session_data) { { messages: [{ role: 'user', content: 'x' }], title: 't' } }

      before do
        allow(session_persistence).to receive(:load_session)
          .with('abc').and_return(session_data)
      end

      it 'skips the confirm prompt' do
        # No allow for ask in this path; force bypasses
        command.execute(['abc', '--force'], ctx)
        expect(conversation.messages.first[:content]).to eq('x')
      end
    end
  end
end
