# frozen_string_literal: true

require 'faraday'
require 'json'

module RubynCode
  module Skills
    # HTTP client for the rubyn.ai skill packs API.
    #
    # All requests include the required `User-Accept: Rubyn Code` header.
    # The API returns 403 without it.
    class RegistryClient
      BASE_URL = 'https://rubyn.ai/api/v1/skills'
      USER_ACCEPT_HEADER = 'Rubyn Code'
      DEFAULT_TIMEOUT = 10

      # @param base_url [String] override for testing
      # @param timeout [Integer] connection + read timeout in seconds
      def initialize(base_url: BASE_URL, timeout: DEFAULT_TIMEOUT)
        @base_url = base_url
        @timeout = timeout
      end

      # Fetch the full pack catalog.
      #
      # @return [Hash] parsed JSON with "packs", "categories", etc.
      # @raise [RegistryError] on HTTP or parse failure
      def fetch_catalog
        response = get('/packs')
        parse_json(response)
      end

      # Fetch metadata for a single pack (including file listing).
      #
      # @param name [String] pack name (e.g. "hotwire")
      # @return [Hash] parsed pack metadata
      # @raise [RegistryError] on HTTP or parse failure
      def fetch_pack(name)
        response = get("/packs/#{encode(name)}")
        parse_json(response)
      end

      # Download a single skill file from a pack.
      #
      # @param pack_name [String]
      # @param file_path [String] relative path (e.g. "turbo_frames.md")
      # @param etag [String, nil] previous ETag for conditional fetch
      # @return [Hash] { content:, etag:, not_modified: }
      # @raise [RegistryError] on HTTP failure
      def fetch_file(pack_name, file_path, etag: nil)
        headers = {}
        headers['If-None-Match'] = etag if etag

        response = get("/packs/#{encode(pack_name)}/files/#{encode(file_path)}", headers: headers)

        if response.status == 304
          { content: nil, etag: etag, not_modified: true }
        else
          { content: response.body, etag: response.headers['etag'], not_modified: false }
        end
      end

      # Fetch pack suggestions based on detected gems.
      #
      # @param gems [Array<String>] gem names from the Gemfile
      # @return [Array<Hash>] suggestions with :name and :reason
      # @raise [RegistryError] on HTTP failure
      def fetch_suggestions(gems)
        return [] if gems.empty?

        response = get("/packs/suggest", params: { gems: gems.join(',') })
        data = parse_json(response)
        data['suggestions'] || []
      end

      # @return [Boolean] true if the registry is reachable
      def available?
        connection.head('/packs')
        true
      rescue StandardError
        false
      end

      private

      def get(path, headers: {}, params: {})
        response = connection.get(path) do |req|
          req.params = params unless params.empty?
          headers.each { |k, v| req.headers[k] = v }
        end

        unless response.success? || response.status == 304
          raise RegistryError, "Registry returned #{response.status}: #{response.body}"
        end

        response
      end

      def connection
        @connection ||= Faraday.new(url: @base_url) do |f|
          f.headers['User-Accept'] = USER_ACCEPT_HEADER
          f.headers['Accept'] = 'application/json'
          f.options.timeout = @timeout
          f.options.open_timeout = @timeout
          f.adapter Faraday.default_adapter
        end
      end

      def parse_json(response)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise RegistryError, "Invalid JSON from registry: #{e.message}"
      end

      def encode(value)
        ERB::Util.url_encode(value)
      end
    end

    class RegistryError < StandardError; end
  end
end
