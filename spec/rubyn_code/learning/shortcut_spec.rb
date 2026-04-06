# frozen_string_literal: true

RSpec.describe RubynCode::Learning::Shortcut do
  subject(:shortcut) { described_class.new }

  describe '#apply' do
    it 'returns settings for matching patterns' do
      result = shortcut.apply(['uses_rspec'])
      expect(result).to eq(test_framework: :rspec)
    end

    it 'returns empty hash for non-matching patterns' do
      result = shortcut.apply(['unknown_pattern'])
      expect(result).to eq({})
    end

    it 'matches patterns with spaces instead of underscores' do
      result = shortcut.apply(['uses factory bot'])
      expect(result).to eq(spec_template: :factory_bot_rspec)
    end

    it 'applies multiple patterns and merges settings' do
      result = shortcut.apply(['uses_rspec', 'uses_factory_bot'])
      expect(result).to include(test_framework: :rspec, spec_template: :factory_bot_rspec)
    end

    it 'tracks applied shortcuts' do
      shortcut.apply(['uses_rspec', 'uses_devise'])
      expect(shortcut.applied_shortcuts.size).to eq(2)
    end

    it 'estimates tokens saved based on skipped steps' do
      shortcut.apply(['uses_rspec'])
      expect(shortcut.tokens_saved_estimate).to eq(500)
    end
  end

  describe '#skip?' do
    before { shortcut.apply(['uses_rspec']) }

    it 'returns true for skipped steps' do
      expect(shortcut.skip?('framework_detection')).to be true
    end

    it 'returns false for non-skipped steps' do
      expect(shortcut.skip?('something_else')).to be false
    end

    it 'handles string and symbol step names' do
      expect(shortcut.skip?(:framework_detection)).to be true
    end
  end

  describe '#stats' do
    it 'returns correct stats after applying shortcuts' do
      shortcut.apply(['uses_rspec', 'uses_factory_bot'])
      result = shortcut.stats

      expect(result[:shortcuts_applied]).to eq(2)
      expect(result[:steps_skipped]).to eq(3)
      expect(result[:tokens_saved_estimate]).to eq(1500)
    end

    it 'returns zeroes when no shortcuts applied' do
      result = shortcut.stats

      expect(result[:shortcuts_applied]).to eq(0)
      expect(result[:steps_skipped]).to eq(0)
      expect(result[:tokens_saved_estimate]).to eq(0)
    end
  end
end
