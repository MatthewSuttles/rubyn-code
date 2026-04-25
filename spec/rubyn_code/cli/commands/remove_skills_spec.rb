# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::RemoveSkills do
  subject(:command) { described_class.new }

  let(:ctx) { instance_double(RubynCode::CLI::Commands::Context, renderer: renderer) }
  let(:renderer) { instance_double('Renderer', info: nil, error: nil, warning: nil) }

  let(:pack_manager) { instance_double(RubynCode::Skills::PackManager) }

  before do
    allow(RubynCode::Skills::PackManager).to receive(:new).and_return(pack_manager)
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/remove-skills') }
  end

  describe '#execute' do
    context 'without arguments' do
      it 'shows usage' do
        command.execute([], ctx)
        expect(renderer).to have_received(:warning).with(/Usage/)
      end
    end

    context 'with an installed pack name' do
      before do
        allow(pack_manager).to receive(:installed?).with('rails-testing').and_return(true)
        allow(pack_manager).to receive(:remove).with('rails-testing').and_return(true)
      end

      it 'removes the pack' do
        command.execute(['rails-testing'], ctx)
        expect(pack_manager).to have_received(:remove).with('rails-testing')
      end

      it 'shows success message' do
        command.execute(['rails-testing'], ctx)
        expect(renderer).to have_received(:info).with(/Removed skill pack 'rails-testing'/)
      end
    end

    context 'when pack is not installed' do
      before do
        allow(pack_manager).to receive(:installed?).with('nonexistent').and_return(false)
      end

      it 'shows warning' do
        command.execute(['nonexistent'], ctx)
        expect(renderer).to have_received(:warning).with(/not installed/)
      end
    end

    context 'with multiple pack names' do
      before do
        allow(pack_manager).to receive(:installed?).and_return(true)
        allow(pack_manager).to receive(:remove).and_return(true)
      end

      it 'removes each pack' do
        command.execute(%w[pack-a pack-b], ctx)
        expect(pack_manager).to have_received(:remove).twice
      end
    end
  end
end
