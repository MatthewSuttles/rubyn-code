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
      it 'lists installed packs' do
        allow(pack_manager).to receive(:installed).and_return([
          { name: 'rails-testing', version: '1.0.0', description: 'Testing patterns' }
        ])

        expect { command.execute([], ctx) }.to output(/rails-testing/).to_stdout
        expect(renderer).to have_received(:info).with(/Installed skill packs/)
      end

      it 'shows message when no packs installed' do
        allow(pack_manager).to receive(:installed).and_return([])
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with(/No skill packs installed/)
      end
    end

    context 'with "list" subcommand' do
      it 'lists installed packs' do
        allow(pack_manager).to receive(:installed).and_return([
          { name: 'api-design', version: '2.0.0', description: 'API patterns' }
        ])

        expect { command.execute(['list'], ctx) }.to output(/api-design/).to_stdout
      end
    end

    context 'with "available" subcommand' do
      it 'fetches and displays registry packs' do
        allow(registry).to receive(:list_packs).and_return([
          { name: 'rails-testing', description: 'Testing patterns' },
          { name: 'api-design', description: 'API patterns' }
        ])
        allow(pack_manager).to receive(:installed?).and_return(false)

        expect { command.execute(['available'], ctx) }.to output(/rails-testing/).to_stdout
        expect(renderer).to have_received(:info).with(/Available skill packs/)
      end

      it 'marks installed packs' do
        allow(registry).to receive(:list_packs).and_return([
          { name: 'rails-testing', description: 'Testing patterns' }
        ])
        allow(pack_manager).to receive(:installed?).with('rails-testing').and_return(true)

        expect { command.execute(['available'], ctx) }.to output(/\[installed\]/).to_stdout
      end

      it 'shows message when registry is empty' do
        allow(registry).to receive(:list_packs).and_return([])
        command.execute(['available'], ctx)
        expect(renderer).to have_received(:info).with(/No packs found/)
      end
    end

    context 'with "search" subcommand' do
      it 'searches the registry' do
        allow(registry).to receive(:search_packs).with('rails').and_return([
          { name: 'rails-testing', description: 'Testing patterns' }
        ])

        expect { command.execute(%w[search rails], ctx) }.to output(/rails-testing/).to_stdout
      end

      it 'shows usage when no search term provided' do
        command.execute(%w[search], ctx)
        expect(renderer).to have_received(:warning).with(/Usage/)
      end

      it 'shows message when no results found' do
        allow(registry).to receive(:search_packs).with('zzz').and_return([])
        command.execute(%w[search zzz], ctx)
        expect(renderer).to have_received(:info).with(/No packs found matching/)
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
