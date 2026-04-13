# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::Auth::KeyEncryption do
  let(:tmpdir) { Dir.mktmpdir('rubyn_enc_test_') }

  before do
    stub_const('RubynCode::Config::Defaults::HOME_DIR', tmpdir)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.encrypt and .decrypt' do
    it 'round-trips a plaintext value' do
      encrypted = described_class.encrypt('sk-test-key-123')
      expect(described_class.decrypt(encrypted)).to eq('sk-test-key-123')
    end

    it 'produces different ciphertext each time (random IV)' do
      a = described_class.encrypt('same-key')
      b = described_class.encrypt('same-key')
      expect(a).not_to eq(b)
    end

    it 'prefixes encrypted values with enc:v1:' do
      encrypted = described_class.encrypt('my-key')
      expect(encrypted).to start_with('enc:v1:')
    end

    it 'returns nil for nil input' do
      expect(described_class.encrypt(nil)).to be_nil
      expect(described_class.decrypt(nil)).to be_nil
    end

    it 'returns nil when decryption fails (tampered data)' do
      encrypted = described_class.encrypt('real-key')
      tampered = "#{encrypted}TAMPERED"
      expect(described_class.decrypt(tampered)).to be_nil
    end

    it 'handles empty string' do
      encrypted = described_class.encrypt('')
      expect(described_class.decrypt(encrypted)).to eq('')
    end

    it 'handles unicode values' do
      encrypted = described_class.encrypt('key-with-emoji-🔑')
      expect(described_class.decrypt(encrypted)).to eq('key-with-emoji-🔑')
    end
  end

  describe '.encrypted?' do
    it 'returns true for encrypted values' do
      encrypted = described_class.encrypt('test')
      expect(described_class.encrypted?(encrypted)).to be true
    end

    it 'returns false for plaintext values' do
      expect(described_class.encrypted?('sk-plain-key')).to be false
    end

    it 'returns false for nil' do
      expect(described_class.encrypted?(nil)).to be false
    end
  end

  describe 'machine identity (regression)' do
    # Regression: Etc.getlogin reads the controlling tty's owner, not the real
    # UID. Under sudo or some VSCode terminal setups the tty is root-owned and
    # Etc.getlogin returns "root" while the process is actually the real user,
    # which caused decryption to fail with a misleading "no API key" error.
    # We derive identity from the real UID via Etc.getpwuid instead.
    it 'derives identity from the real UID, not the controlling tty' do
      allow(Etc).to receive(:getlogin).and_return('root')
      allow(Etc).to receive(:getpwuid).with(Process.uid)
                                      .and_return(instance_double(Etc::Passwd, name: 'realuser'))

      identity = described_class.send(:machine_identity)
      expect(identity).to start_with('realuser:')
      expect(identity).not_to start_with('root:')
    end
  end

  describe 'salt persistence' do
    it 'creates a salt file on first use' do
      described_class.encrypt('test')
      salt_path = File.join(tmpdir, '.encryption_salt')
      expect(File.exist?(salt_path)).to be true
    end

    it 'sets restrictive permissions on salt file' do
      described_class.encrypt('test')
      salt_path = File.join(tmpdir, '.encryption_salt')
      mode = File.stat(salt_path).mode & 0o777
      expect(mode).to eq(0o600)
    end

    it 'reuses the same salt across calls' do
      described_class.encrypt('first')
      salt_path = File.join(tmpdir, '.encryption_salt')
      salt1 = File.binread(salt_path)

      described_class.encrypt('second')
      salt2 = File.binread(salt_path)

      expect(salt1).to eq(salt2)
    end

    it 'can decrypt values encrypted in the same session' do
      encrypted1 = described_class.encrypt('key-one')
      encrypted2 = described_class.encrypt('key-two')
      expect(described_class.decrypt(encrypted1)).to eq('key-one')
      expect(described_class.decrypt(encrypted2)).to eq('key-two')
    end
  end
end
