# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Undo do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      conversation: conversation,
      renderer: renderer
    )
  end
  let(:conversation) { instance_double('Conversation', undo_last!: nil) }
  let(:renderer) { instance_double('Renderer', info: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/undo') }
  end

  describe '#execute' do
    it 'removes the last exchange' do
      command.execute([], ctx)
      expect(conversation).to have_received(:undo_last!)
    end

    it 'shows confirmation' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/removed/i)
    end
  end
end
