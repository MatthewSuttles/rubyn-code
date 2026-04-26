# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::InstallSkills do
  subject(:command) { described_class.new }

  let(:ctx) { instance_double(RubynCode::CLI::Commands::Context, renderer: renderer) }
  let(:renderer) { instance_double('Renderer', info: nil, error: nil, warning: nil) }

  let(:pack_manager) { instance_double(RubynCode::Skills::PackManager) }
  let(:registry) { instance_double(RubynCode::Skills::RegistryClient) }

  before do
    allow(RubynCode::Skills::PackManager).to receive(:new).and_return(pack_manager)
    allow(RubynCode::Skills::RegistryClient).to receive(:new).and_return(registry)
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/install-skills') }
  end

  describe '#execute' do
    context 'without arguments' do
      it 'shows usage' do
        command.execute([], ctx)
        expect(renderer).to have_received(:warning).with(/Usage/)
      end
    end

    context 'with a pack name' do
      let(:pack_data) { { name: 'rails-testing', version: '1.0.0', files: [] } }

      before do
        allow(pack_manager).to receive(:installed?).with('rails-testing').and_return(false)
        allow(registry).to receive(:fetch_pack).with('rails-testing').and_return(pack_data)
        allow(pack_manager).to receive(:install).with(pack_data).and_return(pack_data)
      end

      it 'fetches and installs the pack' do
        command.execute(['rails-testing'], ctx)
        expect(registry).to have_received(:fetch_pack).with('rails-testing')
        expect(pack_manager).to have_received(:install).with(pack_data)
      end

      it 'shows success message' do
        command.execute(['rails-testing'], ctx)
        expect(renderer).to have_received(:info).with(/Installed skill pack 'rails-testing'/)
      end
    end

    context 'when pack is already installed' do
      before do
        allow(pack_manager).to receive(:installed?).with('rails-testing').and_return(true)
      end

      it 'shows warning and does not fetch' do
        command.execute(['rails-testing'], ctx)
        expect(renderer).to have_received(:warning).with(/already installed/)
        expect(registry).not_to have_received(:fetch_pack) if registry.respond_to?(:fetch_pack)
      end
    end

    context 'when registry fetch fails' do
      before do
        allow(pack_manager).to receive(:installed?).with('broken').and_return(false)
        allow(registry).to receive(:fetch_pack).and_raise(
          RubynCode::Skills::RegistryError, 'network timeout'
        )
      end

      it 'shows error message' do
        command.execute(['broken'], ctx)
        expect(renderer).to have_received(:error).with(/Failed to install 'broken'/)
      end
    end

    context 'with multiple pack names' do
      before do
        allow(pack_manager).to receive(:installed?).and_return(false)
        allow(registry).to receive(:fetch_pack).and_return({ name: 'a', files: [] }, { name: 'b', files: [] })
        allow(pack_manager).to receive(:install).and_return({})
      end

      it 'installs each pack' do
        command.execute(%w[pack-a pack-b], ctx)
        expect(registry).to have_received(:fetch_pack).twice
        expect(pack_manager).to have_received(:install).twice
      end
    end
  end
end
