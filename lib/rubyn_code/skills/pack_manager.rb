# frozen_string_literal: true

require 'fileutils'
require 'json'

module RubynCode
  module Skills
    # Manages local installation and removal of skill packs.
    #
    # Installed packs live under ~/.rubyn-code/skill-packs/<pack-name>/.
    # A manifest.json in each pack directory records metadata for listing
    # and version tracking.
    class PackManager
      PACKS_DIR = File.join(Config::Defaults::HOME_DIR, 'skill-packs')
      MANIFEST_FILE = 'manifest.json'

      def initialize(packs_dir: PACKS_DIR)
        @packs_dir = packs_dir
      end

      # Install a pack from registry data.
      #
      # @param pack_data [Hash] from RegistryClient#fetch_pack
      #   Expected keys: :name, :description, :version, :files
      #   Each file: { filename: "name.md", content: "..." }
      # @return [Hash] installed pack metadata
      def install(pack_data)
        name = pack_data[:name] || pack_data['name']
        raise ArgumentError, 'Pack data must include a name' if name.nil? || name.empty?

        pack_dir = File.join(@packs_dir, name)
        FileUtils.mkdir_p(pack_dir)

        write_files(pack_dir, pack_data)
        write_manifest(pack_dir, pack_data)

        manifest(name)
      end

      # Remove an installed pack.
      #
      # @param name [String] pack name
      # @return [Boolean] true if removed, false if not found
      def remove(name)
        pack_dir = File.join(@packs_dir, name.to_s)
        return false unless File.directory?(pack_dir)

        FileUtils.rm_rf(pack_dir)
        true
      end

      # List all installed packs.
      #
      # @return [Array<Hash>] each with :name, :description, :version, :installed_at
      def installed
        return [] unless File.directory?(@packs_dir)

        Dir.children(@packs_dir)
           .select { |d| File.directory?(File.join(@packs_dir, d)) }
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
        dir = File.join(@packs_dir, name.to_s)
        File.directory?(dir) ? dir : nil
      end

      # Return all installed pack directories (for catalog integration).
      #
      # @return [Array<String>]
      def all_pack_dirs
        return [] unless File.directory?(@packs_dir)

        Dir.children(@packs_dir)
           .map { |d| File.join(@packs_dir, d) }
           .select { |d| File.directory?(d) }
      end

      private

      def manifest(name)
        path = File.join(@packs_dir, name.to_s, MANIFEST_FILE)
        return nil unless File.exist?(path)

        JSON.parse(File.read(path), symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      def write_files(pack_dir, pack_data)
        files = pack_data[:files] || pack_data['files'] || []
        files.each do |file|
          filename = file[:filename] || file['filename']
          content  = file[:content]  || file['content']
          next if filename.nil? || content.nil?

          # Prevent path traversal
          safe_name = File.basename(filename)
          File.write(File.join(pack_dir, safe_name), content)
        end
      end

      def write_manifest(pack_dir, pack_data)
        manifest = {
          name: pack_data[:name] || pack_data['name'],
          description: pack_data[:description] || pack_data['description'] || '',
          version: pack_data[:version] || pack_data['version'] || '1.0.0',
          installed_at: Time.now.iso8601,
          file_count: (pack_data[:files] || pack_data['files'] || []).size
        }

        File.write(
          File.join(pack_dir, MANIFEST_FILE),
          JSON.pretty_generate(manifest)
        )
      end
    end
  end
end
