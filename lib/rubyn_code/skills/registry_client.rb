# frozen_string_literal: true

require 'faraday'
require 'json'

module RubynCode
  module Skills
    # Fetches skill pack metadata and content from the rubyn.ai registry API.
    #
    # GET /api/skills          → list available packs
    # GET /api/skills/:name    → pack metadata + content
    class RegistryClient
      DEFAULT_BASE_URL = 'https://rubyn.ai'
      TIMEOUT_SECONDS  = 10

      attr_reader :base_url

      def initialize(base_url: nil)
        @base_url = base_url || ENV.fetch('RUBYN_REGISTRY_URL', DEFAULT_BASE_URL)
      end

      # Fetch the full catalog of available skill packs.
      #
      # @return [Array<Hash>] each with :name, :description, :version, :category
      # @raise [RegistryError] on network or parse failure
      def list_packs
        response = connection.get('/api/skills')
        parse_response(response)
      rescue Faraday::Error => e
        raise RegistryError, "Failed to fetch skill packs: #{e.message}"
      end

      # Search packs by keyword.
      #
      # @param query [String]
      # @return [Array<Hash>]
      def search_packs(query)
        response = connection.get('/api/skills', { q: query })
        parse_response(response)
      rescue Faraday::Error => e
        raise RegistryError, "Failed to search skill packs: #{e.message}"
      end

      # Fetch a single pack's full content for installation.
      #
      # @param name [String] pack name
      # @return [Hash] with :name, :description, :version, :files (Array<Hash>)
      # @raise [RegistryError] on not found or network failure
      def fetch_pack(name)
        response = connection.get("/api/skills/#{encode_name(name)}")
        parse_response(response)
      rescue Faraday::Error => e
        raise RegistryError, "Failed to fetch pack '#{name}': #{e.message}"
      end

      private

      def connection
        @connection ||= Faraday.new(url: base_url) do |f|
          f.request :url_encoded
          f.response :raise_error
          f.options.timeout = TIMEOUT_SECONDS
          f.options.open_timeout = TIMEOUT_SECONDS
          f.headers['Accept'] = 'application/json'
          f.headers['User-Agent'] = "rubyn-code/#{RubynCode::VERSION}"
        end
      end

      def parse_response(response)
        JSON.parse(response.body, symbolize_names: true)
      rescue JSON::ParserError => e
        raise RegistryError, "Invalid response from registry: #{e.message}"
      end

      def encode_name(name)
        ERB::Util.url_encode(name.to_s)
      end
    end

    class RegistryError < RubynCode::Error; end
  end
end
