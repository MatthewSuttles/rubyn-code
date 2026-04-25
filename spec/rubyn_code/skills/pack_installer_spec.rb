# frozen_string_literal: true

require_relative 'skill_packs_spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe RubynCode::Skills::PackInstaller do
  let(:tmpdir) { Dir.mktmpdir('rubyn_installer_test_') }
  let(:registry_client) { instance_double(RubynCode::Skills::RegistryClient) }
  subject(:installer) do
    described_class.new(registry_client: registry_client, project_root: tmpdir)
  end

  after { FileUtils.remove_entry(tmpdir) }

  let(:stripe_meta) do
    {
      'name' => 'stripe',
      'displayName' => 'Stripe',
      'version' => '1.0.0',
      'files' => [
        { 'path' => 'webhooks.md', 'title' => 'Webhook handling', 'size' => 4200 },
        { 'path' => 'checkout_sessions.md', 'title' => 'Checkout Sessions', 'size' => 3800 }
      ]
    }
  end

  let(:stripe_meta_v2) do
    stripe_meta.merge('version' => '2.0.0')
  end

  def skills_dir
    File.join(tmpdir, '.rubyn-code', 'skills')
  end

  def pack_dir(name)
    File.join(skills_dir, name)
  end

  def manifest_path(name)
    File.join(pack_dir(name), '.manifest.json')
  end

  def read_manifest(name)
    JSON.parse(File.read(manifest_path(name)))
  end

  describe '#install' do
    before do
      allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta)
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'webhooks.md', etag: nil)
        .and_return({ content: '# Webhooks', etag: '"etag1"', not_modified: false })
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'checkout_sessions.md', etag: nil)
        .and_return({ content: '# Checkout', etag: '"etag2"', not_modified: false })
    end

    it 'downloads and installs pack files' do
      results = installer.install(['stripe'])

      expect(results.first[:status]).to eq(:installed)
      expect(results.first[:files]).to contain_exactly('webhooks.md', 'checkout_sessions.md')
      expect(File.read(File.join(pack_dir('stripe'), 'webhooks.md'))).to eq('# Webhooks')
      expect(File.read(File.join(pack_dir('stripe'), 'checkout_sessions.md'))).to eq('# Checkout')
    end

    it 'writes a manifest file with version and timestamp' do
      installer.install(['stripe'])

      manifest = read_manifest('stripe')
      expect(manifest['name']).to eq('stripe')
      expect(manifest['version']).to eq('1.0.0')
      expect(manifest['installedAt']).to match(/\d{4}-\d{2}-\d{2}T/)
      expect(manifest['skillCount']).to eq(2)
      expect(manifest['files']).to contain_exactly('webhooks.md', 'checkout_sessions.md')
    end

    it 'saves ETags for conditional fetching' do
      installer.install(['stripe'])

      etags_path = File.join(pack_dir('stripe'), '.etags.json')
      etags = JSON.parse(File.read(etags_path))
      expect(etags['webhooks.md']).to eq('"etag1"')
      expect(etags['checkout_sessions.md']).to eq('"etag2"')
    end

    it 'yields progress events' do
      events = []
      installer.install(['stripe']) { |event, data| events << [event, data] }

      event_types = events.map(&:first)
      expect(event_types).to include(:fetching, :downloading, :installed)
    end

    it 'installs multiple packs' do
      hotwire_meta = {
        'name' => 'hotwire',
        'displayName' => 'Hotwire',
        'version' => '1.0.0',
        'files' => [{ 'path' => 'turbo_drive.md', 'title' => 'Turbo Drive', 'size' => 3000 }]
      }

      allow(registry_client).to receive(:fetch_pack).with('hotwire').and_return(hotwire_meta)
      allow(registry_client).to receive(:fetch_file)
        .with('hotwire', 'turbo_drive.md', etag: nil)
        .and_return({ content: '# Turbo Drive', etag: '"hw1"', not_modified: false })

      results = installer.install(%w[stripe hotwire])

      expect(results.size).to eq(2)
      expect(results.map { |r| r[:status] }).to all(eq(:installed))
    end

    context 'when pack is already installed at same version' do
      before do
        installer.install(['stripe'])
      end

      it 'reports up_to_date without re-downloading' do
        results = installer.install(['stripe'])

        expect(results.first[:status]).to eq(:up_to_date)
      end

      it 'yields up_to_date event' do
        events = []
        installer.install(['stripe']) { |event, data| events << [event, data] }

        expect(events.map(&:first)).to include(:up_to_date)
      end
    end

    context 'when update flag is set' do
      before do
        installer.install(['stripe'])
      end

      it 're-downloads files even when version matches' do
        # On update, it fetches again using cached ETags
        allow(registry_client).to receive(:fetch_file)
          .with('stripe', 'webhooks.md', etag: '"etag1"')
          .and_return({ content: nil, etag: '"etag1"', not_modified: true })
        allow(registry_client).to receive(:fetch_file)
          .with('stripe', 'checkout_sessions.md', etag: '"etag2"')
          .and_return({ content: nil, etag: '"etag2"', not_modified: true })

        results = installer.install(['stripe'], update: true)

        expect(results.first[:status]).to eq(:installed)
      end
    end

    context 'when a newer version is available' do
      before do
        installer.install(['stripe'])
        allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta_v2)
      end

      it 'installs the update without the update flag (version differs)' do
        allow(registry_client).to receive(:fetch_file)
          .with('stripe', 'webhooks.md', etag: '"etag1"')
          .and_return({ content: '# Updated Webhooks', etag: '"etag3"', not_modified: false })
        allow(registry_client).to receive(:fetch_file)
          .with('stripe', 'checkout_sessions.md', etag: '"etag2"')
          .and_return({ content: '# Updated Checkout', etag: '"etag4"', not_modified: false })

        results = installer.install(['stripe'])

        expect(results.first[:status]).to eq(:installed)
        manifest = read_manifest('stripe')
        expect(manifest['version']).to eq('2.0.0')
      end
    end

    context 'with ETag caching' do
      it 'skips download when server returns 304' do
        # First install
        installer.install(['stripe'])

        # Second install with update flag — cached ETags sent
        allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta_v2)
        allow(registry_client).to receive(:fetch_file)
          .with('stripe', 'webhooks.md', etag: '"etag1"')
          .and_return({ content: nil, etag: '"etag1"', not_modified: true })
        allow(registry_client).to receive(:fetch_file)
          .with('stripe', 'checkout_sessions.md', etag: '"etag2"')
          .and_return({ content: nil, etag: '"etag2"', not_modified: true })

        results = installer.install(['stripe'], update: true)

        # Files were not re-downloaded (304), but status is still :installed
        expect(results.first[:status]).to eq(:installed)
        expect(results.first[:files]).to be_empty
      end

      it 'downloads only changed files' do
        installer.install(['stripe'])

        allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta_v2)
        allow(registry_client).to receive(:fetch_file)
          .with('stripe', 'webhooks.md', etag: '"etag1"')
          .and_return({ content: '# Updated', etag: '"etag_new"', not_modified: false })
        allow(registry_client).to receive(:fetch_file)
          .with('stripe', 'checkout_sessions.md', etag: '"etag2"')
          .and_return({ content: nil, etag: '"etag2"', not_modified: true })

        results = installer.install(['stripe'], update: true)

        expect(results.first[:files]).to eq(['webhooks.md'])
        expect(File.read(File.join(pack_dir('stripe'), 'webhooks.md'))).to eq('# Updated')
      end
    end

    context 'when registry raises an error' do
      it 'yields error event and returns error status' do
        allow(registry_client).to receive(:fetch_pack).with('broken')
          .and_raise(RubynCode::Skills::RegistryError, 'Connection refused')

        events = []
        results = installer.install(['broken']) { |event, data| events << [event, data] }

        expect(results.first[:status]).to eq(:error)
        expect(results.first[:message]).to include('Connection refused')
        expect(events.map(&:first)).to include(:error)
      end
    end
  end

  describe '#remove' do
    before do
      allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta)
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'webhooks.md', etag: nil)
        .and_return({ content: '# Webhooks', etag: '"etag1"', not_modified: false })
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'checkout_sessions.md', etag: nil)
        .and_return({ content: '# Checkout', etag: '"etag2"', not_modified: false })
      installer.install(['stripe'])
    end

    it 'removes the pack directory' do
      expect(installer.remove('stripe')).to be true
      expect(Dir.exist?(pack_dir('stripe'))).to be false
    end

    it 'returns false when pack is not installed' do
      expect(installer.remove('nonexistent')).to be false
    end
  end

  describe '#installed_packs' do
    it 'returns empty array when no packs installed' do
      expect(installer.installed_packs).to eq([])
    end

    it 'returns manifests for installed packs' do
      allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta)
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'webhooks.md', etag: nil)
        .and_return({ content: '# Webhooks', etag: '"e1"', not_modified: false })
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'checkout_sessions.md', etag: nil)
        .and_return({ content: '# Checkout', etag: '"e2"', not_modified: false })

      installer.install(['stripe'])

      packs = installer.installed_packs
      expect(packs.size).to eq(1)
      expect(packs.first['name']).to eq('stripe')
      expect(packs.first['version']).to eq('1.0.0')
    end
  end

  describe '#installed?' do
    it 'returns false for a pack that is not installed' do
      expect(installer.installed?('stripe')).to be false
    end

    it 'returns true for an installed pack' do
      allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta)
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'webhooks.md', etag: nil)
        .and_return({ content: '# W', etag: '"e1"', not_modified: false })
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'checkout_sessions.md', etag: nil)
        .and_return({ content: '# C', etag: '"e2"', not_modified: false })

      installer.install(['stripe'])

      expect(installer.installed?('stripe')).to be true
    end
  end

  describe '#update_all' do
    it 'returns empty array when no packs installed' do
      expect(installer.update_all).to eq([])
    end

    it 'updates all installed packs' do
      allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta)
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'webhooks.md', etag: nil)
        .and_return({ content: '# W', etag: '"e1"', not_modified: false })
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'checkout_sessions.md', etag: nil)
        .and_return({ content: '# C', etag: '"e2"', not_modified: false })

      installer.install(['stripe'])

      # Now update_all re-fetches with update: true
      allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta_v2)
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'webhooks.md', etag: '"e1"')
        .and_return({ content: '# Updated', etag: '"e3"', not_modified: false })
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'checkout_sessions.md', etag: '"e2"')
        .and_return({ content: nil, etag: '"e2"', not_modified: true })

      results = installer.update_all
      expect(results.first[:status]).to eq(:installed)
      expect(results.first[:files]).to eq(['webhooks.md'])
    end
  end

  describe '#read_manifest' do
    it 'returns nil for a pack that is not installed' do
      expect(installer.read_manifest('stripe')).to be_nil
    end

    it 'returns nil for corrupted manifest' do
      dir = pack_dir('stripe')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, '.manifest.json'), 'not json')

      expect(installer.read_manifest('stripe')).to be_nil
    end
  end

  describe 'global install' do
    let(:global_home) { File.join(tmpdir, '.rubyn-code-global') }
    let(:global_installer) do
      stub_const('RubynCode::Config::Defaults::HOME_DIR', global_home)
      described_class.new(registry_client: registry_client, project_root: tmpdir, global: true)
    end

    it 'installs to the global skills directory' do
      allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta)
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'webhooks.md', etag: nil)
        .and_return({ content: '# W', etag: '"e1"', not_modified: false })
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'checkout_sessions.md', etag: nil)
        .and_return({ content: '# C', etag: '"e2"', not_modified: false })

      global_installer.install(['stripe'])

      global_pack = File.join(global_home, 'skills', 'stripe')
      expect(Dir.exist?(global_pack)).to be true
      expect(File.exist?(File.join(global_pack, 'webhooks.md'))).to be true
    end
  end

  describe 'offline fallback' do
    it 'preserves cached files when registry is down on update' do
      # Initial install succeeds
      allow(registry_client).to receive(:fetch_pack).with('stripe').and_return(stripe_meta)
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'webhooks.md', etag: nil)
        .and_return({ content: '# Webhooks', etag: '"e1"', not_modified: false })
      allow(registry_client).to receive(:fetch_file)
        .with('stripe', 'checkout_sessions.md', etag: nil)
        .and_return({ content: '# Checkout', etag: '"e2"', not_modified: false })

      installer.install(['stripe'])

      # Update attempt fails — registry is down
      allow(registry_client).to receive(:fetch_pack).with('stripe')
        .and_raise(RubynCode::Skills::RegistryError, 'Connection refused')

      results = installer.install(['stripe'], update: true)
      expect(results.first[:status]).to eq(:error)

      # But cached files are still there
      expect(File.exist?(File.join(pack_dir('stripe'), 'webhooks.md'))).to be true
      expect(File.read(File.join(pack_dir('stripe'), 'webhooks.md'))).to eq('# Webhooks')
    end
  end
end
