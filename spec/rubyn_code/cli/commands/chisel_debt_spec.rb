# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::CLI::Commands::ChiselDebt do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double('Renderer', info: nil) }
  let(:ctx) { instance_double(RubynCode::CLI::Commands::Context, renderer: renderer, project_root: root) }

  around do |example|
    Dir.mktmpdir('chisel_debt_cmd_') do |dir|
      @dir = dir
      example.run
    end
  end
  let(:root) { @dir }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/chisel-debt') }
  end

  describe '#execute' do
    it 'reports a clean message when there are no markers' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/clean/i)
    end

    it 'lists each marker with location and note' do
      FileUtils.mkdir_p(File.join(root, 'lib'))
      File.write(File.join(root, 'lib', 'a.rb'), "# chisel: collapse this\n")

      command.execute([], ctx)

      expect(renderer).to have_received(:info).with(/1 deferred simplification:/)
      expect(renderer).to have_received(:info).with(%r{lib/a\.rb:1 — collapse this})
    end
  end
end
