# frozen_string_literal: true

require 'json'
require 'fileutils'

module RubynCode
  module Skills
    # Downloads and installs skill packs from the registry.
    #
    # Handles ETag caching, version comparison, and offline fallback.
    # Installs to `.rubyn-code/skills/<pack>/` (project) by default,
    # or `~/.rubyn-code/skills/<pack>/` with the --global flag.
    class PackInstaller
      MANIFEST_FILE = '.manifest.json'

      # @param registry_client [RegistryClient]
      # @param project_root [String] path to the project root
      # @param global [Boolean] install to ~/.rubyn-code/skills/ instead of project
      def initialize(registry_client:, project_root:, global: false)
        @client = registry_client
        @project_root = project_root
        @global = global
      end

      # Install one or more packs by name.
      #
      # @param names [Array<String>] pack names
      # @param update [Boolean] update without prompting if already installed
      # @yield [event, data] progress events
      # @yieldparam event [Symbol] :fetching, :downloading, :installed, :up_to_date, :error
      # @yieldparam data [Hash] event-specific data
      # @return [Array<Hash>] results per pack ({ name:, status:, files: })
      def install(names, update: false, &block)
        names.map { |name| install_single(name, update: update, &block) }
      end

      # Update all installed packs to their latest versions.
      #
      # @yield [event, data] progress events
      # @return [Array<Hash>] results per pack
      def update_all(&block)
        installed = installed_packs
        return [] if installed.empty?

        installed.map { |manifest| install_single(manifest['name'], update: true, &block) }
      end

      # Remove an installed pack.
      #
      # @param name [String] pack name
      # @return [Boolean] true if removed
      def remove(name)
        dir = pack_dir(name)
        return false unless Dir.exist?(dir)

        FileUtils.rm_rf(dir)
        true
      end

      # List installed packs with their metadata.
      #
      # @return [Array<Hash>] installed pack manifests
      def installed_packs
        dir = skills_base_dir
        return [] unless Dir.exist?(dir)

        Dir.children(dir)
           .select { |d| File.directory?(File.join(dir, d)) }
           .filter_map { |d| read_manifest(d) }
      end

      # Check if a specific pack is installed.
      #
      # @param name [String]
      # @return [Boolean]
      def installed?(name)
        File.exist?(manifest_path(name))
      end

      # Read the installed manifest for a pack.
      #
      # @param name [String]
      # @return [Hash, nil]
      def read_manifest(name)
        path = manifest_path(name)
        return nil unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil
      end

      private

      def install_single(name, update: false)
        yield(:fetching, { name: name }) if block_given?

        pack_meta = @client.fetch_pack(name)
        files = pack_meta['files'] || []

        existing = read_manifest(name)
        if existing && !update
          if existing['version'] == pack_meta['version']
            yield(:up_to_date, { name: name, version: pack_meta['version'] }) if block_given?
            return { name: name, status: :up_to_date, files: [] }
          end
        end

        etags = load_etags(name)
        downloaded = download_files(name, files, etags)

        yield(:downloading, { name: name, total: files.size, downloaded: downloaded.size }) if block_given?

        write_manifest(name, pack_meta)
        save_etags(name, etags)

        yield(:installed, { name: name, version: pack_meta['version'], files: downloaded }) if block_given?

        { name: name, status: :installed, files: downloaded }
      rescue RegistryError => e
        yield(:error, { name: name, message: e.message }) if block_given?
        { name: name, status: :error, message: e.message }
      end

      def download_files(pack_name, files, etags)
        dir = pack_dir(pack_name)
        FileUtils.mkdir_p(dir)

        downloaded = []

        files.each do |file_info|
          path = file_info['path']
          result = @client.fetch_file(pack_name, path, etag: etags[path])

          if result[:not_modified]
            next
          end

          File.write(File.join(dir, path), result[:content])
          etags[path] = result[:etag] if result[:etag]
          downloaded << path
        end

        downloaded
      end

      def write_manifest(name, pack_meta)
        manifest = {
          'name' => pack_meta['name'],
          'displayName' => pack_meta['displayName'],
          'version' => pack_meta['version'],
          'installedAt' => Time.now.utc.iso8601,
          'skillCount' => (pack_meta['files'] || []).size,
          'files' => (pack_meta['files'] || []).map { |f| f['path'] }
        }

        File.write(manifest_path(name), JSON.pretty_generate(manifest))
      end

      def load_etags(name)
        path = etags_path(name)
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end

      def save_etags(name, etags)
        File.write(etags_path(name), JSON.pretty_generate(etags))
      end

      def pack_dir(name)
        File.join(skills_base_dir, name)
      end

      def manifest_path(name)
        File.join(pack_dir(name), MANIFEST_FILE)
      end

      def etags_path(name)
        File.join(pack_dir(name), '.etags.json')
      end

      def skills_base_dir
        if @global
          File.join(Config::Defaults::HOME_DIR, 'skills')
        else
          File.join(@project_root, '.rubyn-code', 'skills')
        end
      end
    end
  end
end
