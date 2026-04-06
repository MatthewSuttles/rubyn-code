# frozen_string_literal: true

module RubynCode
  module LLM
    # Routes tasks to appropriate model tiers based on complexity.
    # Cheap models handle file search and formatting; mid-tier handles
    # code generation; top-tier handles architecture and security.
    module ModelRouter
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

      # Model preferences per tier. Falls back to the configured default.
      TIER_MODELS = {
        cheap: %w[claude-haiku-4-5 gpt-4o-mini gpt-4.1-nano].freeze,
        mid: %w[claude-sonnet-4-20250514 gpt-4o gpt-4.1].freeze,
        top: %w[claude-opus-4-6 o3].freeze
      }.freeze

      class << self
        # Determine the appropriate model tier for a task.
        #
        # @param task_type [Symbol] the type of task
        # @return [Symbol] :cheap, :mid, or :top
        def tier_for(task_type)
          TASK_TIERS.each do |tier, tasks|
            return tier if tasks.include?(task_type.to_sym)
          end
          :mid # default to mid-tier for unknown tasks
        end

        # Get the best available model for a task type.
        #
        # @param task_type [Symbol] the type of task
        # @param available_models [Array<String>] models the user has configured
        # @return [String, nil] the model to use, or nil for default
        def model_for(task_type, available_models: [])
          tier = tier_for(task_type)
          preferred = TIER_MODELS[tier]

          # Return first available preferred model
          if available_models.any?
            preferred.each do |model|
              return model if available_models.any? { |m| m.start_with?(model) }
            end
          end

          # Return first preferred model (caller will validate availability)
          preferred.first
        end

        # Detect task type from a user message and recent tool calls.
        #
        # @param message [String] user input
        # @param recent_tools [Array<String>] recently used tool names
        # @return [Symbol] detected task type
        def detect_task(message, recent_tools: [])
          detect_from_message(message) || detect_from_tools(recent_tools) || :explore
        end

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

        # Returns cost estimate multiplier for a tier relative to top tier.
        def cost_multiplier(tier)
          COST_MULTIPLIERS.fetch(tier, DEFAULT_COST_MULTIPLIER)
        end

        private

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
