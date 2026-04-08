# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::FirstRun do
  let(:config_dir) { Dir.mktmpdir('rubyn_first_run_') }
  let(:config_path) { File.join(config_dir, 'config.yml') }
  let(:tty_prompt) { instance_double(TTY::Prompt) }

  after { FileUtils.rm_rf(config_dir) }

  describe '.needed?' do
    it 'returns true when config file does not exist' do
      expect(described_class.needed?(config_path: File.join(config_dir, 'nonexistent.yml'))).to be true
    end

    it 'returns false when config file exists' do
      File.write(config_path, YAML.dump('provider' => 'anthropic'))
      expect(described_class.needed?(config_path: config_path)).to be false
    end
  end

  describe '.skipped?' do
    it 'returns true when skip_flag is true' do
      expect(described_class.skipped?(skip_flag: true)).to be true
    end

    it 'returns true when RUBYN_SKIP_SETUP env var is set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RUBYN_SKIP_SETUP').and_return('1')
      expect(described_class.skipped?).to be true
    end

    it 'returns false when neither flag nor env var is set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RUBYN_SKIP_SETUP').and_return(nil)
      expect(described_class.skipped?).to be false
    end
  end

  describe '#run' do
    subject(:first_run) { described_class.new(config_path: config_path, prompt: tty_prompt) }

    before do
      allow(tty_prompt).to receive(:select).and_return('anthropic')
      allow(tty_prompt).to receive(:ask).and_return(5.0)
      allow(ENV).to receive(:key?).and_call_original
      allow(ENV).to receive(:key?).with('ANTHROPIC_API_KEY').and_return(true)
    end

    it 'writes a config file' do
      expect { first_run.run }.to output.to_stdout
      expect(File.exist?(config_path)).to be true
    end

    it 'writes valid YAML config' do
      expect { first_run.run }.to output.to_stdout
      data = YAML.safe_load_file(config_path)
      expect(data['provider']).to eq('anthropic')
      expect(data['model']).to eq('claude-opus-4-6')
    end

    it 'stores the budget from user input' do
      allow(tty_prompt).to receive(:ask).and_return(10.0)
      expect { first_run.run }.to output.to_stdout
      data = YAML.safe_load_file(config_path)
      expect(data['session_budget_usd']).to eq(10.0)
    end

    it 'sets file permissions to 0600' do
      expect { first_run.run }.to output.to_stdout
      mode = File.stat(config_path).mode & 0o777
      expect(mode).to eq(0o600)
    end

    it 'includes provider models in config' do
      expect { first_run.run }.to output.to_stdout
      data = YAML.safe_load_file(config_path)
      expect(data['providers']).to be_a(Hash)
      expect(data['providers']['anthropic']).to be_a(Hash)
    end

    context 'with OpenAI provider' do
      before do
        allow(tty_prompt).to receive(:select).and_return('openai')
        allow(ENV).to receive(:key?).with('OPENAI_API_KEY').and_return(false)
      end

      it 'sets openai as provider and correct default model' do
        expect { first_run.run }.to output.to_stdout
        data = YAML.safe_load_file(config_path)
        expect(data['provider']).to eq('openai')
        expect(data['model']).to eq('gpt-5.4')
      end
    end

    context 'with Other provider' do
      before do
        allow(tty_prompt).to receive(:select).and_return('other')
      end

      it 'defaults to anthropic provider' do
        expect { first_run.run }.to output.to_stdout
        data = YAML.safe_load_file(config_path)
        expect(data['provider']).to eq('anthropic')
      end
    end

    it 'displays welcome and summary messages' do
      output = capture_stdout { first_run.run }
      expect(output).to include('Welcome to Rubyn Code')
      expect(output).to include('Setup complete')
      expect(output).to include('/help')
    end
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
