# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Chisel::Inspection do
  describe '.prompt' do
    context 'with scope :diff' do
      subject(:prompt) { described_class.prompt(scope: :diff, target: 'develop') }

      it 'names the base ref and how to gather the diff' do
        expect(prompt).to include('git diff develop...')
      end

      it 'defaults the base ref to main' do
        expect(described_class.prompt(scope: :diff)).to include('git diff main...')
      end

      it 'judges by the shared decision ladder' do
        expect(prompt).to include(RubynCode::Chisel::LADDER)
      end
    end

    context 'with scope :repo' do
      it 'sweeps the whole repo when no path is given' do
        expect(described_class.prompt(scope: :repo)).to include('whole repository')
      end

      it 'scopes to a path when one is given' do
        expect(described_class.prompt(scope: :repo, target: 'app/services')).to include('app/services')
      end

      it 'judges by the shared decision ladder' do
        expect(described_class.prompt(scope: :repo)).to include(RubynCode::Chisel::LADDER)
      end
    end

    it 'always states the output contract' do
      %i[diff repo].each do |scope|
        expect(described_class.prompt(scope: scope)).to include('ranked deletion/simplification list')
      end
    end

    it 'is read-only and reuses the shared safety floor verbatim' do
      %i[diff repo].each do |scope|
        out = described_class.prompt(scope: scope)
        expect(out).to include('READ-ONLY')
        expect(out).to include('do not edit')
        # The exclusion list is the same constant the always-on ruleset injects,
        # so it can never drift — assert the constant itself appears.
        expect(out).to include(RubynCode::Chisel::SAFETY_FLOOR)
      end
    end

    it 'treats a blank target as the default' do
      expect(described_class.prompt(scope: :diff, target: '  ')).to include('git diff main...')
      expect(described_class.prompt(scope: :repo, target: '')).to include('whole repository')
    end

    it 'raises on an unknown scope' do
      expect { described_class.prompt(scope: :everything) }
        .to raise_error(ArgumentError, /unknown Chisel inspection scope/)
    end
  end
end
