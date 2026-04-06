# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::NewSession do
  subject(:command) { described_class.new }

  describe '.command_name' do
    it 'returns /new' do
      expect(described_class.command_name).to eq('/new')
    end
  end

  describe '.description' do
    it 'describes the command' do
      expect(described_class.description).to include('fresh')
    end
  end

  describe '.aliases' do
    it 'includes /reset' do
      expect(described_class.aliases).to include('/reset')
    end
  end

  describe '#execute' do
    let(:conversation) { instance_double(RubynCode::Agent::Conversation, messages: [], clear!: nil) }
    let(:renderer) { double('renderer', info: nil) }
    let(:session_persistence) { double('session_persistence') }
    let(:ctx) do
      double(
        'ctx',
        session_id: 'abc123',
        project_root: '/tmp/project',
        conversation: conversation,
        renderer: renderer,
        session_persistence: session_persistence
      )
    end

    before do
      allow(session_persistence).to receive(:save_session)
      allow(SecureRandom).to receive(:hex).with(16).and_return('deadbeef' * 4)
    end

    it 'saves the current session' do
      command.execute([], ctx)

      expect(session_persistence).to have_received(:save_session).with(
        session_id: 'abc123',
        project_path: '/tmp/project',
        messages: [],
        model: RubynCode::Config::Defaults::DEFAULT_MODEL
      )
    end

    it 'clears the conversation' do
      command.execute([], ctx)
      expect(conversation).to have_received(:clear!)
    end

    it 'displays info messages' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with('Session saved. Starting fresh.')
      expect(renderer).to have_received(:info).with(/New session:/)
    end

    it 'returns a hash with :new_session action' do
      result = command.execute([], ctx)
      expect(result[:action]).to eq(:new_session)
      expect(result[:session_id]).to be_a(String)
      expect(result[:session_id].length).to eq(32)
    end

    it 'generates a new session id' do
      result = command.execute([], ctx)
      expect(result[:session_id]).to eq('deadbeef' * 4)
    end

    it 'shows first 8 chars of new session id in info' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/deadbeef/)
    end
  end
end
