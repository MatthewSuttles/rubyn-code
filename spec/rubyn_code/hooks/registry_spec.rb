# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Hooks::Registry do
  subject(:registry) { described_class.new }

  describe '#on' do
    it 'registers a callable for an event' do
      hook = ->(**) { 'called' }
      registry.on(:pre_tool_use, hook)
      expect(registry.hooks_for(:pre_tool_use)).to include(hook)
    end

    it 'accepts a block' do
      registry.on(:post_tool_use) { |**_| 'block' }
      expect(registry.hooks_for(:post_tool_use).size).to eq(1)
    end

    it 'raises on unknown event' do
      expect { registry.on(:bogus_event) { nil } }.to raise_error(ArgumentError, /Unknown event/)
    end

    it 'raises when no callable or block given' do
      expect { registry.on(:pre_tool_use) }.to raise_error(ArgumentError, /callable or block/)
    end

    it 'orders hooks by priority' do
      low = ->(**) { 'low' }
      high = ->(**) { 'high' }
      registry.on(:pre_tool_use, low, priority: 50)
      registry.on(:pre_tool_use, high, priority: 10)
      expect(registry.hooks_for(:pre_tool_use)).to eq([high, low])
    end
  end

  describe '#hooks_for' do
    it 'returns empty array for event with no hooks' do
      expect(registry.hooks_for(:on_error)).to eq([])
    end
  end

  describe '#clear!' do
    it 'clears all hooks when no event given' do
      registry.on(:pre_tool_use) { |**_| nil }
      registry.on(:post_tool_use) { |**_| nil }
      registry.clear!
      expect(registry.hooks_for(:pre_tool_use)).to be_empty
      expect(registry.hooks_for(:post_tool_use)).to be_empty
    end

    it 'clears hooks for a specific event' do
      registry.on(:pre_tool_use) { |**_| nil }
      registry.on(:post_tool_use) { |**_| nil }
      registry.clear!(:pre_tool_use)
      expect(registry.hooks_for(:pre_tool_use)).to be_empty
      expect(registry.hooks_for(:post_tool_use).size).to eq(1)
    end
  end

  describe '#registered_events' do
    it 'returns events that have hooks' do
      registry = described_class.new
      registry.on(:pre_tool_use) { nil }

      expect(registry.registered_events).to include(:pre_tool_use)
    end

    it 'excludes events with no hooks' do
      registry = described_class.new

      expect(registry.registered_events).to be_empty
    end
  end
end
