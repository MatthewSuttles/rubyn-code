# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Review do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      send_message: nil
    )
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/review') }
  end

  describe '#execute' do
    it 'sends a review request with defaults' do
      command.execute([], ctx)
      expect(ctx).to have_received(:send_message).with(/main.*all/m)
    end

    it 'uses custom base branch' do
      command.execute(['develop'], ctx)
      expect(ctx).to have_received(:send_message).with(/develop/)
    end

    it 'uses custom focus area' do
      command.execute(%w[main security], ctx)
      expect(ctx).to have_received(:send_message).with(/security/)
    end
  end
end
