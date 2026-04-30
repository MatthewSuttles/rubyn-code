# frozen_string_literal: true

require_relative 'gemfile_parser'
require_relative 'registry_client'
require_relative 'loader'
require_relative 'catalog'

module RubynCode
  module Skills
    # Builds additional skill context for PR reviews based on detected gems.
    #
    # On GitHub App runs (or any run where a Gemfile is present in the repo):
    # 1. Parse the Gemfile for gem names
    # 2. Fetch matching packs from the registry API
    # 3. Format pack skills into a context block for the review agent
    #
    # The GitHub App has access to ALL packs as a premium differentiator.
    # No local `/install-skills` required — everything is fetched transparently.
    #
    # Usage:
    #   context = PackContext.for_repo(
    #     project_root: '/path/to/repo',
    #     registry_url: 'https://rubyn.ai'
    #   )
    #   review_prompt = context.build_review_context(diff_content)
    class PackContext
      SKILL_NAME_OVERRIDES = {
        'stripe' => 'stripe/webhooks'
      }.freeze

      # Factory: build a PackContext for a given repo.
      #
      # @param project_root [String] path to the repository
      # @param registry_url [String, nil] override for registry URL
      # @return [PackContext] ready to build context
      def self.for_repo(project_root:, registry_url: nil)
        gemfile_path = File.join(project_root, 'Gemfile')
        content = File.read(gemfile_path, encoding: 'UTF-8') if File.exist?(gemfile_path)
        gems = content ? GemfileParser.gems(content) : []
        client = RegistryClient.new(base_url: registry_url)
        new(gems: gems, registry_client: client)
      end

      # Build context for an external/GitHub App context where we need to
      # fetch the full pack content (not just local skills).
      #
      # @param pack_names [Array<String>] names of packs to load
      # @return [String] context block to prepend to the review prompt
      def self.for_packs(pack_names:, registry_client:)
        new(gems: pack_names, registry_client: registry_client).build_context_block
      end

      attr_reader :gems

      def initialize(gems:, registry_client:)
        @gems = gems
        @registry_client = registry_client
        @cache = {}
      end

      # Returns the list of packs that matched detected gems.
      # Some gems map to pack names (e.g. stripe → stripe/webhooks).
      #
      # Tradeoff: every detected gem that doesn't appear in SKILL_NAME_OVERRIDES
      # is queried against the registry as a potential pack name. For a typical
      # Rails app with 40-80 gems this means up to 80 sequential registry calls,
      # each returning a 404 for unknown packs. This is intentional for now:
      #   - Responses are cached in @cache so repeated calls within a session are free
      #   - The GitHub App context is latency-tolerant (async review runs)
      #   - A future batch endpoint on the registry API can reduce this to one call
      # If latency becomes a problem, add a KNOWN_PACKS allowlist and skip gems
      # that are not in it before fetching.
      #
      # @return [Array<String>] pack names
      def matched_packs
        @matched_packs ||= gems.filter_map { |gem| pack_name_for(gem) }.uniq
      end

      # Fetch and cache pack content from registry.
      #
      # RegistryClient#fetch_pack returns a { data:, etag:, not_modified: } wrapper.
      # We cache and return only the :data payload so callers work with pack attributes
      # directly (e.g. :description, :files) rather than the transport envelope.
      #
      # @param pack_name [String]
      # @return [Hash, nil] pack data or nil if not found
      def fetch_pack(pack_name)
        return @cache[pack_name] if @cache.key?(pack_name)

        result = @registry_client.fetch_pack(pack_name)
        @cache[pack_name] = result[:data]
      rescue RegistryError
        @cache[pack_name] = nil
      end

      # Build a context block listing all detected packs and their skills.
      # This is prepended to the review prompt so the agent can apply them.
      #
      # @return [String] context block
      def build_context_block
        return '' if matched_packs.empty?

        lines = []
        lines << "\n## Pack-Informed Review Context"
        lines << 'The following skill packs were detected from the Gemfile and are ' \
               'available for this review (via GitHub App access):'
        lines << ''

        matched_packs.each do |pack_name|
          pack = fetch_pack(pack_name)
          if pack.nil?
            lines << "- **[#{pack_name}]** (pack not found in registry — skipped)"
            next
          end

          lines << "### Pack: #{pack_name}"
          lines << pack_description(pack)
          lines << pack_skills(pack)
          lines << ''
        rescue StandardError
          lines << "- **[#{pack_name}]** (failed to load — skipped)"
        end

        lines.join("\n")
      end

      private

      def pack_name_for(gem)
        SKILL_NAME_OVERRIDES[gem] || gem
      end

      def pack_description(pack)
        desc = pack[:description] || pack['description'] || ''
        desc.empty? ? '' : "#{desc}\n"
      end

      def pack_skills(pack)
        files = pack[:files] || pack['files'] || []
        return '' if files.empty?

        # RegistryClient#fetch_files_with_content returns an Array of
        # { filename: String, content: String } hashes — not a Hash keyed by name.
        skills = files.map do |file|
          filename = file[:filename] || file['filename'] || ''
          skill_name = File.basename(filename, '.*')
          skill_content = (file[:content] || file['content']).to_s
          format_skill_block(skill_name, skill_content)
        end
        skills.join("\n")
      end

      def format_skill_block(name, content)
        lines = []
        lines << "<skill name=\"#{name}\">"
        lines << content.strip
        lines << '</skill>'
        lines.join("\n")
      end
    end
  end
end
