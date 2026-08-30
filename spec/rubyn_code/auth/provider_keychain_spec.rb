# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Auth::ProviderKeychain do
  it 'keeps the real Keychain out of isolated test runs' do
    expect(described_class.available?).to be(false)
  end

  it 'uses the native framework rather than a credential-bearing command' do
    expect(described_class.const_defined?(:SECURITY_EXECUTABLE, false)).to be(false)
    expect(described_class.const_defined?(:Native, false)).to be(RUBY_PLATFORM.include?('darwin'))
  end

  it 'treats a missing credential as an ordinary absence' do
    allow(described_class).to receive(:find_item).with('missing').and_return([described_class::ITEM_NOT_FOUND, nil])

    expect(described_class.delete('missing')).to be(false)
  end

  it 'fails closed when Keychain revocation fails' do
    skip 'macOS Security.framework is unavailable on this platform' unless RUBY_PLATFORM.include?('darwin')

    item = instance_double(Fiddle::Pointer)
    allow(described_class).to receive(:find_item).with('groq').and_return([described_class::SUCCESS, item])
    allow(described_class::Native).to receive(:SecKeychainItemDelete).with(item).and_return(-1)
    allow(described_class::Native).to receive(:CFRelease).with(item)

    expect { described_class.delete('groq') }
      .to raise_error(described_class::CredentialStoreError, 'macOS Keychain did not revoke the provider credential')
  end
end
