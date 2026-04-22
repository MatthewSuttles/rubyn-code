# frozen_string_literal: true

require_relative '../../skills/skill_packs_spec_helper'
require 'rubyn_code/cli/commands/base'
require 'rubyn_code/cli/commands/context'
require 'rubyn_code/cli/commands/install_skills'

RSpec.describe RubynCode::CLI::Commands::InstallSkills do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double('Renderer', info: nil, success: nil, error: nil, warning: nil) }
  let(:catalog) { instance_double('Catalog', available: []) }
  let(:skill_loader) { instance_double('SkillLoader', catalog: catalog) }
  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      project_root: '/tmp/test-project',
      skill_loader: skill_loader
    )
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/install-skills') }
  end

  describe '#execute' do
    context 'with no arguments' do
      it 'shows usage information' do
        command.execute([], ctx)

        expect(renderer).to have_received(:info).with(/Usage: \/install-skills/)
      end
    end

    context 'with pack names' do
      let(:installer) { instance_double(RubynCode::Skills::PackInstaller) }
      let(:client) { instance_double(RubynCode::Skills::RegistryClient) }

      before do
        allow(RubynCode::Skills::RegistryClient).to receive(:new).and_return(client)
        allow(RubynCode::Skills::PackInstaller).to receive(:new)
          .with(registry_client: client, project_root: '/tmp/test-project', global: false)
          .and_return(installer)
      end

      it 'installs the requested packs' do
        allow(installer).to receive(:install)
          .with(['stripe'], update: false)
          .and_yield(:fetching, { name: 'stripe' })
          .and_yield(:downloading, { name: 'stripe', total: 2, downloaded: 2 })
          .and_yield(:installed, { name: 'stripe', version: '1.0.0', files: ['webhooks.md', 'checkout.md'] })
          .and_return([{ name: 'stripe', status: :installed, files: ['webhooks.md', 'checkout.md'] }])

        expect { command.execute(['stripe'], ctx) }.to output(/webhooks\.md/).to_stdout

        expect(renderer).to have_received(:info).with(/Fetching stripe/)
        expect(renderer).to have_received(:success).with(/Installed 2 skills/)
      end

      it 'handles already-installed packs' do
        allow(installer).to receive(:install)
          .with(['stripe'], update: false)
          .and_yield(:fetching, { name: 'stripe' })
          .and_yield(:up_to_date, { name: 'stripe', version: '1.0.0' })
          .and_return([{ name: 'stripe', status: :up_to_date, files: [] }])

        command.execute(['stripe'], ctx)

        expect(renderer).to have_received(:info).with(/already installed/)
      end

      it 'handles installation errors' do
        allow(installer).to receive(:install)
          .with(['broken'], update: false)
          .and_yield(:error, { name: 'broken', message: 'Pack not found' })
          .and_return([{ name: 'broken', status: :error, message: 'Pack not found' }])

        command.execute(['broken'], ctx)

        expect(renderer).to have_received(:error).with(/Failed to install broken/)
      end
    end

    context 'with --global flag' do
      let(:installer) { instance_double(RubynCode::Skills::PackInstaller) }
      let(:client) { instance_double(RubynCode::Skills::RegistryClient) }

      before do
        allow(RubynCode::Skills::RegistryClient).to receive(:new).and_return(client)
        allow(RubynCode::Skills::PackInstaller).to receive(:new)
          .with(registry_client: client, project_root: '/tmp/test-project', global: true)
          .and_return(installer)
      end

      it 'creates installer with global: true' do
        allow(installer).to receive(:install)
          .with(['stripe'], update: false)
          .and_yield(:installed, { name: 'stripe', version: '1.0.0', files: ['webhooks.md'] })
          .and_return([{ name: 'stripe', status: :installed, files: ['webhooks.md'] }])

        expect { command.execute(['--global', 'stripe'], ctx) }.to output.to_stdout

        expect(RubynCode::Skills::PackInstaller).to have_received(:new)
          .with(hash_including(global: true))
      end
    end

    context 'with --update flag and no pack names' do
      let(:installer) { instance_double(RubynCode::Skills::PackInstaller) }
      let(:client) { instance_double(RubynCode::Skills::RegistryClient) }

      before do
        allow(RubynCode::Skills::RegistryClient).to receive(:new).and_return(client)
        allow(RubynCode::Skills::PackInstaller).to receive(:new)
          .with(registry_client: client, project_root: '/tmp/test-project', global: false)
          .and_return(installer)
      end

      it 'updates all installed packs' do
        allow(installer).to receive(:installed_packs)
          .and_return([{ 'name' => 'stripe', 'version' => '1.0.0' }])
        allow(installer).to receive(:update_all)
          .and_yield(:installed, { name: 'stripe', version: '2.0.0', files: ['webhooks.md'] })
          .and_return([{ name: 'stripe', status: :installed, files: ['webhooks.md'] }])

        command.execute(['--update'], ctx)

        expect(renderer).to have_received(:success).with(/Updated 1 pack/)
      end

      it 'shows message when no packs are installed' do
        allow(installer).to receive(:installed_packs).and_return([])

        command.execute(['--update'], ctx)

        expect(renderer).to have_received(:info).with(/No skill packs installed/)
      end

      it 'shows message when all packs are up to date' do
        allow(installer).to receive(:installed_packs)
          .and_return([{ 'name' => 'stripe', 'version' => '1.0.0' }])
        allow(installer).to receive(:update_all)
          .and_return([{ name: 'stripe', status: :up_to_date, files: [] }])

        command.execute(['--update'], ctx)

        expect(renderer).to have_received(:info).with(/up to date/)
      end
    end

    context 'with --update flag and pack names' do
      let(:installer) { instance_double(RubynCode::Skills::PackInstaller) }
      let(:client) { instance_double(RubynCode::Skills::RegistryClient) }

      before do
        allow(RubynCode::Skills::RegistryClient).to receive(:new).and_return(client)
        allow(RubynCode::Skills::PackInstaller).to receive(:new)
          .with(registry_client: client, project_root: '/tmp/test-project', global: false)
          .and_return(installer)
      end

      it 'installs with update: true' do
        allow(installer).to receive(:install)
          .with(['stripe'], update: true)
          .and_yield(:installed, { name: 'stripe', version: '2.0.0', files: ['webhooks.md'] })
          .and_return([{ name: 'stripe', status: :installed, files: ['webhooks.md'] }])

        expect { command.execute(['--update', 'stripe'], ctx) }.to output.to_stdout

        expect(installer).to have_received(:install).with(['stripe'], update: true)
      end
    end

    context 'when RegistryError is raised' do
      before do
        allow(RubynCode::Skills::RegistryClient).to receive(:new)
          .and_raise(RubynCode::Skills::RegistryError, 'Connection refused')
      end

      it 'shows the error message' do
        command.execute(['stripe'], ctx)

        expect(renderer).to have_received(:error).with(/Registry error: Connection refused/)
      end
    end

    context 'when unexpected error is raised' do
      before do
        allow(RubynCode::Skills::RegistryClient).to receive(:new)
          .and_raise(StandardError, 'something broke')
      end

      it 'shows the error message' do
        command.execute(['stripe'], ctx)

        expect(renderer).to have_received(:error).with(/Install failed: something broke/)
      end
    end

    context 'skill loader reload' do
      let(:installer) { instance_double(RubynCode::Skills::PackInstaller) }
      let(:client) { instance_double(RubynCode::Skills::RegistryClient) }

      before do
        allow(RubynCode::Skills::RegistryClient).to receive(:new).and_return(client)
        allow(RubynCode::Skills::PackInstaller).to receive(:new).and_return(installer)
        allow(catalog).to receive(:respond_to?).with(:available).and_return(true)
        allow(catalog).to receive(:instance_variable_set).with(:@index, nil)
      end

      it 'reloads skills after installation' do
        allow(installer).to receive(:install)
          .with(['stripe'], update: false)
          .and_yield(:installed, { name: 'stripe', version: '1.0.0', files: ['webhooks.md'] })
          .and_return([{ name: 'stripe', status: :installed, files: ['webhooks.md'] }])

        expect { command.execute(['stripe'], ctx) }.to output.to_stdout

        expect(catalog).to have_received(:instance_variable_set).with(:@index, nil)
      end
    end
  end
end
