# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Auth::TokenResult do
  describe '#initialize' do
    it 'builds a valid oauth result' do
      result = described_class.new(
        access_token: 'sk-ant-xxx',
        refresh_token: 'rf-xxx',
        expires_at: Time.now + 3600,
        type: :oauth,
        source: :keychain
      )

      expect(result.access_token).to eq('sk-ant-xxx')
      expect(result.type).to eq(:oauth)
      expect(result.source).to eq(:keychain)
    end

    it 'builds a valid api_key result with nil optionals' do
      result = described_class.new(
        access_token: 'sk-openai-xxx',
        type: :api_key,
        source: :env
      )

      expect(result.access_token).to eq('sk-openai-xxx')
      expect(result.refresh_token).to be_nil
      expect(result.expires_at).to be_nil
    end

    it 'raises on empty access_token' do
      expect do
        described_class.new(access_token: '', type: :api_key, source: :env)
      end.to raise_error(ArgumentError, /access_token/)
    end

    it 'raises on nil access_token' do
      expect do
        described_class.new(access_token: nil, type: :api_key, source: :env)
      end.to raise_error(ArgumentError, /access_token/)
    end

    it 'raises on invalid type' do
      expect do
        described_class.new(access_token: 'x', type: :invalid, source: :env)
      end.to raise_error(ArgumentError, /type/)
    end

    it 'raises on non-symbol source' do
      expect do
        described_class.new(access_token: 'x', type: :api_key, source: 'env')
      end.to raise_error(ArgumentError, /source/)
    end
  end

  describe '#to_h' do
    it 'returns a hash matching the legacy contract' do
      time = Time.now + 3600
      result = described_class.new(
        access_token: 'tok',
        refresh_token: 'rf',
        expires_at: time,
        type: :oauth,
        source: :keychain
      )

      expect(result.to_h).to eq(
        access_token: 'tok',
        refresh_token: 'rf',
        expires_at: time,
        type: :oauth,
        source: :keychain
      )
    end
  end
end
