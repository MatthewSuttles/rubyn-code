# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Compact do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      llm_client: llm_client,
      conversation: conversation,
      renderer: renderer
    )
  end
  let(:llm_client) { double('LLMClient') }
  let(:conversation) { instance_double('Conversation', messages: [], replace!: nil, length: 3) }
  let(:renderer) { instance_double('Renderer', info: nil) }
  let(:compactor) { instance_double(RubynCode::Context::Compactor, manual_compact!: []) }

  before do
    allow(RubynCode::Context::Compactor).to receive(:new).and_return(compactor)
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/compact') }
  end

  describe '#execute' do
    it 'creates a compactor and compacts' do
      command.execute([], ctx)
      expect(compactor).to have_received(:manual_compact!).with([], focus: nil)
    end

    it 'passes focus when provided' do
      command.execute(['auth'], ctx)
      expect(compactor).to have_received(:manual_compact!).with([], focus: 'auth')
    end

    it 'replaces conversation messages' do
      command.execute([], ctx)
      expect(conversation).to have_received(:replace!)
    end

    it 'shows compaction result' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/compacted.*3 messages/i)
    end
  end
end
