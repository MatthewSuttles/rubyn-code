# frozen_string_literal: true

require 'spec_helper'
require 'rubyn_code/memory/models'

RSpec.describe RubynCode::Memory::MemoryRecord do
  let(:record) do
    described_class.new(
      id: 'mem-1',
      project_path: '/test',
      tier: 'medium',
      category: 'code_pattern',
      content: 'Use guard clauses',
      relevance_score: 1.0,
      access_count: 0,
      expires_at: nil,
      metadata: nil,
      created_at: '2024-01-01T00:00:00Z',
      last_accessed_at: '2024-01-01T00:00:00Z'
    )
  end

  describe '#expired?' do
    it 'returns false when expires_at is nil' do
      expect(record.expired?).to be false
    end

    it 'returns true when expires_at is in the past' do
      expired = record.with(expires_at: '2020-01-01T00:00:00Z')
      expect(expired.expired?).to be true
    end

    it 'returns false when expires_at is in the future' do
      future = record.with(expires_at: (Time.now + 86_400).utc.iso8601)
      expect(future.expired?).to be false
    end

    it 'returns false for unparseable expires_at' do
      bad = record.with(expires_at: 'not-a-date')
      expect(bad.expired?).to be false
    end
  end

  describe '#short?, #medium?, #long?' do
    it 'returns true for matching tier' do
      expect(record.medium?).to be true
      expect(record.short?).to be false
      expect(record.long?).to be false
    end

    it 'returns true for short tier' do
      expect(record.with(tier: 'short').short?).to be true
    end

    it 'returns true for long tier' do
      expect(record.with(tier: 'long').long?).to be true
    end
  end

  describe '#to_h' do
    it 'returns a hash with all fields' do
      h = record.to_h
      expect(h[:id]).to eq('mem-1')
      expect(h[:tier]).to eq('medium')
      expect(h[:content]).to eq('Use guard clauses')
      expect(h[:category]).to eq('code_pattern')
    end
  end
end
