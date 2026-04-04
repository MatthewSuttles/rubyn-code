# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Debug do
  let(:output) { StringIO.new }

  before do
    described_class.disable!
    described_class.output = output
  end

  after do
    described_class.disable!
    described_class.output = $stderr
    ENV.delete('RUBYN_DEBUG')
  end

  describe '.enable! / .disable!' do
    it 'enables debug mode' do
      described_class.enable!

      expect(described_class.enabled?).to be true
    end

    it 'disables debug mode' do
      described_class.enable!
      described_class.disable!

      expect(described_class.enabled?).to be_falsey
    end
  end

  describe '.enabled?' do
    it 'returns falsey by default' do
      expect(described_class.enabled?).to be_falsey
    end

    it 'returns true when enabled' do
      described_class.enable!

      expect(described_class.enabled?).to be true
    end

    it 'returns truthy when RUBYN_DEBUG env var is set' do
      ENV['RUBYN_DEBUG'] = '1'

      expect(described_class.enabled?).to be_truthy
    end

    it 'returns falsey when RUBYN_DEBUG is not set and not enabled' do
      ENV.delete('RUBYN_DEBUG')
      described_class.disable!

      expect(described_class.enabled?).to be_falsey
    end
  end

  describe '.log' do
    it 'outputs timestamped tagged message when enabled' do
      described_class.enable!

      described_class.log('test', 'hello world')

      log_output = output.string
      expect(log_output).to match(/\[\d{2}:\d{2}:\d{2}\.\d{3}\]/)
      expect(log_output).to include('[test]')
      expect(log_output).to include('hello world')
    end

    it 'is silent when disabled' do
      described_class.disable!

      described_class.log('test', 'should not appear')

      expect(output.string).to be_empty
    end

    it 'respects RUBYN_DEBUG env var' do
      ENV['RUBYN_DEBUG'] = '1'

      described_class.log('test', 'env enabled')

      expect(output.string).to include('env enabled')
    end
  end

  describe 'convenience methods' do
    before { described_class.enable! }

    it '.llm delegates to log with llm tag' do
      described_class.llm('LLM request sent')

      expect(output.string).to include('[llm]')
      expect(output.string).to include('LLM request sent')
    end

    it '.tool delegates to log with tool tag' do
      described_class.tool('Running bash')

      expect(output.string).to include('[tool]')
      expect(output.string).to include('Running bash')
    end

    it '.agent delegates to log with agent tag' do
      described_class.agent('Agent started')

      expect(output.string).to include('[agent]')
      expect(output.string).to include('Agent started')
    end

    it '.loop_tick delegates to log with loop tag' do
      described_class.loop_tick('Iteration 5')

      expect(output.string).to include('[loop]')
      expect(output.string).to include('Iteration 5')
    end

    it '.recovery delegates to log with recovery tag' do
      described_class.recovery('Retrying request')

      expect(output.string).to include('[recovery]')
      expect(output.string).to include('Retrying request')
    end

    it '.token delegates to log with token tag' do
      described_class.token('1000 tokens used')

      expect(output.string).to include('[token]')
      expect(output.string).to include('1000 tokens used')
    end

    it '.warn delegates to log with warn tag' do
      described_class.warn('Something suspicious')

      expect(output.string).to include('[warn]')
      expect(output.string).to include('Something suspicious')
    end

    it '.error delegates to log with error tag' do
      described_class.error('Something broke')

      expect(output.string).to include('[error]')
      expect(output.string).to include('Something broke')
    end
  end
end
