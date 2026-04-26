# frozen_string_literal: true

require 'faraday'
require 'json'

module RubynCode
  module Skills
    # HTTP client for the rubyn.ai skill packs registry API.
    #
    # All requests send Accept: application/vnd.rubyn-code to identify
    # rubyn-code clients. Supports ETag-based conditional requests for
    # efficient cache validation and offline resilience.
    #
    # GET /api/skills          -> catalog of available packs
    # GET /api/skills/:name    -> single pack metadata + files
    class RegistryClient
      DEFAULT_BASE_URL = 'https://rubyn.ai'
      TIMEOUT_SECONDS  = 10
      ACCEPT_HEADER    = 'application/vnd.rubyn-code'

      attr_reader :base_url

      def initialize(base_url: nil)
        @base_url = base_url || ENV.fetch('RUBYN_REGISTRY_URL', DEFAULT_BASE_URL)
      end

      # Fetch the full catalog of available skill packs.
      #
      # @param etag [String, nil] cached ETag for conditional request
      # @return [Hash] { data: Array<Hash>, etag: String|nil, not_modified: Boolean }
      # @raise [RegistryError] on network or parse failure
      def fetch_catalog(etag: nil)
        response = conditional_get('/api/skills', etag: etag)
        return not_modified_result if response.status == 304

        data = validate_and_parse(response)
        packs = normalize_packs(data)
        { data: packs, etag: response.headers['etag'], not_modified: false }
      rescue Faraday::Error => e
        raise RegistryError, "Failed to fetch skill catalog: #{e.message}"
      end

      # Search packs by keyword.
      #
      # @param query [String]
      # @param etag [String, nil] cached ETag for conditional request
      # @return [Hash] { data: Array<Hash>, etag: String|nil, not_modified: Boolean }
      # @raise [RegistryError] on network or parse failure
      def search_packs(query, etag: nil)
        response = conditional_get('/api/skills', params: { q: query }, etag: etag)
        return not_modified_result if response.status == 304

        data = validate_and_parse(response)
        packs = normalize_packs(data)
        { data: packs, etag: response.headers['etag'], not_modified: false }
      rescue Faraday::Error => e
        raise RegistryError, "Failed to search skill packs: #{e.message}"
      end

      # Fetch a single pack's full content for installation.
      #
      # @param name [String] pack name (validated for safe characters)
      # @param etag [String, nil] cached ETag for conditional request
      # @return [Hash] { data: Hash, etag: String|nil, not_modified: Boolean }
      # @raise [RegistryError] on not found, validation, or network failure
      def fetch_pack(name, etag: nil)
        validate_pack_name!(name)
        response = conditional_get("/api/skills/#{encode_name(name)}", etag: etag)
        return not_modified_result if response.status == 304

        data = validate_and_parse(response)
        validate_pack_response!(data, name)
        { data: data, etag: response.headers['etag'], not_modified: false }
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
          f.headers['Accept'] = ACCEPT_HEADER
          f.headers['User-Agent'] = "rubyn-code/#{RubynCode::VERSION}"
        end
      end

      # Perform a GET with optional ETag-based conditional caching.
      # Sends If-None-Match when an ETag is provided; server returns
      # 304 Not Modified if content hasn't changed.
      def conditional_get(path, etag: nil, params: {})
        connection.get(path) do |req|
          req.params.merge!(params) unless params.empty?
          req.headers['If-None-Match'] = etag if etag
        end
      end

      def validate_and_parse(response)
        body = response.body.to_s.strip
        raise RegistryError, 'Empty response from registry' if body.empty?

        JSON.parse(body, symbolize_names: true)
      rescue JSON::ParserError => e
        raise RegistryError, "Invalid response from registry: #{e.message}"
      end

      # Normalize response into an array of pack hashes.
      # Handles both bare arrays and { packs: [...] } wrapper shapes.
      def normalize_packs(data)
        return data if data.is_a?(Array)
        return data[:packs] if data.is_a?(Hash) && data[:packs].is_a?(Array)

        raise RegistryError, 'Unexpected catalog format from registry'
      end

      def validate_pack_response!(data, name)
        return if data.is_a?(Hash) && (data[:name] || data[:files])

        raise RegistryError, "Invalid pack response for '#{name}': missing name or files"
      end

      # Only allow alphanumeric, hyphens, and underscores in pack names.
      def validate_pack_name!(name)
        return if name.to_s.match?(/\A[a-zA-Z0-9_-]+\z/)

        raise RegistryError,
              "Invalid pack name: '#{name}'. Only letters, numbers, hyphens, and underscores allowed."
      end

      def encode_name(name)
        ERB::Util.url_encode(name.to_s)
      end

      def not_modified_result
        { data: nil, etag: nil, not_modified: true }
      end
    end

    class RegistryError < RubynCode::Error; end
  end
end
