# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::CommandTemplate do
  describe '#render' do
    it 'substitutes $ARGUMENTS with all args joined' do
      tmpl = described_class.new('Review this: $ARGUMENTS')
      expect(tmpl.render(%w[a b c])).to eq('Review this: a b c')
    end

    it 'substitutes positional $1..$9' do
      tmpl = described_class.new('first=$1 second=$2')
      expect(tmpl.render(%w[x y])).to eq('first=x second=y')
    end

    it 'renders missing positionals as empty strings' do
      tmpl = described_class.new('only=$1 missing=$3')
      expect(tmpl.render(%w[here])).to eq('only=here missing=')
    end

    it 'inlines !`shell command` output' do
      tmpl = described_class.new('Branch: !`echo main`')
      expect(tmpl.render).to eq('Branch: main')
    end

    it 'reports a failed bash substitution instead of raising' do
      tmpl = described_class.new('x: !`exit 7`')
      # capture2e of a non-zero exit still returns output (empty here)
      expect { tmpl.render }.not_to raise_error
    end

    it 'leaves plain text untouched' do
      tmpl = described_class.new('just text')
      expect(tmpl.render(%w[ignored])).to eq('just text')
    end
  end
end
