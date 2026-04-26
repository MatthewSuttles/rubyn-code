# frozen_string_literal: true

RSpec.describe RubynCode::Skills::PackManager do
  subject(:manager) { described_class.new(packs_dir: packs_dir) }

  let(:packs_dir) { File.join(Dir.tmpdir, "rubyn-test-packs-#{SecureRandom.hex(4)}") }

  after { FileUtils.rm_rf(packs_dir) }

  let(:pack_data) do
    {
      name: 'rails-testing',
      description: 'Rails testing patterns',
      version: '1.0.0',
      files: [
        { filename: 'rspec.md', content: '# RSpec Guide' },
        { filename: 'factory-bot.md', content: '# Factory Bot' }
      ]
    }
  end

  describe '#install' do
    it 'creates pack directory and writes files' do
      manager.install(pack_data)

      pack_dir = File.join(packs_dir, 'rails-testing')
      expect(File.directory?(pack_dir)).to be true
      expect(File.exist?(File.join(pack_dir, 'rspec.md'))).to be true
      expect(File.exist?(File.join(pack_dir, 'factory-bot.md'))).to be true
    end

    it 'writes a manifest file' do
      manager.install(pack_data)

      manifest_path = File.join(packs_dir, 'rails-testing', 'manifest.json')
      expect(File.exist?(manifest_path)).to be true

      manifest = JSON.parse(File.read(manifest_path), symbolize_names: true)
      expect(manifest[:name]).to eq('rails-testing')
      expect(manifest[:version]).to eq('1.0.0')
      expect(manifest[:skillCount]).to eq(2)
    end

    it 'returns installed pack metadata' do
      result = manager.install(pack_data)
      expect(result[:name]).to eq('rails-testing')
      expect(result[:version]).to eq('1.0.0')
    end

    it 'raises when name is missing' do
      expect { manager.install({ files: [] }) }.to raise_error(ArgumentError, /name/)
    end

    it 'raises when name is empty' do
      expect { manager.install({ name: '' }) }.to raise_error(ArgumentError, /name/)
    end

    it 'handles string keys in pack data' do
      string_data = {
        'name' => 'string-keys',
        'description' => 'Test',
        'version' => '1.0.0',
        'files' => [{ 'filename' => 'test.md', 'content' => '# Test' }]
      }
      result = manager.install(string_data)
      expect(result[:name]).to eq('string-keys')
    end

    it 'prevents path traversal in filenames' do
      evil_data = {
        name: 'evil-pack',
        files: [{ filename: '../../../etc/passwd', content: 'hacked' }]
      }
      manager.install(evil_data)

      pack_dir = File.join(packs_dir, 'evil-pack')
      expect(File.exist?(File.join(pack_dir, 'passwd'))).to be true
      expect(File.exist?('/etc/passwd_hacked')).to be false
    end
  end

  describe '#remove' do
    before { manager.install(pack_data) }

    it 'removes the pack directory' do
      expect(manager.remove('rails-testing')).to be true
      expect(File.directory?(File.join(packs_dir, 'rails-testing'))).to be false
    end

    it 'returns false when pack not found' do
      expect(manager.remove('nonexistent')).to be false
    end
  end

  describe '#installed' do
    it 'returns empty array when no packs' do
      expect(manager.installed).to eq([])
    end

    it 'lists installed packs sorted by name' do
      manager.install(pack_data)
      manager.install({ name: 'aaa-pack', version: '1.0.0', files: [] })

      packs = manager.installed
      expect(packs.size).to eq(2)
      expect(packs.first[:name]).to eq('aaa-pack')
      expect(packs.last[:name]).to eq('rails-testing')
    end
  end

  describe '#installed?' do
    it 'returns true for installed pack' do
      manager.install(pack_data)
      expect(manager.installed?('rails-testing')).to be true
    end

    it 'returns false for missing pack' do
      expect(manager.installed?('nonexistent')).to be false
    end
  end

  describe '#pack_skills_dir' do
    it 'returns path for installed pack' do
      manager.install(pack_data)
      expect(manager.pack_skills_dir('rails-testing')).to eq(File.join(packs_dir, 'rails-testing'))
    end

    it 'returns nil for missing pack' do
      expect(manager.pack_skills_dir('nonexistent')).to be_nil
    end
  end

  describe '#all_pack_dirs' do
    it 'returns empty array when no packs' do
      expect(manager.all_pack_dirs).to eq([])
    end

    it 'returns all pack directories' do
      manager.install(pack_data)
      dirs = manager.all_pack_dirs
      expect(dirs.size).to eq(1)
      expect(dirs.first).to end_with('rails-testing')
    end
  end
end
