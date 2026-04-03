# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::ContextInfo do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      conversation: conversation,
      plan_mode?: false
    )
  end
  let(:conversation) { instance_double('Conversation', messages: messages) }
  let(:messages) { Array.new(5) { double('message') } }

  before do
    allow(RubynCode::Observability::TokenCounter).to receive(:estimate_messages).and_return(50_000)
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/context') }
  end

  describe '#execute' do
    it 'prints context bar with percentage' do
      expect { command.execute([], ctx) }.to output(/25\.0%/).to_stdout
    end

    it 'prints message count' do
      expect { command.execute([], ctx) }.to output(/5 messages/).to_stdout
    end

    it 'prints model name' do
      expect { command.execute([], ctx) }.to output(/Model:/).to_stdout
    end

    context 'when plan mode is on' do
      before { allow(ctx).to receive(:plan_mode?).and_return(true) }

      it 'shows plan mode indicator' do
        expect { command.execute([], ctx) }.to output(/plan mode/).to_stdout
      end
    end
  end
end
