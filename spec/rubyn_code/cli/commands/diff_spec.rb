# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Diff do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      project_root: '/tmp/test',
      renderer: renderer
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/diff') }
  end

  describe '#execute' do
    before do
      allow(command).to receive(:`).and_return('')
    end

    context 'with no changes' do
      it 'shows no changes message' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/No changes/)
      end
    end

    context 'with changes' do
      before { allow(command).to receive(:`).and_return('+ new line') }

      it 'prints the diff' do
        expect { command.execute([], ctx) }.to output(/new line/).to_stdout
      end
    end

    context 'with staged target' do
      it 'runs git diff --cached' do
        command.execute(['staged'], ctx)
        expect(command).to have_received(:`).with(/git diff --cached/)
      end
    end
  end
end
