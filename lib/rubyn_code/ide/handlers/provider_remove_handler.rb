# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Removes one IDE-configured provider and its Rubyn-owned API key. The
      # response deliberately contains provider identity only—never secrets.
      class ProviderRemoveHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          name = params['name'].to_s.strip.downcase
          unless name.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
            return { 'removed' => false, 'error' => 'Provider name is invalid' }
          end

          settings = Config::Settings.new
          removed = settings.remove_provider(name)
          return { 'removed' => false, 'error' => 'Provider is not configured' } unless removed

          Auth::TokenStore.delete_provider_key(name)
          @server.notify('config/changed', { 'key' => 'providers', 'provider' => name })
          { 'removed' => true, 'provider' => name }
        rescue Config::Settings::LoadError => e
          { 'removed' => false, 'error' => e.message }
        end
      end
    end
  end
end
