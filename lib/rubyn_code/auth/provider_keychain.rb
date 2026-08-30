# frozen_string_literal: true

require 'fiddle/import'

module RubynCode
  module Auth
    # Stores named provider API keys with macOS Security.framework. Credentials
    # remain in process memory and never enter command arguments or files.
    module ProviderKeychain
      SERVICE = 'ai.rubyn-code.provider-key'
      SECURITY_FRAMEWORK = '/System/Library/Frameworks/Security.framework/Security'
      CORE_FOUNDATION = '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
      SUCCESS = 0
      ITEM_NOT_FOUND = -25_300
      POINTER_PACK = 'J'
      UINT32_PACK = 'L'

      class CredentialStoreError < StandardError; end

      if RUBY_PLATFORM.include?('darwin')
        module Native
          extend Fiddle::Importer

          dlload SECURITY_FRAMEWORK, CORE_FOUNDATION
          extern 'int SecKeychainAddGenericPassword(' \
                 'void*, unsigned int, const char*, unsigned int, const char*, unsigned int, const void*, void*)'
          extern 'int SecKeychainFindGenericPassword(' \
                 'void*, unsigned int, const char*, unsigned int, const char*, unsigned int*, void**, void**)'
          extern 'int SecKeychainItemModifyAttributesAndData(void*, void*, unsigned int, const void*)'
          extern 'int SecKeychainItemDelete(void*)'
          extern 'int SecKeychainItemFreeContent(void*, void*)'
          extern 'void CFRelease(void*)'
        end
      end

      class << self
        def available?
          const_defined?(:Native, false) && !ENV['RUBYN_TESTING']
        end

        def save(provider, key)
          account = provider.to_s
          status, item = find_item(account)
          result = if status == SUCCESS
                     Native.SecKeychainItemModifyAttributesAndData(item, nil, key.bytesize, key)
                   elsif status == ITEM_NOT_FOUND
                     Native.SecKeychainAddGenericPassword(
                       nil, SERVICE.bytesize, SERVICE, account.bytesize, account, key.bytesize, key, nil
                     )
                   else
                     status
                   end
          raise CredentialStoreError, 'macOS Keychain did not store the provider credential' unless result == SUCCESS
        ensure
          release(item)
        end

        def load(provider)
          account = provider.to_s
          length = uint32_buffer
          data = pointer_buffer
          item = pointer_buffer
          status = Native.SecKeychainFindGenericPassword(
            nil, SERVICE.bytesize, SERVICE, account.bytesize, account, length, data, item
          )
          return nil if status == ITEM_NOT_FOUND
          raise CredentialStoreError, 'macOS Keychain did not read the provider credential' unless status == SUCCESS

          content = pointer_value(data)
          content[0, uint32_value(length)].force_encoding('UTF-8')
        ensure
          Native.SecKeychainItemFreeContent(nil, content) if content
          release(pointer_value(item)) if item
        end

        def delete(provider)
          status, item = find_item(provider.to_s)
          return false if status == ITEM_NOT_FOUND
          raise CredentialStoreError, 'macOS Keychain did not locate the provider credential' unless status == SUCCESS

          deleted = Native.SecKeychainItemDelete(item)
          raise CredentialStoreError, 'macOS Keychain did not revoke the provider credential' unless deleted == SUCCESS

          true
        ensure
          release(item)
        end

        private

        def find_item(account)
          item = pointer_buffer
          status = Native.SecKeychainFindGenericPassword(
            nil, SERVICE.bytesize, SERVICE, account.bytesize, account, nil, nil, item
          )
          [status, pointer_value(item)]
        end

        def pointer_buffer
          buffer = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          buffer[0, Fiddle::SIZEOF_VOIDP] = [0].pack(POINTER_PACK)
          buffer
        end

        def pointer_value(buffer)
          address = buffer[0, Fiddle::SIZEOF_VOIDP].unpack1(POINTER_PACK)
          Fiddle::Pointer.new(address) unless address.zero?
        end

        def uint32_buffer
          buffer = Fiddle::Pointer.malloc(4)
          buffer[0, 4] = [0].pack(UINT32_PACK)
          buffer
        end

        def uint32_value(buffer)
          buffer[0, 4].unpack1(UINT32_PACK)
        end

        def release(pointer)
          Native.CFRelease(pointer) if pointer
        end
      end
    end
  end
end
