# frozen_string_literal: true

require 'spec_helper'
require 'rubyn_code/ide/server'

RSpec.describe RubynCode::IDE::Handlers::ProviderRemoveHandler do
  let(:server) { instance_double(RubynCode::IDE::Server, notify: nil) }
  let(:settings) { instance_double(RubynCode::Config::Settings, remove_provider: true) }
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
    allow(settings).to receive(:remove_provider).and_return(false)

    result = handler.call('name' => 'missing')

    expect(result['removed']).to be(false)
    expect(RubynCode::Auth::TokenStore).not_to have_received(:delete_provider_key)
  end
end
