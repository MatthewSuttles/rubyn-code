# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Version do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/version') }
  end

  describe '#execute' do
    it 'displays the version' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/#{Regexp.escape(RubynCode::VERSION)}/)
    end
  end
end
