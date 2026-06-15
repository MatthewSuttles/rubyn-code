# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'gemfile_parser'

module RubynCode
  module Skills
    # Suggests skill packs based on gems detected in the project's Gemfile.
    #
    # On session start, parses the Gemfile, queries the registry for matching
    # packs, and shows a one-time suggestion. Tracks shown suggestions in
    # `.rubyn-code/suggested.json` to avoid repeating.
    #
    # The registry lookup runs in a background thread (see #start) and
    # responses are cached in `.rubyn-code/suggestions_cache.json` keyed by
    # the Gemfile's gem list, so session start never blocks on the network.
    class AutoSuggest
      SUGGESTED_FILE = 'suggested.json'
      CACHE_FILE = 'suggestions_cache.json'
      CACHE_TTL = 86_400 # 24 hours
      FETCH_TIMEOUT = 3

      # @param project_root [String]
      # @param registry_client [RegistryClient]
      def initialize(project_root:, registry_client: nil)
        @project_root = project_root
        @client = registry_client || RegistryClient.new(timeout: FETCH_TIMEOUT)
        @thread = nil
      end

      # Kicks off the suggestion check in a background thread.
      # Call `pending_message` later to collect the result without blocking.
      def start
        @thread = Thread.new { @message = check }
        @thread.abort_on_exception = false
      end

      # Non-blocking: returns the suggestion message once the background
      # check has finished, nil while it's still running or after the
      # message has already been consumed.
      #
      # @return [String, nil]
      def pending_message
        return nil unless @thread
        return nil if @thread.alive?

        message = @message
        @message = nil
        message
      end

      # Check for suggestable packs and return a display message if any.
      # Returns nil if no suggestions or if all have been shown/dismissed.
      #
      # This method never raises — registry failures are silently swallowed
      # to avoid blocking session start.
      #
      # @return [String, nil] suggestion message or nil
      def check
        gems = parse_gemfile
        return nil if gems.empty?

        suggestions = fetch_suggestions(gems)
        return nil if suggestions.empty?

        new_suggestions = filter_shown(suggestions)
        return nil if new_suggestions.empty?

        record_shown(new_suggestions)
        format_message(new_suggestions)
      rescue StandardError
        nil
      end

      # Mark a pack as installed so it won't be suggested again.
      #
      # @param name [String] pack name
      def mark_installed(name)
        state = load_state
        state['installed'] ||= []
        state['installed'] << name unless state['installed'].include?(name)
        save_state(state)
      end

      # Mark a suggestion as dismissed.
      #
      # @param name [String] pack name
      def mark_dismissed(name)
        state = load_state
        state['dismissed'] ||= []
        state['dismissed'] << name unless state['dismissed'].include?(name)
        save_state(state)
      end

      private

      def parse_gemfile
        gemfile_path = File.join(@project_root, 'Gemfile')
        return [] unless File.exist?(gemfile_path)

        GemfileParser.gems(File.read(gemfile_path))
      rescue StandardError
        []
      end

      def fetch_suggestions(gems)
        cached = read_suggestions_cache(gems)
        return cached if cached

        suggestions = @client.fetch_suggestions(gems)
        write_suggestions_cache(gems, suggestions)
        suggestions
      rescue RegistryError
        []
      end

      def read_suggestions_cache(gems)
        path = cache_path
        return nil unless File.exist?(path)

        data = JSON.parse(File.read(path))
        return nil unless data['gemfile_hash'] == gemfile_hash(gems)
        return nil if (Time.now.to_i - data['fetched_at'].to_i) > CACHE_TTL

        suggestions = data['suggestions']
        suggestions.is_a?(Array) ? suggestions : nil
      rescue StandardError
        nil
      end

      def write_suggestions_cache(gems, suggestions)
        FileUtils.mkdir_p(File.dirname(cache_path))
        File.write(cache_path, JSON.pretty_generate(
                                 'gemfile_hash' => gemfile_hash(gems),
                                 'fetched_at' => Time.now.to_i,
                                 'suggestions' => suggestions
                               ))
      rescue StandardError
        # Best effort — caching failures must never break suggestions
      end

      def gemfile_hash(gems)
        Digest::SHA256.hexdigest(gems.sort.join(','))
      end

      def cache_path
        File.join(@project_root, '.rubyn-code', CACHE_FILE)
      end

      def filter_shown(suggestions)
        state = load_state
        shown = Array(state['shown'])
        installed = Array(state['installed'])
        dismissed = Array(state['dismissed'])
        skip = (shown + installed + dismissed).uniq

        suggestions.reject { |s| skip.include?(s['name']) }
      end

      def record_shown(suggestions)
        state = load_state
        state['shown'] ||= []
        suggestions.each do |s|
          state['shown'] << s['name'] unless state['shown'].include?(s['name'])
        end
        save_state(state)
      end

      def format_message(suggestions)
        gem_names = suggestions.map { |s| s['name'] }.join(', ')
        details = suggestions.map { |s| "#{s['name']} (#{s['reason']})" }.join(', ')
        install_cmd = "/install-skills #{suggestions.map { |s| s['name'] }.join(' ')}"

        "Skill packs available: #{details}\n" \
          "Run #{install_cmd} to install."
      end

      def load_state
        path = state_path
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end

      def save_state(state)
        dir = File.dirname(state_path)
        FileUtils.mkdir_p(dir)
        File.write(state_path, JSON.pretty_generate(state))
      end

      def state_path
        File.join(@project_root, '.rubyn-code', SUGGESTED_FILE)
      end
    end
  end
end
