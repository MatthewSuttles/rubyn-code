# frozen_string_literal: true

require 'json'

module RubynCode
  module Skills
    # Suggests skill packs based on gems detected in the project's Gemfile.
    #
    # On session start, parses the Gemfile, queries the registry for matching
    # packs, and shows a one-time suggestion. Tracks shown suggestions in
    # `.rubyn-code/suggested.json` to avoid repeating.
    class AutoSuggest
      SUGGESTED_FILE = 'suggested.json'

      # @param project_root [String]
      # @param registry_client [RegistryClient]
      def initialize(project_root:, registry_client: nil)
        @project_root = project_root
        @client = registry_client || RegistryClient.new
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

        content = File.read(gemfile_path)
        content.scan(/^\s*gem\s+['"]([^'"]+)['"]/).flatten.uniq
      rescue StandardError
        []
      end

      def fetch_suggestions(gems)
        @client.fetch_suggestions(gems)
      rescue RegistryError
        []
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
