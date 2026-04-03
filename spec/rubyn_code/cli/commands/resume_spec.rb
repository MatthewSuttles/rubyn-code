# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Resume do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      session_persistence: session_persistence,
      conversation: conversation,
      project_root: '/tmp/test'
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil, error: nil) }
  let(:conversation) { instance_double('Conversation', replace!: nil) }
  let(:session_persistence) do
    instance_double('SessionPersistence',
                    load_session: nil,
                    list_sessions: [])
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/resume') }
  end

  describe '#execute' do
    context 'with a session ID' do
      let(:session_data) { { messages: [{ role: 'user', content: 'hi' }] } }

      before do
        allow(session_persistence).to receive(:load_session)
          .with('abc12345').and_return(session_data)
      end

      it 'restores the conversation' do
        command.execute(['abc12345'], ctx)
        expect(conversation).to have_received(:replace!).with(session_data[:messages])
      end

      it 'returns session ID action' do
        result = command.execute(['abc12345'], ctx)
        expect(result).to eq(action: :set_session_id, session_id: 'abc12345')
      end
    end

    context 'with unknown session ID' do
      it 'shows error' do
        command.execute(['unknown'], ctx)
        expect(renderer).to have_received(:error).with(/not found/)
      end
    end

    context 'without arguments' do
      it 'lists recent sessions' do
        allow(session_persistence).to receive(:list_sessions).and_return([])
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/No previous/)
      end
    end

    context 'with sessions to list' do
      let(:sessions) do
        [{ id: 'abc12345-6789', title: 'My session', created_at: '2025-01-01' }]
      end

      before do
        allow(session_persistence).to receive(:list_sessions).and_return(sessions)
      end

      it 'prints session list' do
        expect { command.execute([], ctx) }.to output(/My session/).to_stdout
      end
    end
  end
end
