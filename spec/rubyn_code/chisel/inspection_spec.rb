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

    it 'is read-only and excludes the safety floor' do
      %i[diff repo].each do |scope|
        out = described_class.prompt(scope: scope)
        expect(out).to include('READ-ONLY')
        expect(out).to include('do not edit')
        expect(out).to match(/validation.*security.*accessibility/m)
      end
    end

    it 'raises on an unknown scope' do
      expect { described_class.prompt(scope: :everything) }
        .to raise_error(ArgumentError, /unknown Chisel inspection scope/)
    end
  end
end
