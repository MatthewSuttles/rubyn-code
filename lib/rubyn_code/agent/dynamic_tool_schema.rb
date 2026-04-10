# frozen_string_literal: true

module RubynCode
  module Agent
    # Filters tool schemas sent to the LLM based on detected task context.
    # Instead of sending all 28+ tool schemas on every call, only include
    # tools relevant to the current task. This reduces per-turn system
    # prompt overhead by 30-50%.
    module DynamicToolSchema
      BASE_TOOLS = %w[
        read_file write_file edit_file glob grep bash
      ].freeze

      TASK_TOOLS = {
        testing: %w[run_specs].freeze,
        git: %w[git_status git_diff git_log git_commit].freeze,
        review: %w[review_pr git_diff].freeze,
        explore: %w[spawn_agent].freeze,
        web: %w[web_search web_fetch].freeze,
        memory: %w[memory_search memory_write].freeze,
        skills: %w[load_skill].freeze,
        tasks: %w[task].freeze,
        teams: %w[spawn_teammate send_message read_inbox].freeze,
        rails: %w[rails_generate db_migrate bundle_install bundle_add].freeze,
        background: %w[background_run].freeze,
        interaction: %w[ask_user compact].freeze
      }.freeze

      class << self
        # Returns tool names relevant to the detected task context.
        #
        # @param task_context [Symbol, nil] detected task type
        # @param discovered_tools [Set<String>] tools already discovered this session
        # @param codebase_index [RubynCode::Index::CodebaseIndex, nil] optional index for deeper context detection
        # @param message [String, nil] original user message for index-based matching
        # @return [Array<String>] tool names to include in the schema
        def active_tools(task_context: nil, discovered_tools: Set.new, codebase_index: nil, message: nil)
          tools = BASE_TOOLS.dup

          # Always include interaction tools
          tools.concat(TASK_TOOLS[:interaction])
          tools.concat(TASK_TOOLS[:memory])

          # Add task-specific tools
          if task_context
            context_tools = resolve_context_tools(task_context)
            tools.concat(context_tools)
          end

          # Add index-aware tools when a codebase index and message are available
          if codebase_index && message
            index_contexts = detect_index_contexts(message, codebase_index)
            index_contexts.each { |ctx| tools.concat(resolve_context_tools(ctx)) }
          end

          # Always include previously discovered tools
          tools.concat(discovered_tools.to_a)

          tools.uniq
        end

        # Detect task context from a user message.
        #
        # @param message [String]
        # @param codebase_index [RubynCode::Index::CodebaseIndex, nil] optional index for deeper detection
        # @return [Symbol, nil]
        def detect_context(message, codebase_index: nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- context detection dispatch
          msg = message.to_s.downcase
          return :testing if msg.match?(/\b(test|spec|rspec)\b/)
          return :git     if msg.match?(/\b(commit|push|diff|branch|merge|git)\b/)
          return :review  if msg.match?(/\b(review|pr|pull request)\b/)
          return :rails   if msg.match?(/\b(migrate|generate|scaffold|rails)\b/)
          return :web     if msg.match?(/\b(search|fetch|url|http|api)\b/)
          return :explore if msg.match?(/\b(explore|architecture|structure)\b/)
          return :teams   if msg.match?(/\b(team|spawn|message|inbox)\b/)

          # Fall back to index-based detection when keyword matching yields nothing
          return nil unless codebase_index

          index_contexts = detect_index_contexts(message, codebase_index)
          index_contexts.first
        end

        # Detect additional tool contexts based on codebase index content.
        #
        # @param message [String] user message
        # @param codebase_index [RubynCode::Index::CodebaseIndex] codebase index instance
        # @return [Array<Symbol>] detected context symbols
        def detect_index_contexts(message, codebase_index)
          contexts = []
          return contexts unless codebase_index

          contexts << :rails if message_mentions_model?(message, codebase_index)
          contexts << :testing if message_mentions_specced_file?(message, codebase_index)
          contexts.uniq
        rescue StandardError
          []
        end

        # Filter full tool definitions to only include active tools.
        #
        # @param all_definitions [Array<Hash>] full tool schema list
        # @param active_names [Array<String>] names of active tools
        # @return [Array<Hash>] filtered definitions
        def filter(all_definitions, active_names:)
          name_set = active_names.to_set
          all_definitions.select do |defn|
            name = defn[:name] || defn['name']
            name_set.include?(name)
          end
        end

        private

        def resolve_context_tools(context)
          case context
          when Symbol
            TASK_TOOLS.fetch(context, [])
          when Array
            context.flat_map { |c| TASK_TOOLS.fetch(c, []) }
          else
            []
          end
        end

        # Check if the user message mentions a model name from the index.
        def message_mentions_model?(message, codebase_index)
          model_names = codebase_index.nodes
                                      .select { |n| n['type'] == 'model' }
                                      .map { |n| n['name'] }
          return false if model_names.empty?

          msg_lower = message.to_s.downcase
          model_names.any? { |name| msg_lower.include?(name.downcase) }
        end

        # Check if the user message mentions a file that has specs in the index.
        def message_mentions_specced_file?(message, codebase_index)
          spec_edges = codebase_index.edges.select { |e| e['relationship'] == 'tests' }
          return false if spec_edges.empty?

          tested_files = spec_edges.map { |e| e['to'] }.compact
          msg_lower = message.to_s.downcase
          tested_files.any? do |file|
            basename = File.basename(file, '.rb')
            msg_lower.include?(basename)
          end
        end
      end
    end
  end
end
