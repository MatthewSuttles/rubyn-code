# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Chisel do
  # Control the env override explicitly; restore whatever was there.
  around do |example|
    original = ENV.fetch('RUBYN_CHISEL_MODE', nil)
    ENV.delete('RUBYN_CHISEL_MODE')
    example.run
  ensure
    if original.nil?
      ENV.delete('RUBYN_CHISEL_MODE')
    else
      ENV['RUBYN_CHISEL_MODE'] = original
    end
  end

  describe '.valid?' do
    it 'accepts the four known modes' do
      expect(%w[off lite full ultra]).to all(satisfy { |m| described_class.valid?(m) })
    end

    it 'rejects anything else' do
      expect(described_class.valid?('aggressive')).to be(false)
      expect(described_class.valid?(nil)).to be(false)
    end
  end

  describe '.mode' do
    it 'defaults to off when nothing is set' do
      allow(described_class).to receive(:configured_mode).and_return(nil)
      expect(described_class.mode).to eq('off')
    end

    it 'reads the persisted config value' do
      allow(described_class).to receive(:configured_mode).and_return('full')
      expect(described_class.mode).to eq('full')
    end

    it 'lets the env var override config' do
      allow(described_class).to receive(:configured_mode).and_return('lite')
      ENV['RUBYN_CHISEL_MODE'] = 'ultra'
      expect(described_class.mode).to eq('ultra')
    end

    it 'ignores an invalid env value and falls through to config' do
      allow(described_class).to receive(:configured_mode).and_return('full')
      ENV['RUBYN_CHISEL_MODE'] = 'banana'
      expect(described_class.mode).to eq('full')
    end

    it 'falls back to off when the configured value is invalid' do
      allow(described_class).to receive(:configured_mode).and_return('banana')
      expect(described_class.mode).to eq('off')
    end
  end

  describe '.enabled?' do
    it 'is false when off' do
      allow(described_class).to receive(:mode).and_return('off')
      expect(described_class.enabled?).to be(false)
    end

    it 'is true for any non-off mode' do
      allow(described_class).to receive(:mode).and_return('lite')
      expect(described_class.enabled?).to be(true)
    end
  end

  describe '.prompt_section' do
    it 'is empty when off' do
      allow(described_class).to receive(:mode).and_return('off')
      expect(described_class.prompt_section).to eq('')
    end

    it 'includes the ladder and safety floor at lite, but no intensity addenda' do
      allow(described_class).to receive(:mode).and_return('lite')
      section = described_class.prompt_section
      expect(section).to include('write the minimum that works')
      expect(section).to include('Lazy, not negligent')
      expect(section).not_to include(described_class::FULL_ADDENDUM)
      expect(section).not_to include(described_class::ULTRA_ADDENDUM)
    end

    it 'always carries the safety floor in every non-off mode' do
      %w[lite full ultra].each do |m|
        allow(described_class).to receive(:mode).and_return(m)
        expect(described_class.prompt_section).to include(described_class::SAFETY_FLOOR)
      end
    end

    it 'nests: lite ⊂ full ⊂ ultra' do
      sections = %w[lite full ultra].map do |m|
        allow(described_class).to receive(:mode).and_return(m)
        described_class.prompt_section
      end
      lite, full, ultra = sections

      expect(full).to include(described_class::FULL_ADDENDUM)
      expect(lite).not_to include(described_class::FULL_ADDENDUM)
      expect(ultra).to include(described_class::FULL_ADDENDUM)
      expect(ultra).to include(described_class::ULTRA_ADDENDUM)
      expect(full).not_to include(described_class::ULTRA_ADDENDUM)
    end
  end

  describe '.configured_mode' do
    it 'returns nil rather than raising when settings blow up' do
      allow(RubynCode::Config::Settings).to receive(:new).and_raise(StandardError)
      expect(described_class.configured_mode).to be_nil
    end
  end
end
