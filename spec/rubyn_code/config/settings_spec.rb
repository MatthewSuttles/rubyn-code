# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Config::Settings do
  let(:config_dir) { Dir.mktmpdir('rubyn_config_') }
  let(:config_path) { File.join(config_dir, 'config.yml') }

  after { FileUtils.rm_rf(config_dir) }

  describe '#initialize' do
    it 'loads config from YAML file' do
      File.write(config_path, YAML.dump({ 'model' => 'claude-haiku', 'max_iterations' => 50 }))

      settings = described_class.new(config_path: config_path)

      expect(settings.get('model')).to eq('claude-haiku')
      expect(settings.get('max_iterations')).to eq(50)
    end

    it 'returns defaults when no config file exists' do
      settings = described_class.new(config_path: File.join(config_dir, 'nonexistent.yml'))

      expect(settings.model).to eq(RubynCode::Config::Defaults::DEFAULT_MODEL)
      expect(settings.max_iterations).to eq(RubynCode::Config::Defaults::MAX_ITERATIONS)
    end

    it 'handles empty config file' do
      File.write(config_path, '')

      settings = described_class.new(config_path: config_path)

      expect(settings.model).to eq(RubynCode::Config::Defaults::DEFAULT_MODEL)
    end

    it 'raises on malformed YAML' do
      File.write(config_path, "{\ninvalid: yaml: [broken\n")

      expect { described_class.new(config_path: config_path) }
        .to raise_error(described_class::LoadError, /Malformed YAML/)
    end

    it 'raises when YAML is not a Hash' do
      File.write(config_path, "- item1\n- item2\n")

      expect { described_class.new(config_path: config_path) }
        .to raise_error(described_class::LoadError, /Expected a YAML mapping/)
    end
  end

  describe '#get' do
    let(:settings) { described_class.new(config_path: File.join(config_dir, 'nonexistent.yml')) }

    it 'returns config value' do
      settings.set('model', 'claude-haiku')

      expect(settings.get('model')).to eq('claude-haiku')
    end

    it 'returns default from DEFAULT_MAP when key is missing' do
      expect(settings.get('model')).to eq(RubynCode::Config::Defaults::DEFAULT_MODEL)
    end

    it 'returns explicit default when key is missing and not in DEFAULT_MAP' do
      expect(settings.get('unknown_key', 'fallback')).to eq('fallback')
    end

    it 'returns nil when key is missing and no default provided' do
      expect(settings.get('unknown_key')).to be_nil
    end
  end

  describe '#set' do
    let(:settings) { described_class.new(config_path: File.join(config_dir, 'nonexistent.yml')) }

    it 'stores a value' do
      settings.set('model', 'claude-haiku')

      expect(settings.get('model')).to eq('claude-haiku')
    end

    it 'overwrites existing values' do
      settings.set('model', 'claude-haiku')
      settings.set('model', 'claude-opus')

      expect(settings.get('model')).to eq('claude-opus')
    end
  end

  describe '#save!' do
    it 'writes YAML to disk' do
      settings = described_class.new(config_path: config_path)
      settings.set('model', 'claude-haiku')
      settings.set('max_iterations', 100)

      settings.save!

      written = YAML.safe_load(File.read(config_path))
      expect(written['model']).to eq('claude-haiku')
      expect(written['max_iterations']).to eq(100)
    end

    it 'sets file permissions to 0600' do
      settings = described_class.new(config_path: config_path)
      settings.set('model', 'test')
      settings.save!

      mode = File.stat(config_path).mode & 0o777
      expect(mode).to eq(0o600)
    end

    it 'creates parent directories if needed' do
      nested_path = File.join(config_dir, 'deep', 'nested', 'config.yml')
      settings = described_class.new(config_path: nested_path)
      settings.set('model', 'test')
      settings.save!

      expect(File.exist?(nested_path)).to be true
    end
  end

  describe '#reload!' do
    it 're-reads the config file' do
      settings = described_class.new(config_path: config_path)
      settings.set('model', 'claude-haiku')
      settings.save!

      # Modify the file externally
      data = YAML.safe_load(File.read(config_path))
      data['model'] = 'claude-opus'
      File.write(config_path, YAML.dump(data))

      settings.reload!

      expect(settings.get('model')).to eq('claude-opus')
    end
  end

  describe '#to_h' do
    it 'merges defaults with overrides' do
      settings = described_class.new(config_path: File.join(config_dir, 'nonexistent.yml'))
      settings.set('model', 'claude-haiku')

      hash = settings.to_h

      expect(hash['model']).to eq('claude-haiku')
      expect(hash['max_iterations']).to eq(RubynCode::Config::Defaults::MAX_ITERATIONS)
    end

    it 'includes all default keys' do
      settings = described_class.new(config_path: File.join(config_dir, 'nonexistent.yml'))

      hash = settings.to_h

      RubynCode::Config::Settings::DEFAULT_MAP.each_key do |key|
        expect(hash).to have_key(key.to_s)
      end
    end
  end

  describe 'dynamic accessor methods' do
    let(:settings) { described_class.new(config_path: File.join(config_dir, 'nonexistent.yml')) }

    it 'reads model via accessor' do
      expect(settings.model).to eq(RubynCode::Config::Defaults::DEFAULT_MODEL)
    end

    it 'writes model via accessor' do
      settings.model = 'claude-haiku'

      expect(settings.model).to eq('claude-haiku')
    end

    it 'reads max_iterations via accessor' do
      expect(settings.max_iterations).to eq(RubynCode::Config::Defaults::MAX_ITERATIONS)
    end

    it 'writes max_iterations via accessor' do
      settings.max_iterations = 42

      expect(settings.max_iterations).to eq(42)
    end

    it 'reads session_budget_usd via accessor' do
      expect(settings.session_budget_usd).to eq(RubynCode::Config::Defaults::SESSION_BUDGET_USD)
    end

    it 'writes session_budget_usd via accessor' do
      settings.session_budget_usd = 25.0

      expect(settings.session_budget_usd).to eq(25.0)
    end
  end
end
