# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Hooks::EventMap do
  describe '.external' do
    it 'maps internal symbols to Claude Code event names' do
      expect(described_class.external(:pre_tool_use)).to eq('PreToolUse')
      expect(described_class.external(:post_tool_use)).to eq('PostToolUse')
      expect(described_class.external(:stop)).to eq('Stop')
      expect(described_class.external(:user_prompt_submit)).to eq('UserPromptSubmit')
    end

    it 'returns nil for events with no external mapping' do
      expect(described_class.external(:on_error)).to be_nil
      expect(described_class.external(:on_stall)).to be_nil
      expect(described_class.external(:permission_request)).to be_nil
    end

    it 'accepts strings and converts them' do
      expect(described_class.external('pre_tool_use')).to eq('PreToolUse')
    end
  end

  describe '.internal' do
    it 'maps Claude Code event names to internal symbols' do
      expect(described_class.internal('PreToolUse')).to eq(:pre_tool_use)
      expect(described_class.internal('PostToolUse')).to eq(:post_tool_use)
      expect(described_class.internal('SessionStart')).to eq(:session_start)
    end

    it 'returns nil for unknown external events' do
      expect(described_class.internal('BogusEvent')).to be_nil
    end
  end

  describe 'round-trip' do
    it 'is symmetric for every mapped event' do
      described_class::TO_EXTERNAL.each do |internal, external|
        expect(described_class.external(internal)).to eq(external)
        expect(described_class.internal(external)).to eq(internal)
      end
    end
  end

  describe 'EXTERNAL_EVENTS' do
    it 'includes the full Claude Code hook surface' do
      expect(described_class::EXTERNAL_EVENTS).to include(
        'PreToolUse', 'PostToolUse', 'UserPromptSubmit', 'SessionStart',
        'SessionEnd', 'Stop', 'SubagentStop', 'PreCompact', 'Notification'
      )
    end
  end
end
