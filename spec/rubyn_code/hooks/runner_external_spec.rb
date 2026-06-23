# frozen_string_literal: true

require 'spec_helper'

# Integration tests covering the Runner's interaction with ExternalDispatcher.
# These live separately from runner_spec.rb because they exercise the
# two-tier (in-process + external) hook pipeline.
RSpec.describe RubynCode::Hooks::Runner do
  let(:registry) { RubynCode::Hooks::Registry.new }
  let(:fake_dispatcher) { instance_double(RubynCode::Hooks::ExternalDispatcher) }

  def response_with(**attrs)
    RubynCode::Hooks::Response.new(raw: attrs.transform_keys(&:to_s))
  end

  before do
    allow(RubynCode::Hooks::ExternalDispatcher).to receive(:new).and_return(fake_dispatcher)
  end

  describe ':pre_tool_use — external block is honored' do
    it 'returns deny when the external dispatcher says block' do
      allow(fake_dispatcher).to receive(:fire).with(:pre_tool_use, hash_including(:tool_name))
                                                .and_return(response_with(decision: 'block', reason: 'no rm -rf'))

      runner = described_class.new(registry: registry, external_dispatcher: fake_dispatcher)
      result = runner.fire(:pre_tool_use, tool_name: 'bash', tool_input: { 'command' => 'rm -rf /' })

      expect(result).to eq(deny: true, reason: 'no rm -rf')
    end

    it 'in-process deny wins over external approval' do
      registry.on(:pre_tool_use, ->(**_) { { deny: true, reason: 'in-process blocked this' } })
      allow(fake_dispatcher).to receive(:fire).and_return(response_with(decision: 'approve'))

      runner = described_class.new(registry: registry, external_dispatcher: fake_dispatcher)
      result = runner.fire(:pre_tool_use, tool_name: 'bash', tool_input: {})

      expect(result[:deny]).to be true
      expect(result[:reason]).to eq('in-process blocked this')
    end

    it 'returns nil when neither in-process nor external deny' do
      allow(fake_dispatcher).to receive(:fire).and_return(response_with)
      runner = described_class.new(registry: registry, external_dispatcher: fake_dispatcher)

      expect(runner.fire(:pre_tool_use, tool_name: 'bash', tool_input: {})).to be_nil
    end

    it 'does not call the dispatcher when none is configured' do
      runner = described_class.new(registry: registry) # no external_dispatcher
      expect { runner.fire(:pre_tool_use, tool_name: 'bash', tool_input: {}) }.not_to raise_error
      expect(runner.fire(:pre_tool_use, tool_name: 'bash', tool_input: {})).to be_nil
    end
  end

  describe ':stop — external stop is honored' do
    it 'returns block when the external dispatcher says stop' do
      allow(fake_dispatcher).to receive(:fire).with(:stop, hash_including(:reason))
                                                .and_return(response_with(continue: false, stopReason: 'policy reached'))
      runner = described_class.new(registry: registry, external_dispatcher: fake_dispatcher)

      result = runner.fire(:stop, reason: 'agent finished')
      expect(result).to eq(block: true, reason: 'policy reached')
    end

    it 'in-process block wins over external non-stop' do
      registry.on(:stop, ->(**_) { { block: true, reason: 'goal not reached' } })
      allow(fake_dispatcher).to receive(:fire).and_return(response_with)

      runner = described_class.new(registry: registry, external_dispatcher: fake_dispatcher)
      expect(runner.fire(:stop)).to eq(block: true, reason: 'goal not reached')
    end
  end

  describe ':post_tool_use — external does not transform output' do
    it 'returns the in-process output unchanged even when external fires' do
      registry.on(:post_tool_use, ->(result:, **) { "#{result} [redacted]" })
      allow(fake_dispatcher).to receive(:fire).and_return(response_with)

      runner = described_class.new(registry: registry, external_dispatcher: fake_dispatcher)
      expect(runner.fire(:post_tool_use, result: 'secret')).to eq('secret [redacted]')
    end
  end

  describe 'generic events — external errors do not crash the agent' do
    it 'swallows dispatcher errors and continues' do
      allow(fake_dispatcher).to receive(:fire).and_raise(StandardError, 'subprocess died')

      runner = described_class.new(registry: registry, external_dispatcher: fake_dispatcher)
      expect { runner.fire(:on_session_end, reason: 'done') }.not_to raise_error
    end
  end
end
