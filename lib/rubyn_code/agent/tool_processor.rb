# frozen_string_literal: true

module RubynCode
  module Agent
    # Handles tool definition filtering, permission checks, and execution
    # for the agent loop.
    module ToolProcessor
      CORE_TOOLS = %w[read_file write_file edit_file glob grep bash spawn_agent background_run].freeze
      PLAN_MODE_RISK_LEVELS = %i[read].freeze

      private

      def tool_definitions
        all_tools = @tool_executor.tool_definitions
        return all_tools if all_tools.size <= CORE_TOOLS.size

        @discovered_tools ||= Set.new
        all_tools.select { |t| core_or_discovered?(t) }
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
        result = @tool_executor.execute(tool_name, symbolize_keys(tool_input))
        @hook_runner.fire(:post_tool_use, tool_name: tool_name, tool_input: tool_input, result: result)
        [result.to_s, false]
      rescue StandardError => e
        ["Error executing #{tool_name}: #{e.message}", true]
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
