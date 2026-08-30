# frozen_string_literal: true

require 'spec_helper'
require 'rubyn_code/ide/server'

RSpec.describe RubynCode::IDE::Handlers::ProviderRemoveHandler do
  let(:server) { instance_double(RubynCode::IDE::Server, notify: nil) }
  let(:settings) { instance_double(RubynCode::Config::Settings, provider_config: { 'models' => ['model'] }, remove_provider: true) }
  let(:handler) { described_class.new(server) }

  before do
    allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)
    allow(RubynCode::Auth::TokenStore).to receive(:delete_provider_key)
  end

  it 'removes provider configuration and its key without returning credential data' do
    result = handler.call('name' => 'MiniMax')

    expect(settings).to have_received(:remove_provider).with('minimax')
    expect(RubynCode::Auth::TokenStore).to have_received(:delete_provider_key).with('minimax')
    expect(server).to have_received(:notify)
      .with('config/changed', 'key' => 'providers', 'provider' => 'minimax')
    expect(result).to eq('removed' => true, 'provider' => 'minimax')
  end

  it 'rejects an invalid provider before deleting anything' do
    result = handler.call('name' => '../../tokens')

    expect(result['removed']).to be(false)
    expect(settings).not_to have_received(:remove_provider)
    expect(RubynCode::Auth::TokenStore).not_to have_received(:delete_provider_key)
  end

  it 'does not delete a key when provider configuration is absent' do
    allow(settings).to receive(:provider_config).and_return(nil)

    result = handler.call('name' => 'missing')

    expect(result['removed']).to be(false)
    expect(RubynCode::Auth::TokenStore).not_to have_received(:delete_provider_key)
  end

  it 'keeps provider configuration when Keychain revocation fails' do
    allow(RubynCode::Auth::TokenStore).to receive(:delete_provider_key)
      .and_raise(RubynCode::Auth::ProviderKeychain::CredentialStoreError, 'macOS Keychain refused revocation')

    result = handler.call('name' => 'minimax')

    expect(result).to eq('removed' => false, 'error' => 'macOS Keychain refused revocation')
    expect(settings).not_to have_received(:remove_provider)
    expect(server).not_to have_received(:notify)
  end
end
