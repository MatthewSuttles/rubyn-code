# frozen_string_literal: true

module RubynCode
  module Learning
    # Uses learned instincts to skip redundant discovery steps. For example,
    # if we know the project uses FactoryBot, skip checking test_helper.rb
    # and looking for factories/ — just generate FactoryBot-style specs.
    class Shortcut
      SHORTCUT_RULES = {
        'uses_factory_bot' => {
          skip: %w[test_helper factories_check],
          apply: { spec_template: :factory_bot_rspec }
        },
        'uses_rspec' => {
          skip: %w[framework_detection],
          apply: { test_framework: :rspec }
        },
        'uses_minitest' => {
          skip: %w[framework_detection],
          apply: { test_framework: :minitest }
        },
        'uses_service_objects' => {
          skip: %w[pattern_detection],
          apply: { service_pattern: 'app/services/**/*_service.rb' }
        },
        'uses_devise' => {
          skip: %w[auth_detection],
          apply: { auth_framework: :devise }
        },
        'uses_grape' => {
          skip: %w[api_detection],
          apply: { api_framework: :grape }
        },
        'uses_sidekiq' => {
          skip: %w[job_detection],
          apply: { job_framework: :sidekiq }
        }
      }.freeze

      attr_reader :applied_shortcuts, :tokens_saved_estimate

      def initialize
        @applied_shortcuts = []
        @tokens_saved_estimate = 0
      end

      # Apply shortcuts based on instinct patterns.
      #
      # @param instinct_patterns [Array<String>] patterns from the instincts table
      # @return [Hash] aggregated settings from applied shortcuts
      def apply(instinct_patterns)
        settings = {}

        instinct_patterns.each do |pattern|
          rule_key = match_rule(pattern)
          next unless rule_key

          rule = SHORTCUT_RULES[rule_key]
          settings.merge!(rule[:apply])
          @applied_shortcuts << { rule: rule_key, skipped: rule[:skip] }
          @tokens_saved_estimate += rule[:skip].size * 500
        end

        settings
      end

      # Check if a discovery step should be skipped.
      #
      # @param step_name [String] the discovery step name
      # @return [Boolean]
      def skip?(step_name)
        @applied_shortcuts.any? { |s| s[:skipped].include?(step_name.to_s) }
      end

      # Returns stats about shortcuts applied this session.
      def stats
        {
          shortcuts_applied: @applied_shortcuts.size,
          steps_skipped: @applied_shortcuts.sum { |s| s[:skipped].size },
          tokens_saved_estimate: @tokens_saved_estimate
        }
      end

      private

      def match_rule(pattern)
        normalized = pattern.to_s.downcase
        SHORTCUT_RULES.each_key do |key|
          return key if normalized.include?(key.tr('_', ' ')) || normalized.include?(key)
        end
        nil
      end
    end
  end
end
