# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Chisel do
  subject(:command) { described_class.new }

  let(:config_dir) { Dir.mktmpdir('rubyn_chisel_') }
  let(:settings) do
    RubynCode::Config::Settings.new(config_path: File.join(config_dir, 'config.yml'))
  end
  let(:renderer) { instance_double('Renderer', info: nil, warning: nil) }
  let(:ctx) { instance_double(RubynCode::CLI::Commands::Context, renderer: renderer) }

  before do
    # Both the command and Chisel.mode build Settings via .new — point them at
    # an isolated temp config so the real ~/.rubyn-code is never touched.
    allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)
    ENV.delete('RUBYN_CHISEL_MODE')
  end

  after { FileUtils.rm_rf(config_dir) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/chisel') }
  end

  describe '#execute' do
    context 'without arguments' do
      it 'reports the current mode and the available modes' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with('Chisel: off')
        expect(renderer).to have_received(:info).with('Modes: off | lite | full | ultra')
      end
    end

    context 'with a valid mode' do
      it 'persists it and confirms' do
        command.execute(['full'], ctx)
        expect(settings.get('chisel_mode')).to eq('full')
        expect(renderer).to have_received(:info).with(/set to full/)
      end

      it 'normalizes case and whitespace' do
        command.execute(['  ULTRA '], ctx)
        expect(settings.get('chisel_mode')).to eq('ultra')
      end

      it 'turning off reports the off message' do
        command.execute(['off'], ctx)
        expect(settings.get('chisel_mode')).to eq('off')
        expect(renderer).to have_received(:info).with(/behaves normally/)
      end
    end

    context 'with an invalid mode' do
      it 'warns and leaves the mode unchanged' do
        command.execute(['aggressive'], ctx)
        expect(renderer).to have_received(:warning).with(/Unknown Chisel mode/)
        expect(settings.get('chisel_mode')).to eq('off')
      end
    end
  end
end
