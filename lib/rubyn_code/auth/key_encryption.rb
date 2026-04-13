# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'securerandom'
require 'etc'
require 'socket'

module RubynCode
  module Auth
    # Encrypts and decrypts provider API keys at rest using AES-256-GCM.
    #
    # The encryption key is derived via PBKDF2 from machine-specific identifiers
    # (username, hostname, home directory) combined with a random salt stored in
    # ~/.rubyn-code/.encryption_salt. This means keys are only decryptable on the
    # same machine by the same user.
    #
    # Encrypted values are prefixed with "enc:v1:" so plaintext values from older
    # versions are transparently migrated on first read.
    module KeyEncryption
      CIPHER = 'aes-256-gcm'
      PREFIX = 'enc:v1:'
      IV_LENGTH = 12
      TAG_LENGTH = 16
      PBKDF2_ITERATIONS = 100_000
      KEY_LENGTH = 32
      SALT_LENGTH = 32

      class << self
        def encrypt(plaintext)
          return nil unless plaintext

          cipher = OpenSSL::Cipher.new(CIPHER).encrypt
          key = derive_key
          cipher.key = key
          iv = cipher.random_iv

          ciphertext = cipher.update(plaintext) + cipher.final
          tag = cipher.auth_tag(TAG_LENGTH)

          encoded = Base64.strict_encode64(iv + ciphertext + tag)
          "#{PREFIX}#{encoded}"
        end

        def decrypt(value)
          return nil unless value
          return value unless encrypted?(value)

          raw = Base64.strict_decode64(value.delete_prefix(PREFIX))
          decrypt_raw(raw)
        rescue OpenSSL::Cipher::CipherError, ArgumentError
          nil
        end

        def encrypted?(value)
          value.is_a?(String) && value.start_with?(PREFIX)
        end

        private

        def decrypt_raw(raw)
          iv = raw[0, IV_LENGTH]
          tag = raw[-TAG_LENGTH, TAG_LENGTH]
          ciphertext = raw[IV_LENGTH...-TAG_LENGTH]

          cipher = OpenSSL::Cipher.new(CIPHER).decrypt
          cipher.key = derive_key
          cipher.iv = iv
          cipher.auth_tag = tag
          (cipher.update(ciphertext) + cipher.final).force_encoding('UTF-8')
        end

        def derive_key
          OpenSSL::KDF.pbkdf2_hmac(
            machine_identity,
            salt: load_or_create_salt,
            iterations: PBKDF2_ITERATIONS,
            length: KEY_LENGTH,
            hash: 'SHA256'
          )
        end

        def machine_identity
          # Use the real UID's login name rather than Etc.getlogin. Etc.getlogin
          # reads the controlling tty's owner and can return "root" when the tty
          # is root-owned (common after `sudo`, and in some VSCode integrated
          # terminal setups) — even though the process itself is running as the
          # real user. That mismatch derives a different AES key on decrypt vs.
          # encrypt and the AEAD tag check fails, which surfaces as a misleading
          # "No <provider> API key configured" error.
          user = begin
            Etc.getpwuid(Process.uid).name
          rescue StandardError
            ENV['USER'] || Etc.getlogin || 'unknown'
          end
          [user, Socket.gethostname, Dir.home].join(':')
        end

        def load_or_create_salt
          path = salt_path
          if File.exist?(path)
            File.binread(path)
          else
            salt = SecureRandom.random_bytes(SALT_LENGTH)
            FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
            File.binwrite(path, salt)
            File.chmod(0o600, path)
            salt
          end
        end

        def salt_path
          File.join(Config::Defaults::HOME_DIR, '.encryption_salt')
        end
      end
    end
  end
end
