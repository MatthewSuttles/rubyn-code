# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::CLI::Commands::ChiselGain do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double('Renderer', info: nil) }
  let(:ctx) { instance_double(RubynCode::CLI::Commands::Context, renderer: renderer, project_root: root) }

  around do |example|
    Dir.mktmpdir('chisel_gain_') do |dir|
      @dir = dir
      example.run
    end
  end
  let(:root) { @dir }

  before { allow(RubynCode::Chisel).to receive(:mode).and_return('off') }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/chisel-gain') }
  end

  describe '#execute' do
    it 'reports the current mode and hints how to enable when off' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with('Chisel mode: off')
      expect(renderer).to have_received(:info).with(%r{/chisel full})
    end

    it 'reports the outstanding debt marker count' do
      FileUtils.mkdir_p(File.join(root, 'lib'))
      File.write(File.join(root, 'lib', 'a.rb'), "# chisel: one\n# chisel: two\n")

      command.execute([], ctx)

      expect(renderer).to have_received(:info).with(/Outstanding chisel: debt markers: 2/)
    end

    it 'shows an attributed reference impact figure' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/Reference benchmark.*less code/)
    end

    it 'does not hint to enable when already on' do
      allow(RubynCode::Chisel).to receive(:mode).and_return('full')
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with('Chisel mode: full')
      expect(renderer).not_to have_received(:info).with(%r{/chisel full})
    end
  end
end
