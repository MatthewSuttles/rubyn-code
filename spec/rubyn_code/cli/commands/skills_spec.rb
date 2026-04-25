# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Skills do
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
    it { expect(described_class.command_name).to eq('/skills') }
  end

  describe '#execute' do
    context 'without arguments (list installed)' do
      it 'shows empty message when no packs installed' do
        allow(pack_manager).to receive(:installed).and_return([])
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/No skill packs installed/)
      end

      it 'lists installed packs' do
        packs = [
          { name: 'rails-testing', version: '1.0.0', description: 'Rails testing patterns' },
          { name: 'factory-bot', version: '2.0.0', description: 'Factory Bot guide' }
        ]
        allow(pack_manager).to receive(:installed).and_return(packs)
        expect { command.execute([], ctx) }.to output(/rails-testing/).to_stdout
      end
    end

    context 'with "list" subcommand' do
      it 'lists installed packs' do
        allow(pack_manager).to receive(:installed).and_return([])
        command.execute(['list'], ctx)
        expect(renderer).to have_received(:info).with(/No skill packs installed/)
      end
    end

    context 'with "available" subcommand' do
      it 'fetches and displays registry packs' do
        packs = [
          { name: 'rails-testing', description: 'Rails testing' },
          { name: 'rspec', description: 'RSpec patterns' }
        ]
        allow(registry).to receive(:list_packs).and_return(packs)
        allow(pack_manager).to receive(:installed?).and_return(false)
        expect { command.execute(['available'], ctx) }.to output(/rails-testing/).to_stdout
      end

      it 'shows empty message when no packs in registry' do
        allow(registry).to receive(:list_packs).and_return([])
        command.execute(['available'], ctx)
        expect(renderer).to have_received(:info).with(/No packs found/)
      end

      it 'marks installed packs' do
        packs = [{ name: 'rails-testing', description: 'Rails testing' }]
        allow(registry).to receive(:list_packs).and_return(packs)
        allow(pack_manager).to receive(:installed?).with('rails-testing').and_return(true)
        expect { command.execute(['available'], ctx) }.to output(/\[installed\]/).to_stdout
      end
    end

    context 'with "search" subcommand' do
      it 'searches the registry' do
        results = [{ name: 'rails-testing', description: 'Rails testing patterns' }]
        allow(registry).to receive(:search_packs).with('rails').and_return(results)
        expect { command.execute(%w[search rails], ctx) }.to output(/rails-testing/).to_stdout
      end

      it 'shows no results message' do
        allow(registry).to receive(:search_packs).with('nonexistent').and_return([])
        command.execute(%w[search nonexistent], ctx)
        expect(renderer).to have_received(:info).with(/No packs found matching/)
      end

      it 'shows usage when no search term' do
        command.execute(['search'], ctx)
        expect(renderer).to have_received(:warning).with(/Usage/)
      end
    end

    context 'with unknown subcommand' do
      it 'shows warning' do
        command.execute(['bogus'], ctx)
        expect(renderer).to have_received(:warning).with(/Unknown subcommand/)
      end
    end

    context 'when registry raises error' do
      it 'shows error message' do
        allow(registry).to receive(:list_packs).and_raise(
          RubynCode::Skills::RegistryError, 'connection refused'
        )
        command.execute(['available'], ctx)
        expect(renderer).to have_received(:error).with(/connection refused/)
      end
    end
  end
end
