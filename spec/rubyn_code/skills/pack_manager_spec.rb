# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe RubynCode::Skills::PackManager do
  let(:tmpdir) { Dir.mktmpdir }
  let(:packs_dir) { File.join(tmpdir, 'skill-packs') }

  subject(:manager) { described_class.new(packs_dir: packs_dir) }

  after { FileUtils.remove_entry(tmpdir) }

  let(:pack_data) do
    {
      name: 'rails-testing',
      description: 'Rails testing patterns and best practices',
      version: '1.2.0',
      files: [
        { filename: 'factory_bot.md', content: '# Factory Bot patterns' },
        { filename: 'request_specs.md', content: '# Request spec conventions' }
      ]
    }
  end

  describe '#install' do
    it 'creates the pack directory with files' do
      manager.install(pack_data)

      pack_dir = File.join(packs_dir, 'rails-testing')
      expect(File.directory?(pack_dir)).to be true
      expect(File.read(File.join(pack_dir, 'factory_bot.md'))).to eq('# Factory Bot patterns')
      expect(File.read(File.join(pack_dir, 'request_specs.md'))).to eq('# Request spec conventions')
    end

    it 'writes a manifest.json with metadata' do
      manager.install(pack_data)

      manifest_path = File.join(packs_dir, 'rails-testing', 'manifest.json')
      manifest = JSON.parse(File.read(manifest_path), symbolize_names: true)

      expect(manifest[:name]).to eq('rails-testing')
      expect(manifest[:description]).to eq('Rails testing patterns and best practices')
      expect(manifest[:version]).to eq('1.2.0')
      expect(manifest[:installed_at]).not_to be_nil
      expect(manifest[:file_count]).to eq(2)
    end

    it 'returns the installed manifest' do
      result = manager.install(pack_data)
      expect(result[:name]).to eq('rails-testing')
      expect(result[:version]).to eq('1.2.0')
    end

    it 'raises ArgumentError when name is missing' do
      expect { manager.install({ files: [] }) }.to raise_error(ArgumentError, /name/)
    end

    it 'prevents path traversal in filenames' do
      evil_data = pack_data.merge(files: [{ filename: '../../../etc/passwd', content: 'hacked' }])
      manager.install(evil_data)

      expect(File.exist?(File.join(packs_dir, 'rails-testing', 'passwd'))).to be true
    end

    it 'handles packs with no files' do
      empty_pack = { name: 'empty-pack', description: 'No files', version: '0.1.0', files: [] }
      result = manager.install(empty_pack)
      expect(result[:name]).to eq('empty-pack')
      expect(result[:file_count]).to eq(0)
    end
  end

  describe '#remove' do
    before { manager.install(pack_data) }

    it 'removes the pack directory' do
      expect(manager.remove('rails-testing')).to be true
      expect(File.directory?(File.join(packs_dir, 'rails-testing'))).to be false
    end

    it 'returns false when pack is not installed' do
      expect(manager.remove('nonexistent')).to be false
    end
  end

  describe '#installed' do
    it 'returns empty array when no packs installed' do
      expect(manager.installed).to eq([])
    end

    it 'lists all installed packs sorted by name' do
      manager.install(pack_data)
      manager.install(name: 'api-design', description: 'API patterns', version: '1.0.0', files: [])

      packs = manager.installed
      expect(packs.size).to eq(2)
      expect(packs.map { |p| p[:name] }).to eq(%w[api-design rails-testing])
    end

    it 'returns empty array when packs directory does not exist' do
      fresh_manager = described_class.new(packs_dir: '/tmp/nonexistent-dir-xyz')
      expect(fresh_manager.installed).to eq([])
    end
  end

  describe '#installed?' do
    it 'returns true for installed packs' do
      manager.install(pack_data)
      expect(manager.installed?('rails-testing')).to be true
    end

    it 'returns false for non-installed packs' do
      expect(manager.installed?('nonexistent')).to be false
    end
  end

  describe '#pack_skills_dir' do
    it 'returns the pack directory path when installed' do
      manager.install(pack_data)
      dir = manager.pack_skills_dir('rails-testing')
      expect(dir).to eq(File.join(packs_dir, 'rails-testing'))
    end

    it 'returns nil when pack is not installed' do
      expect(manager.pack_skills_dir('nonexistent')).to be_nil
    end
  end

  describe '#all_pack_dirs' do
    it 'returns directories for all installed packs' do
      manager.install(pack_data)
      manager.install(name: 'api-design', description: 'API patterns', version: '1.0.0', files: [])

      dirs = manager.all_pack_dirs
      expect(dirs.size).to eq(2)
      dirs.each { |d| expect(File.directory?(d)).to be true }
    end

    it 'returns empty array when no packs are installed' do
      expect(manager.all_pack_dirs).to eq([])
    end
  end
end
