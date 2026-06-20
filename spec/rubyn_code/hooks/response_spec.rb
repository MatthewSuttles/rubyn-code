# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Hooks::Response do
  describe '#block?' do
    it 'is true when decision is "block"' do
      response = described_class.new(raw: { 'decision' => 'block', 'reason' => 'rm -rf' })
      expect(response.block?).to be true
      expect(response.reason).to eq('rm -rf')
    end

    it 'is false for "approve"' do
      expect(described_class.new(raw: { 'decision' => 'approve' }).block?).to be false
    end

    it 'is false when decision is absent' do
      expect(described_class.new(raw: {}).block?).to be false
    end
  end

  describe '#stop?' do
    it 'is true when continue is false' do
      response = described_class.new(raw: { 'continue' => false, 'stopReason' => 'Denied' })
      expect(response.stop?).to be true
      expect(response.stop_reason).to eq('Denied')
    end

    it 'is true (default) when continue is absent' do
      expect(described_class.new(raw: {}).stop?).to be false
    end

    it 'is false when continue is true' do
      expect(described_class.new(raw: { 'continue' => true }).stop?).to be false
    end
  end

  describe '#additional_context?' do
    it 'is true when hookSpecificOutput.additionalContext is present' do
      raw = {
        'hookSpecificOutput' => {
          'hookEventName' => 'PreToolUse',
          'additionalContext' => 'Run rubocop before commit'
        }
      }
      response = described_class.new(raw: raw)
      expect(response.additional_context?).to be true
      expect(response.additional_context).to eq('Run rubocop before commit')
      expect(response.hook_event_name).to eq('PreToolUse')
    end

    it 'is false when additionalContext is missing' do
      raw = { 'hookSpecificOutput' => { 'hookEventName' => 'PreToolUse' } }
      expect(described_class.new(raw: raw).additional_context?).to be false
    end

    it 'is false when additionalContext is empty' do
      raw = { 'hookSpecificOutput' => { 'hookEventName' => 'PreToolUse', 'additionalContext' => '' } }
      expect(described_class.new(raw: raw).additional_context?).to be false
    end
  end

  describe '#suppress_output?' do
    it 'is true when suppressOutput is true' do
      expect(described_class.new(raw: { 'suppressOutput' => true }).suppress_output?).to be true
    end

    it 'is false for any other value' do
      expect(described_class.new(raw: { 'suppressOutput' => false }).suppress_output?).to be false
      expect(described_class.new(raw: {}).suppress_output?).to be false
    end
  end

  describe 'nil tolerance' do
    it 'does not raise when raw is nil' do
      expect { described_class.new(raw: nil) }.not_to raise_error
      expect(described_class.new(raw: nil).block?).to be false
    end
  end
end
