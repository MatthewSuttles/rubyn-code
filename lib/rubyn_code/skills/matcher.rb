# frozen_string_literal: true

require_relative 'gemfile_parser'

module RubynCode
  module Skills
    # Selects which skills to auto-load for a given user message.
    #
    # A skill is selected when:
    #   - its `triggers:` frontmatter list has at least one case-insensitive
    #     substring hit against the user message, AND
    #   - every gem in its `gems:` list is present in the project's Gemfile
    #     (skills with no `gems:` are unrestricted; if there is no Gemfile,
    #     gem gating is skipped entirely), AND
    #   - it has not already been selected by this matcher in the current
    #     session (per-instance dedup).
    #
    # Match scope is the latest user turn only. There is no cap on the
    # number of matches per turn.
    class Matcher
      def initialize(catalog:, project_root: nil)
        @catalog = catalog
        @project_root = project_root
        @loaded = Set.new
      end

      # Find skills whose triggers match `user_message`.
      #
      # @param user_message [String]
      # @return [Array<Hash>] catalog entries to load
      def match(user_message)
        text = user_message.to_s.downcase
        return [] if text.empty?

        available_gems_set = available_gems
        @catalog.available.filter_map do |entry|
          next unless eligible?(entry, text, available_gems_set)

          @loaded << entry[:name]
          entry
        end
      end

      # Names of skills selected so far in this session.
      def loaded
        @loaded.to_a
      end

      private

      def eligible?(entry, text, available_gems_set)
        return false if @loaded.include?(entry[:name])

        triggers = entry[:triggers]
        return false if triggers.nil? || triggers.empty?
        return false unless triggers_match?(triggers, text)

        gem_gate_pass?(entry[:gems], available_gems_set)
      end

      def triggers_match?(triggers, text)
        triggers.any? { |t| text.include?(t.to_s.downcase) }
      end

      # Pass when:
      #   - skill declares no gem dependencies, or
      #   - we can't read a Gemfile (no project root / no Gemfile / parse error),
      #     so we don't gate based on missing data, or
      #   - every required gem is in the Gemfile.
      def gem_gate_pass?(required_gems, available_gems_set)
        return true if required_gems.nil? || required_gems.empty?
        return true if available_gems_set.nil?

        required_gems.all? { |g| available_gems_set.include?(g.to_s.downcase) }
      end

      def available_gems
        return nil unless @project_root

        gemfile = File.join(@project_root, 'Gemfile')
        return nil unless File.exist?(gemfile)

        GemfileParser.gems(File.read(gemfile)).to_set
      rescue StandardError
        nil
      end
    end
  end
end
