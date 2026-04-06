# frozen_string_literal: true

module RubynCode
  module LLM
    # Routes tasks to appropriate model tiers based on complexity.
    # Integrates with the multi-provider adapter layer and reads
    # per-provider model tier overrides from config.yml.
    #
    # Users can configure tier models per provider in config.yml:
    #
    #   providers:
    #     anthropic:
    #       env_key: ANTHROPIC_API_KEY
    #       models:
    #         cheap: claude-haiku-4-5
    #         mid: claude-sonnet-4-6
    #         top: claude-opus-4-6
    #     openai:
    #       env_key: OPENAI_API_KEY
    #       models:
    #         cheap: gpt-5.4-nano
    #         mid: gpt-5.4-mini
    #         top: gpt-5.4
    #
    module ModelRouter # rubocop:disable Metrics/ModuleLength -- tier routing with provider integration
      TASK_TIERS = {
        cheap: %i[
          file_search spec_summary schema_lookup format_code
          git_operations memory_retrieval context_summary
        ].freeze,
        mid: %i[
          generate_specs simple_refactor code_review
          documentation bug_fix explore
        ].freeze,
        top: %i[
          architecture complex_refactor security_review
          performance planning
        ].freeze
      }.freeze

      # Hardcoded fallbacks when no config override exists.
      TIER_DEFAULTS = {
        cheap: [
          %w[anthropic claude-haiku-4-5],
          %w[openai gpt-5.4-nano]
        ].freeze,
        mid: [
          %w[anthropic claude-sonnet-4-6],
          %w[openai gpt-5.4-mini]
        ].freeze,
        top: [
          %w[anthropic claude-opus-4-6],
          %w[openai gpt-5.4]
        ].freeze
      }.freeze

      COST_MULTIPLIERS = { cheap: 0.07, mid: 0.20, top: 1.0 }.freeze
      DEFAULT_COST_MULTIPLIER = 0.20
      MESSAGE_PATTERNS = [
        [/\b(architect|design|restructure|multi.?file)\b/, :architecture],
        [/\b(security|vulnerab|audit|owasp)\b/,           :security_review],
        [/\b(n\+1|performance|slow|optimize|query)\b/,    :performance],
        [/\b(spec|test|rspec)\b/,                         :generate_specs],
        [/\b(fix|bug|error|broken)\b/,                    :bug_fix],
        [/\b(refactor|extract|rename|move)\b/,            :simple_refactor],
        [/\b(find|where|search|locate)\b/,                :file_search],
        [/\b(doc|readme|comment|explain)\b/,              :documentation]
      ].freeze

      class << self
        # Determine the appropriate model tier for a task.
        def tier_for(task_type)
          TASK_TIERS.each do |tier, tasks|
            return tier if tasks.include?(task_type.to_sym)
          end
          :mid
        end

        # Resolve the best [provider, model] pair for a task type.
        # Checks per-provider config overrides first, then falls back
        # to TIER_DEFAULTS.
        #
        # @param task_type [Symbol]
        # @param client [LLM::Client, nil] active client (for provider checks)
        # @return [Hash] { provider:, model: }
        def resolve(task_type, client: nil)
          tier = tier_for(task_type)

          # 1. Check config overrides for each available provider
          configured = config_tier_models(tier)
          configured.each do |provider, model|
            return { provider: provider, model: model } if client.nil? || provider_available?(provider)
          end

          # 2. Fall back to hardcoded defaults
          TIER_DEFAULTS[tier].each do |provider, model|
            return { provider: provider, model: model } if client.nil? || provider_available?(provider)
          end

          # 3. Last resort: first default
          first = TIER_DEFAULTS[tier].first
          { provider: first[0], model: first[1] }
        end

        # Returns just the model name for a task type (backward-compatible).
        def model_for(task_type, available_models: []) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- config + defaults search
          tier = tier_for(task_type)

          # Check config overrides first
          configured = config_tier_models(tier)
          if available_models.any? && configured.any?
            configured.each do |pair|
              model = pair[1]
              return model if available_models.any? { |m| m.start_with?(model) }
            end
          end

          # Then check hardcoded defaults
          defaults = TIER_DEFAULTS[tier]
          if available_models.any?
            defaults.each do |pair|
              model = pair[1]
              return model if available_models.any? { |m| m.start_with?(model) }
            end
          end

          # Fall back to first configured or first default
          configured.any? ? configured.first[1] : defaults.first[1]
        end

        # Detect task type from a user message and recent tool calls.
        def detect_task(message, recent_tools: [])
          detect_from_message(message) || detect_from_tools(recent_tools) || :explore
        end

        # Returns cost estimate multiplier for a tier relative to top tier.
        def cost_multiplier(tier)
          COST_MULTIPLIERS.fetch(tier, DEFAULT_COST_MULTIPLIER)
        end

        private

        # Read per-provider model tier overrides from config.yml.
        # Returns array of [provider, model] pairs for the given tier.
        # -- config traversal
        def config_tier_models(tier)
          settings = Config::Settings.new
          providers = settings.to_h['providers']
          return [] unless providers.is_a?(Hash)

          tier_key = tier.to_s
          results = []

          providers.each do |provider_name, cfg|
            next unless cfg.is_a?(Hash)

            models = cfg['models']
            next unless models.is_a?(Hash) && models[tier_key]

            results << [provider_name, models[tier_key]]
          end

          results
        rescue StandardError
          []
        end

        def provider_available?(provider)
          return true if %w[anthropic openai].include?(provider)

          settings = Config::Settings.new
          !settings.provider_config(provider).nil?
        rescue StandardError
          false
        end

        def detect_from_message(message)
          msg = message.to_s.downcase
          MESSAGE_PATTERNS.each do |pattern, task_type|
            return task_type if msg.match?(pattern)
          end
          nil
        end

        def detect_from_tools(recent_tools)
          return nil if recent_tools.empty?

          last = recent_tools.last.to_s
          case last
          when 'grep', 'glob' then :file_search
          when 'run_specs'           then :generate_specs
          when 'review_pr'           then :code_review
          when 'git_status', 'git_log', 'git_diff', 'git_commit' then :git_operations
          end
        end
      end
    end
  end
end
