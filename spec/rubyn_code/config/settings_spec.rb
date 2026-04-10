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

      written = YAML.safe_load_file(config_path)
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
      data = YAML.safe_load_file(config_path)
      data['model'] = 'claude-opus'
      File.write(config_path, YAML.dump(data))

      settings.reload!

      expect(settings.get('model')).to eq('claude-opus')
    end
  end

  describe 'seed_config!' do
    it 'creates config.yml on first run with default providers and model tiers' do
      settings = described_class.new(config_path: config_path)
      expect(File.exist?(config_path)).to be true
      data = YAML.safe_load(File.read(config_path))
      expect(data['provider']).to eq('anthropic')
      expect(data['model']).to eq('claude-opus-4-6')
      expect(data['providers']['anthropic']['env_key']).to eq('ANTHROPIC_API_KEY')
      expect(data['providers']['anthropic']['models']['cheap']).to eq('claude-haiku-4-5')
      expect(data['providers']['anthropic']['models']['mid']).to eq('claude-sonnet-4-6')
      expect(data['providers']['anthropic']['models']['top']).to eq('claude-opus-4-6')
      expect(data['providers']['openai']['env_key']).to eq('OPENAI_API_KEY')
      expect(data['providers']['openai']['models']['cheap']).to eq('gpt-5.4-nano')
      expect(data['providers']['openai']['models']['mid']).to eq('gpt-5.4-mini')
      expect(data['providers']['openai']['models']['top']).to eq('gpt-5.4')
    end

    it 'does not overwrite an existing config' do
      File.write(config_path, YAML.dump('model' => 'custom-model'))
      settings = described_class.new(config_path: config_path)
      expect(settings.model).to eq('custom-model')
    end
  end

  describe '#add_provider' do
    it 'adds a provider and persists to disk' do
      settings = described_class.new(config_path: config_path)
      settings.add_provider('groq',
                            base_url: 'https://api.groq.com/openai/v1',
                            env_key: 'GROQ_API_KEY',
                            models: %w[llama-3],
                            pricing: { 'llama-3' => [0.10, 0.20] })

      reloaded = described_class.new(config_path: config_path)
      cfg = reloaded.provider_config('groq')
      expect(cfg['base_url']).to eq('https://api.groq.com/openai/v1')
      expect(cfg['env_key']).to eq('GROQ_API_KEY')
      expect(cfg['models']).to eq(%w[llama-3])
      expect(cfg['pricing']).to eq('llama-3' => [0.10, 0.20])
    end

    it 'omits optional fields when not provided' do
      settings = described_class.new(config_path: config_path)
      settings.add_provider('ollama', base_url: 'http://localhost:11434/v1')

      reloaded = described_class.new(config_path: config_path)
      cfg = reloaded.provider_config('ollama')
      expect(cfg['base_url']).to eq('http://localhost:11434/v1')
      expect(cfg).not_to have_key('env_key')
      expect(cfg).not_to have_key('models')
      expect(cfg).not_to have_key('pricing')
      expect(cfg).not_to have_key('api_format')
    end

    it 'persists api_format when provided' do
      settings = described_class.new(config_path: config_path)
      settings.add_provider('proxy',
                            base_url: 'https://proxy.example.com/v1',
                            api_format: 'anthropic',
                            models: %w[claude-sonnet-4-6])

      reloaded = described_class.new(config_path: config_path)
      cfg = reloaded.provider_config('proxy')
      expect(cfg['api_format']).to eq('anthropic')
      expect(cfg['base_url']).to eq('https://proxy.example.com/v1')
    end
  end

  describe '#provider_config' do
    it 'returns nil for unconfigured providers' do
      settings = described_class.new(config_path: config_path)
      expect(settings.provider_config('minimax')).to be_nil
    end

    it 'returns config hash for a configured provider' do
      File.write(config_path, YAML.dump(
        'providers' => {
          'minimax' => {
            'base_url' => 'https://api.minimax.chat/v1',
            'env_key' => 'MINIMAX_API_KEY',
            'models' => ['M1'],
            'pricing' => { 'M1' => [0.50, 2.00] }
          }
        }
      ))
      settings = described_class.new(config_path: config_path)
      cfg = settings.provider_config('minimax')
      expect(cfg['base_url']).to eq('https://api.minimax.chat/v1')
      expect(cfg['models']).to eq(['M1'])
    end
  end

  describe '#custom_pricing' do
    it 'returns empty hash when no providers configured' do
      settings = described_class.new(config_path: config_path)
      expect(settings.custom_pricing).to eq({})
    end

    it 'returns pricing from configured providers' do
      File.write(config_path, YAML.dump(
        'providers' => {
          'minimax' => {
            'pricing' => { 'M1' => [0.50, 2.00] }
          }
        }
      ))
      settings = described_class.new(config_path: config_path)
      expect(settings.custom_pricing).to eq('M1' => [0.50, 2.00])
    end

    it 'skips malformed pricing entries' do
      File.write(config_path, YAML.dump(
        'providers' => {
          'minimax' => {
            'pricing' => { 'M1' => [0.50] }
          }
        }
      ))
      settings = described_class.new(config_path: config_path)
      expect(settings.custom_pricing).to eq({})
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
