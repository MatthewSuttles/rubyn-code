# frozen_string_literal: true

module RubynCode
  module LLM
    # Routes tasks to appropriate model tiers based on complexity.
    # Integrates with the multi-provider adapter layer — resolves models
    # against configured providers and falls back to the active provider
    # when a preferred model isn't available.
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

      # Default model preferences per tier. Each entry is [provider, model].
      # Uses stable model IDs (no date suffixes) so they resolve to the latest
      # version via prefix matching in CostCalculator and the provider API.
      TIER_DEFAULTS = {
        cheap: [
          %w[anthropic claude-haiku-4-5],
          %w[openai gpt-4o-mini],
          %w[openai gpt-4.1-nano]
        ].freeze,
        mid: [
          %w[anthropic claude-sonnet-4-6],
          %w[openai gpt-4o],
          %w[openai gpt-4.1]
        ].freeze,
        top: [
          %w[anthropic claude-opus-4-6],
          %w[openai o3]
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
        #
        # @param task_type [Symbol] the type of task
        # @return [Symbol] :cheap, :mid, or :top
        def tier_for(task_type)
          TASK_TIERS.each do |tier, tasks|
            return tier if tasks.include?(task_type.to_sym)
          end
          :mid
        end

        # Resolve the best [provider, model] pair for a task type,
        # checking which providers are actually configured.
        #
        # @param task_type [Symbol] the type of task
        # @param client [LLM::Client, nil] the active LLM client (for provider checks)
        # @return [Hash] { provider:, model: } or nil to use current
        def resolve(task_type, client: nil)
          tier = tier_for(task_type)
          defaults = TIER_DEFAULTS[tier]

          if client
            defaults.each do |provider, model|
              return { provider: provider, model: model } if provider_available?(provider)
            end
          end

          first = defaults.first
          { provider: first[0], model: first[1] }
        end

        # Returns just the model name for a task type.
        # Backward-compatible — does not require a client.
        #
        # @param task_type [Symbol]
        # @param available_models [Array<String>] models the user has access to
        # @return [String] the model identifier
        def model_for(task_type, available_models: [])
          tier = tier_for(task_type)
          defaults = TIER_DEFAULTS[tier]

          if available_models.any?
            defaults.each do |pair|
              model = pair[1]
              return model if available_models.any? { |m| m.start_with?(model) }
            end
          end

          defaults.first[1]
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

        # Check if a provider is available (built-in or user-configured).
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
