# frozen_string_literal: true

require 'fileutils'
require 'json'

module RubynCode
  module Skills
    # Manages local installation, removal, and updates of skill packs
    # with ETag caching and offline fallback support.
    #
    # Installed packs live under ~/.rubyn-code/skill-packs/<pack-name>/.
    # A manifest.json in each pack directory records metadata for listing,
    # version tracking, and ETag-based conditional updates.
    class PackManager
      PACKS_DIR       = File.join(Config::Defaults::HOME_DIR, 'skill-packs')
      MANIFEST_FILE   = 'manifest.json'
      ETAG_CACHE_FILE = '.etags.json'
      SAFE_NAME_RE    = /\A[a-zA-Z0-9_-]+\z/

      def initialize(packs_dir: PACKS_DIR)
        @packs_dir = packs_dir
      end

      # Install a pack from registry response data.
      #
      # @param pack_data [Hash] from RegistryClient#fetch_pack[:data]
      #   Expected keys: :name, :description, :version, :files
      #   Each file: { filename: "name.md", content: "..." }
      # @param etag [String, nil] ETag from registry response for cache tracking
      # @return [Hash] installed pack metadata
      def install(pack_data, etag: nil)
        name = fetch_key(pack_data, :name)
        raise ArgumentError, 'Pack data must include a name' if name.nil? || name.empty?

        validate_name!(name)
        pack_dir = pack_path(name)
        FileUtils.mkdir_p(pack_dir)

        write_files(pack_dir, pack_data)
        write_manifest(pack_dir, pack_data, etag: etag)
        store_etag(name, etag) if etag

        manifest(name)
      end

      # Update a single installed pack using ETag-based conditional fetch.
      # Returns :updated, :up_to_date, or :not_installed.
      #
      # @param name [String] pack name
      # @param registry [RegistryClient] registry client to fetch from
      # @return [Symbol] update result
      def update(name, registry)
        validate_name!(name)
        return :not_installed unless installed?(name)

        cached_etag = load_etag(name)
        result = registry.fetch_pack(name, etag: cached_etag)

        return :up_to_date if result[:not_modified]

        install(result[:data], etag: result[:etag])
        :updated
      end

      # Update all installed packs. Returns a hash of { name => status }.
      #
      # @param registry [RegistryClient]
      # @return [Hash<String, Symbol>]
      def update_all(registry)
        installed.each_with_object({}) do |pack, results|
          name = pack[:name]
          results[name] = update(name, registry)
        rescue RegistryError => e
          results[name] = :"error: #{e.message}"
        end
      end

      # Remove an installed pack with path traversal protection.
      #
      # @param name [String] pack name
      # @return [Boolean] true if removed, false if not found
      def remove(name)
        validate_name!(name)
        pack_dir = pack_path(name)
        return false unless File.directory?(pack_dir)

        # Verify the resolved path is within packs_dir to prevent traversal
        real_pack = File.realpath(pack_dir)
        real_base = File.realpath(@packs_dir)
        unless real_pack.start_with?("#{real_base}/")
          raise ArgumentError, "Pack directory is outside the skill-packs directory"
        end

        FileUtils.rm_rf(pack_dir)
        remove_etag(name)
        true
      end

      # List all installed packs.
      #
      # @return [Array<Hash>] each with :name, :description, :version, :installed_at
      def installed
        return [] unless File.directory?(@packs_dir)

        Dir.children(@packs_dir)
           .select { |d| File.directory?(File.join(@packs_dir, d)) }
           .reject { |d| d.start_with?('.') }
           .filter_map { |d| manifest(d) }
           .sort_by { |m| m[:name] }
      end

      # Check if a pack is installed.
      #
      # @param name [String]
      # @return [Boolean]
      def installed?(name)
        manifest_path = File.join(@packs_dir, name.to_s, MANIFEST_FILE)
        File.exist?(manifest_path)
      end

      # Return the skills directory for a pack (for catalog integration).
      #
      # @param name [String]
      # @return [String, nil] path to pack directory or nil
      def pack_skills_dir(name)
        dir = pack_path(name)
        File.directory?(dir) ? dir : nil
      end

      # Return all installed pack directories (for skill loader integration).
      #
      # @return [Array<String>]
      def all_pack_dirs
        installed.map { |pack| pack_path(pack[:name]) }.select { |d| File.directory?(d) }
      end

      private

      def pack_path(name)
        File.join(@packs_dir, name.to_s)
      end

      # Validate pack name contains only safe characters.
      def validate_name!(name)
        return if name.to_s.match?(SAFE_NAME_RE)

        raise ArgumentError,
              "Invalid pack name: '#{name}'. Only letters, numbers, hyphens, and underscores allowed."
      end

      def fetch_key(hash, key)
        hash[key] || hash[key.to_s]
      end

      def manifest(name)
        path = File.join(@packs_dir, name.to_s, MANIFEST_FILE)
        return nil unless File.exist?(path)

        JSON.parse(File.read(path), symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      def write_files(pack_dir, pack_data)
        files = fetch_key(pack_data, :files) || []
        files.each { |file| write_single_file(pack_dir, file) }
      end

      def write_single_file(pack_dir, file)
        filename = fetch_key(file, :filename)
        content  = fetch_key(file, :content)
        return if filename.nil? || content.nil?

        # Prevent path traversal in filenames
        safe_name = File.basename(filename)
        File.write(File.join(pack_dir, safe_name), content)
      end

      def write_manifest(pack_dir, pack_data, etag: nil)
        manifest_data = {
          name: fetch_key(pack_data, :name),
          description: fetch_key(pack_data, :description) || '',
          version: fetch_key(pack_data, :version) || '1.0.0',
          skillCount: (fetch_key(pack_data, :files) || []).size,
          etag: etag,
          installed_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        }

        File.write(
          File.join(pack_dir, MANIFEST_FILE),
          JSON.pretty_generate(manifest_data)
        )
      end

      # ── ETag Cache ────────────────────────────────────────────────

      def etag_cache_path
        File.join(@packs_dir, ETAG_CACHE_FILE)
      end

      def load_etag_cache
        return {} unless File.exist?(etag_cache_path)

        JSON.parse(File.read(etag_cache_path))
      rescue JSON::ParserError
        {}
      end

      def load_etag(name)
        load_etag_cache[name.to_s]
      end

      def store_etag(name, etag)
        FileUtils.mkdir_p(@packs_dir)
        cache = load_etag_cache
        cache[name.to_s] = etag
        File.write(etag_cache_path, JSON.pretty_generate(cache))
      end

      def remove_etag(name)
        return unless File.exist?(etag_cache_path)

        cache = load_etag_cache
        cache.delete(name.to_s)
        File.write(etag_cache_path, JSON.pretty_generate(cache))
      end
    end
  end
end
