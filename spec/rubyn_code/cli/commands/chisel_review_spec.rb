# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::ChiselReview do
  subject(:command) { described_class.new }

  let(:ctx) { instance_double(RubynCode::CLI::Commands::Context, send_message: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/chisel-review') }
  end

  describe '#execute' do
    it 'reviews against main by default' do
      command.execute([], ctx)
      expect(ctx).to have_received(:send_message).with(/git diff main\.\.\./)
    end

    it 'uses a custom base ref' do
      command.execute(['develop'], ctx)
      expect(ctx).to have_received(:send_message).with(/git diff develop\.\.\./)
    end

    it 'sends a read-only deletion-list prompt' do
      command.execute([], ctx)
      expect(ctx).to have_received(:send_message).with(%r{ranked deletion/simplification list})
    end
  end
end
