# frozen_string_literal: true

module RubynCode
  module Skills
    # Web fallback for trigger-based skill autoload.
    #
    # When the user message matches a skill pack in the registry that the
    # user hasn't installed locally, fetch the pack, install it under
    # ~/.rubyn-code/skill-packs/, refresh the loader's catalog, and let the
    # local matcher pick up the freshly-available skills.
    #
    # Pack-level matching (decided up front): substring-match the user
    # message against each pack's :name and :tags. Skill-level triggers
    # aren't in the registry catalog yet, so we pull packs at the coarser
    # grain and let the local matcher take over once files land on disk.
    #
    # Failure modes are silent: a registry error returns no matches so the
    # turn proceeds as if the web fallback weren't there.
    class RegistryAutoload
      # @param loader [Skills::Loader] supplies the live catalog to refresh after install
      # @param matcher [Skills::Matcher] re-run after install to extract real skill matches
      # @param registry_client [Skills::RegistryClient, nil] defaults to a new client
      # @param pack_manager [Skills::PackManager, nil] defaults to a new manager
      # @param on_fetching [Proc, nil] called as on_fetching.call(pack_name) before each fetch
      def initialize(loader:, matcher:, registry_client: nil, pack_manager: nil, on_fetching: nil)
        @loader = loader
        @matcher = matcher
        @client = registry_client || RegistryClient.new
        @pack_manager = pack_manager || PackManager.new
        @on_fetching = on_fetching || ->(_name) {}
        @attempted = Set.new
        @catalog_cache = nil
        @catalog_fetch_failed = false
      end

      # Attempt to install and match uninstalled packs whose name or tags
      # appear in the user message.
      #
      # @param user_input [String]
      # @return [Array<Hash>] catalog entries (from the local matcher) that
      #   became matchable after install. Empty if nothing fetched or the
      #   registry is unreachable.
      def try(user_input)
        text = user_input.to_s.downcase
        return [] if text.empty?

        candidates = uninstalled_packs_matching(text)
        return [] if candidates.empty?

        installed_any = candidates.any? { |pack| attempt_install(pack) }
        return [] unless installed_any

        @loader.catalog.refresh!
        @matcher.match(user_input)
      end

      private

      def uninstalled_packs_matching(text)
        packs = registry_catalog
        return [] if packs.nil?

        packs.select do |pack|
          name = pack_name(pack)
          next false if name.nil? || name.empty?
          next false if @pack_manager.installed?(name)
          next false if @attempted.include?(name)

          pack_matches?(pack, name, text)
        end
      end

      def pack_matches?(pack, name, text)
        return true if text.include?(name.downcase)

        Array(pack[:tags] || pack['tags']).any? do |tag|
          text.include?(tag.to_s.downcase)
        end
      end

      def attempt_install(pack)
        name = pack_name(pack)
        @attempted << name

        @on_fetching.call(name)
        result = @client.fetch_pack(name)
        @pack_manager.install(result[:data], etag: result[:etag])
        true
      rescue StandardError => e
        RubynCode::Debug.warn("Web autoload failed for '#{name}': #{e.message}")
        false
      end

      # Cache the registry catalog for the session. One failure flips
      # @catalog_fetch_failed so we don't hammer the registry on every turn.
      def registry_catalog
        return nil if @catalog_fetch_failed
        return @catalog_cache if @catalog_cache

        @catalog_cache = @client.fetch_catalog[:data] || []
      rescue StandardError => e
        RubynCode::Debug.warn("Web autoload registry fetch failed: #{e.message}")
        @catalog_fetch_failed = true
        nil
      end

      def pack_name(pack)
        (pack[:name] || pack['name']).to_s
      end
    end
  end
end
