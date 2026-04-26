# frozen_string_literal: true

module RubynCode
  module Agent
    # Handles tool definition filtering, permission checks, and execution
    # for the agent loop.
    module ToolProcessor # rubocop:disable Metrics/ModuleLength -- tool filtering + permissions + execution + decision signals
      CORE_TOOLS = %w[read_file write_file edit_file glob grep bash spawn_agent background_run].freeze
      PLAN_MODE_RISK_LEVELS = %i[read].freeze

      private

      def tool_definitions
        all_tools = @tool_executor.tool_definitions
        return all_tools if all_tools.size <= CORE_TOOLS.size

        @discovered_tools ||= Set.new

        # Use DynamicToolSchema to filter based on detected task context
        context = detect_task_context
        if context
          active = DynamicToolSchema.active_tools(task_context: context, discovered_tools: @discovered_tools)
          return DynamicToolSchema.filter(all_tools, active_names: active)
        end

        all_tools.select { |t| core_or_discovered?(t) }
      end

      # -- safe navigation chain
      def detect_task_context
        last_msg = @conversation&.messages&.reverse_each&.find { |m| m[:role] == 'user' } # rubocop:disable Style/SafeNavigationChainLength
        return nil unless last_msg

        text = last_msg[:content]
        return nil unless text.is_a?(String)

        DynamicToolSchema.detect_context(text)
      rescue StandardError
        nil
      end

      def core_or_discovered?(tool)
        name = tool[:name] || tool['name']
        CORE_TOOLS.include?(name) || @discovered_tools&.include?(name)
      end

      def discover_tool(name)
        (@discovered_tools ||= Set.new).add(name)
      end

      def read_only_tool_definitions
        Tools::Registry.all.select { |t| PLAN_MODE_RISK_LEVELS.include?(t::RISK_LEVEL) }.map(&:to_schema)
      end

      # -- tool dispatch with budget + signals
      def process_tool_calls(tool_calls)
        aggregate_chars = 0
        budget = Config::Defaults::MAX_MESSAGE_TOOL_RESULTS_CHARS

        tool_calls.each do |tool_call|
          result, is_error = run_single_tool(tool_call)
          aggregate_chars += result.to_s.length
          result = truncate_tool_result(result, aggregate_chars, budget)
          notify_tool_result(field(tool_call, :name), result, is_error)
          record_tool_result(tool_call, result, is_error)
        end
        @decision_compactor&.signal_edit_batch_complete!
      end

      def run_single_tool(tool_call)
        tool_name  = field(tool_call, :name)
        tool_input = field(tool_call, :input) || {}
        decision = Permissions::Policy.check(
          tool_name: tool_name, tool_input: tool_input, tier: @permission_tier, deny_list: @deny_list
        )
        @on_tool_call&.call(tool_name, tool_input) rescue nil # rubocop:disable Style/RescueModifier
        execute_with_permission(decision, tool_name, tool_input)
      end

      def truncate_tool_result(result, aggregate_chars, budget)
        return result unless aggregate_chars > budget

        remaining = [budget - (aggregate_chars - result.to_s.length), 500].max
        RubynCode::Debug.token("Tool result budget exceeded: #{aggregate_chars}/#{budget} chars")
        "#{result.to_s[0, remaining]}\n\n[truncated — tool result budget exceeded (#{budget} chars/message)]"
      end

      def notify_tool_result(tool_name, result, is_error)
        @on_tool_result&.call(tool_name, result, is_error) rescue nil # rubocop:disable Style/RescueModifier
      end

      def record_tool_result(tool_call, result, is_error)
        tool_name = field(tool_call, :name)
        @stall_detector.record(tool_name, field(tool_call, :input) || {})
        @conversation.add_tool_result(field(tool_call, :id), tool_name, result, is_error: is_error)
      end

      def execute_with_permission(decision, tool_name, tool_input)
        case decision
        when :deny  then ["Tool '#{tool_name}' is blocked by the deny list.", true]
        when :ask   then ask_and_execute(tool_name, tool_input)
        when :allow then execute_tool(tool_name, tool_input)
        else ["Unknown permission decision: #{decision}", true]
        end
      end

      def ask_and_execute(tool_name, tool_input)
        if prompt_user(tool_name,
                       tool_input)
          execute_tool(tool_name,
                       tool_input)
        else
          ["User denied permission for '#{tool_name}'.", true]
        end
      end

      def execute_tool(tool_name, tool_input)
        discover_tool(tool_name)
        @hook_runner.fire(:pre_tool_use, tool_name: tool_name, tool_input: tool_input)
        result = dispatch_tool(tool_name, tool_input)
        @hook_runner.fire(:post_tool_use, tool_name: tool_name, tool_input: tool_input, result: result)
        signal_decision_compactor(tool_name, tool_input, result)
        [result.to_s, false]
      rescue RubynCode::UserDeniedError => e
        # User refused this call via the IDE. Surface as is_error so the model
        # knows the tool did not run, not that it ran and returned text.
        [e.message, true]
      rescue StandardError => e
        ["Error executing #{tool_name}: #{e.message}", true]
      end

      # Run the tool through @tool_wrapper if one is configured (IDE mode),
      # otherwise call the executor directly. The wrapper receives the raw
      # tool name/input so it can emit protocol notifications and gate the
      # call; the block below is what actually performs the work.
      def dispatch_tool(tool_name, tool_input)
        if @tool_wrapper
          @tool_wrapper.call(tool_name, tool_input) do
            @tool_executor.execute(tool_name, symbolize_keys(tool_input))
          end
        else
          @tool_executor.execute(tool_name, symbolize_keys(tool_input))
        end
      end

      # -- tool dispatch
      def signal_decision_compactor(tool_name, tool_input, result)
        return unless @decision_compactor

        case tool_name
        when 'edit_file', 'write_file'
          path = tool_input[:path] || tool_input['path']
          @decision_compactor.signal_file_edited!(path) if path
        when 'run_specs'
          @decision_compactor.signal_specs_passed! if result.to_s.include?('0 failures')
        end
      rescue StandardError
        nil
      end

      def prompt_user(tool_name, tool_input)
        risk = resolve_tool_risk(tool_name)
        if risk == :destructive
          Permissions::Prompter.confirm_destructive(tool_name,
                                                    tool_input)
        else
          Permissions::Prompter.confirm(
            tool_name, tool_input
          )
        end
      end

      def resolve_tool_risk(tool_name)
        Tools::Registry.get(tool_name).risk_level
      rescue ToolNotFoundError
        :unknown
      end
    end
  end
end
