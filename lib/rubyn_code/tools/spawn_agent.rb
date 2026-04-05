# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class SpawnAgent < Base
      TOOL_NAME = 'spawn_agent'
      DESCRIPTION = 'Spawn an isolated sub-agent to handle a task. The sub-agent gets its own ' \
                    "fresh context, works independently, and returns only a summary. Use 'explore' " \
                    "type for research/reading, 'worker' type for writing code/files. The sub-agent " \
                    'shares the filesystem but not your conversation.'
      PARAMETERS = {
        prompt: {
          type: :string,
          description: 'The task for the sub-agent to perform',
          required: true
        },
        agent_type: {
          type: :string,
          description: "Type of agent: 'explore' (read-only) or 'worker' (full write access). Default: explore",
          required: false,
          enum: %w[explore worker]
        }
      }.freeze
      RISK_LEVEL = :execute

      # These get injected by the executor or the REPL
      attr_writer :llm_client, :on_status

      def execute(prompt:, agent_type: 'explore')
        type = agent_type.to_sym
        callback = @on_status || method(:default_status)
        @tool_count = 0

        callback.call(:started, "Spawning #{type} agent...")

        tools = tools_for_type(type)
        result, hit_limit = run_sub_agent(
          prompt: prompt, tools: tools, type: type, callback: callback
        )

        callback.call(:done, "Agent finished (#{@tool_count} tool calls).")

        summary = RubynCode::SubAgents::Summarizer.call(result, max_length: 3000)
        format_agent_result(type, summary, hit_limit)
      end

      private

      def format_agent_result(type, summary, hit_limit)
        if hit_limit
          "## Sub-Agent Result (#{type}) — INCOMPLETE (reached #{@tool_count} tool calls)\n\n" \
            'The sub-agent ran out of turns before finishing. Here is what it accomplished so far:' \
            "\n\n#{summary}"
        else
          "## Sub-Agent Result (#{type})\n\n#{summary}"
        end
      end

      def max_iterations_for(type)
        if type == :explore
          Config::Defaults::MAX_EXPLORE_AGENT_ITERATIONS
        else
          Config::Defaults::MAX_SUB_AGENT_ITERATIONS
        end
      end

      # Returns [result_text, hit_limit] tuple
      def run_sub_agent(prompt:, tools:, type:, callback:)
        conversation = RubynCode::Agent::Conversation.new
        conversation.add_user_message(prompt)

        max_iterations = max_iterations_for(type)
        iteration = 0
        last_text = nil

        loop do
          return finish_at_limit(conversation, type, last_text) if iteration >= max_iterations

          last_text, done = process_iteration(
            conversation, tools, type, callback, last_text
          )
          return [last_text || '', false] if done

          iteration += 1
        end
      end

      def finish_at_limit(conversation, type, last_text)
        conversation.add_user_message(
          'You have reached your turn limit. Summarize everything you found or ' \
          'accomplished so far. Be thorough — this is your last chance to report back.'
        )
        response = @llm_client.chat(
          messages: conversation.to_api_format,
          tools: [],
          system: sub_agent_system_prompt(type)
        )
        summary = extract_text(response)
        [summary.empty? ? (last_text || '') : summary, true]
      end

      def process_iteration(conversation, tools, type, callback, last_text)
        response = @llm_client.chat(
          messages: conversation.to_api_format,
          tools: tools,
          system: sub_agent_system_prompt(type)
        )

        content = response_content(response)
        tool_calls = content.select { |b| block_type?(b, 'tool_use') }
        text_blocks = content.select { |b| block_type?(b, 'text') }
        last_text = text_blocks.map(&:text).join("\n") unless text_blocks.empty?

        conversation.add_assistant_message(content)
        return [last_text, true] if tool_calls.empty?

        execute_sub_agent_tools(tool_calls, conversation, type, callback)
        [last_text, false]
      end

      def execute_sub_agent_tools(tool_calls, conversation, type, callback)
        tool_calls.each do |tc|
          name, input, id = extract_tool_call(tc)
          @tool_count += 1
          callback.call(:tool, name.to_s)

          run_single_tool(name, input, id, conversation, type)
        end
      end

      def run_single_tool(name, input, id, conversation, type)
        if %w[spawn_agent].include?(name)
          conversation.add_tool_result(
            id, name, 'Error: Sub-agents cannot spawn other agents.', is_error: true
          )
          return
        end

        tool_class = RubynCode::Tools::Registry.get(name)
        if type == :explore && tool_class.risk_level != :read
          conversation.add_tool_result(
            id, name, 'Error: Explore agents can only use read-only tools.', is_error: true
          )
          return
        end

        tool = tool_class.new(project_root: project_root)
        result = tool.execute(**input.transform_keys(&:to_sym))
        conversation.add_tool_result(id, name, tool.truncate(result.to_s))
      rescue StandardError => e
        conversation.add_tool_result(id, name, "Error: #{e.message}", is_error: true)
      end

      def tools_for_type(type)
        all_tools = RubynCode::Tools::Registry.tool_definitions
        blocked = %w[spawn_agent send_message read_inbox compact memory_write]

        if type == :explore
          read_tools = %w[read_file glob grep bash load_skill memory_search]
          all_tools.select { |t| read_tools.include?(t[:name]) }
        else
          all_tools.reject { |t| blocked.include?(t[:name]) }
        end
      end

      def sub_agent_system_prompt(type)
        base = 'You are a Rubyn sub-agent. Complete your task efficiently and ' \
               'return a clear summary of what you found or did.'

        case type
        when :explore
          "#{base}\nYou have read-only access. Search, read files, and analyze. " \
          'Do NOT attempt to write or modify anything.'
        when :worker
          "#{base}\nYou have full read/write access. Make the changes needed, " \
          'run tests if appropriate, and report what you did.'
        else
          base
        end
      end

      def extract_text(response)
        content = response_content(response)
        text_blocks = content.select { |b| block_type?(b, 'text') }
        text_blocks.map(&:text).join("\n")
      end

      def response_content(response)
        response.respond_to?(:content) ? Array(response.content) : []
      end

      def block_type?(block, type)
        block.respond_to?(:type) && block.type == type
      end

      def extract_tool_call(tool_call)
        name = tool_call.respond_to?(:name) ? tool_call.name : tool_call[:name]
        input = tool_call.respond_to?(:input) ? tool_call.input : tool_call[:input]
        call_id = tool_call.respond_to?(:id) ? tool_call.id : tool_call[:id]
        [name, input, call_id]
      end

      def default_status(_type, message)
        RubynCode::Debug.agent("sub-agent: #{message}")
      end
    end

    Registry.register(SpawnAgent)
  end
end
