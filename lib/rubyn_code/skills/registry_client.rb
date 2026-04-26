# frozen_string_literal: true

require 'faraday'
require 'json'

module RubynCode
  module Skills
    # HTTP client for the rubyn.ai skill packs registry API.
    #
    # All requests send User-Accept: Rubyn Code to identify
    # rubyn-code clients. Supports ETag-based conditional requests for
    # efficient cache validation and offline resilience.
    #
    # GET /api/v1/skills/packs           -> catalog of available packs
    # GET /api/v1/skills/packs/:name     -> single pack metadata + files
    class RegistryClient
      DEFAULT_BASE_URL = 'https://rubyn.ai'
      TIMEOUT_SECONDS  = 10
      USER_ACCEPT_HEADER = 'Rubyn Code'
      LEADING_SLASHES_REGEX = %r{\A/+}

      attr_reader :base_url

      def initialize(base_url: nil)
        @base_url = base_url || ENV.fetch('RUBYN_REGISTRY_URL', DEFAULT_BASE_URL)
      end

      # List all available packs (returns flat array for CLI commands).
      #
      # @param etag [String, nil] cached ETag for conditional request
      # @return [Array<Hash>] array of pack metadata
      # @raise [RegistryError] on network or parse failure
      def list_packs(etag: nil)
        fetch_catalog(etag: etag)[:data] || []
      end

      # Fetch the full catalog of available skill packs.
      #
      # @param etag [String, nil] cached ETag for conditional request
      # @return [Hash] { data: Array<Hash>, etag: String|nil, not_modified: Boolean }
      # @raise [RegistryError] on network or parse failure
      def fetch_catalog(etag: nil)
        response = conditional_get('/api/v1/skills/packs', etag: etag)
        return not_modified_result if response.status == 304

        data = validate_and_parse(response)
        packs = normalize_packs(data)
        { data: packs, etag: response.headers['etag'], not_modified: false }
      rescue Faraday::Error => e
        raise RegistryError, "Failed to fetch skill catalog: #{e.message}"
      end

      # Search packs by keyword.
      # Note: The registry API does not support server-side search.
      # This method fetches the catalog and filters locally.
      #
      # @param query [String]
      # @param etag [String, nil] cached ETag for conditional request
      # @return [Hash] { data: Array<Hash>, etag: String|nil, not_modified: Boolean }
      # @raise [RegistryError] on network or parse failure
      def search_packs(query, etag: nil)
        catalog = fetch_catalog(etag: etag)
        return catalog if catalog[:not_modified]

        q = query.to_s.downcase
        filtered = catalog[:data].select { |pack| matches_query?(pack, q) }
        { data: filtered, etag: catalog[:etag], not_modified: false }
      end

      # Fetch pack suggestions based on detected gems.
      #
      # @param gems [Array<String>] list of gem names detected in the project
      # @return [Array<Hash>] array of { name: String, reason: String }
      # @raise [RegistryError] on network or parse failure
      def fetch_suggestions(gems)
        return [] if gems.empty?

        gems_param = gems.join(',')
        response = connection.get('/api/v1/skills/packs/suggest', { gems: gems_param })
        return [] if response.status == 404

        data = validate_and_parse(response)
        suggestions = data[:suggestions] || data['suggestions'] || []
        suggestions.is_a?(Array) ? suggestions : []
      rescue Faraday::Error => e
        raise RegistryError, "Failed to fetch suggestions: #{e.message}"
      end

      def matches_query?(pack, query)
        pack_name = pack[:name].to_s.downcase
        pack_display = pack[:displayName].to_s.downcase
        pack_desc = pack[:description].to_s.downcase
        pack_tags = pack[:tags] || []

        pack_name.include?(query) ||
          pack_display.include?(query) ||
          pack_desc.include?(query) ||
          pack_tags.any? { |t| t.to_s.downcase.include?(query) }
      end

      # Fetch a single pack's full content for installation.
      # Fetches pack metadata and all skill file contents.
      #
      # @param name [String] pack name (validated for safe characters)
      # @param etag [String, nil] cached ETag for conditional request
      # @return [Hash] { data: Hash, etag: String|nil, not_modified: Boolean }
      # @raise [RegistryError] on not found, validation, or network failure
      def fetch_pack(name, etag: nil)
        validate_pack_name!(name)
        response = conditional_get("/api/v1/skills/packs/#{encode_name(name)}", etag: etag)
        return not_modified_result if response.status == 304

        data = validate_and_parse(response)
        validate_pack_response!(data, name)

        # Fetch individual file contents
        files = fetch_key(data, :files) || []
        data_with_content = fetch_file_contents(name, data, files)

        { data: data_with_content, etag: response.headers['etag'], not_modified: false }
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
          f.headers['User-Accept'] = USER_ACCEPT_HEADER
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

      def fetch_key(hash, key)
        hash[key] || hash[key.to_s]
      end

      # Fetch markdown content for each file in the pack and transform
      # into the format expected by PackManager: { filename, content }
      def fetch_file_contents(pack_name, pack_data, files)
        return pack_data if files.empty?

        files_with_content = files.map do |file|
          path = fetch_key(file, :path)
          content = fetch_file(pack_name, path)
          { filename: path, content: content }
        rescue RegistryError
          # Skip files that fail to load
          nil
        end.compact

        pack_data.merge(files: files_with_content)
      end

      # Fetch a single skill file's markdown content.
      #
      # @param pack_name [String]
      # @param file_path [String]
      # @return [String] file content
      # @raise [RegistryError] on not found or network failure
      def fetch_file(pack_name, file_path)
        validate_pack_name!(pack_name)
        safe_path = file_path.to_s.gsub('..', '').gsub(LEADING_SLASHES_REGEX, '')
        response = connection.get("/api/v1/skills/packs/#{encode_name(pack_name)}/files/#{ERB::Util.url_encode(safe_path)}")
        return response.body if response.success?

        raise RegistryError, "Failed to fetch file '#{file_path}' from pack '#{pack_name}'"
      rescue Faraday::Error => e
        raise RegistryError, "Failed to fetch file '#{file_path}': #{e.message}"
      end

      def not_modified_result
        { data: nil, etag: nil, not_modified: true }
      end
    end

    class RegistryError < RubynCode::Error; end
  end
end
