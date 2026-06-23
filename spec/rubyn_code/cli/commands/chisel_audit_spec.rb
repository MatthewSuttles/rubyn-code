# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::ChiselAudit do
  subject(:command) { described_class.new }

  let(:ctx) { instance_double(RubynCode::CLI::Commands::Context, send_message: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/chisel-audit') }
  end

  describe '#execute' do
    it 'sweeps the whole repo by default' do
      command.execute([], ctx)
      expect(ctx).to have_received(:send_message).with(/whole repository/)
    end

    it 'scopes the sweep to a given path' do
      command.execute(['lib/rubyn_code/agent'], ctx)
      expect(ctx).to have_received(:send_message).with(%r{lib/rubyn_code/agent})
    end

    it 'sends a read-only deletion-list prompt' do
      command.execute([], ctx)
      expect(ctx).to have_received(:send_message).with(%r{ranked deletion/simplification list})
    end
  end
end
