# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class SpawnAgent < Base
      TOOL_NAME = "spawn_agent"
      DESCRIPTION = "Spawn an isolated sub-agent to handle a task. The sub-agent gets its own fresh context, " \
                    "works independently, and returns only a summary. Use 'explore' type for research/reading, " \
                    "'worker' type for writing code/files. The sub-agent shares the filesystem but not your conversation."
      PARAMETERS = {
        prompt: {
          type: :string,
          description: "The task for the sub-agent to perform",
          required: true
        },
        agent_type: {
          type: :string,
          description: "Type of agent: 'explore' (read-only tools) or 'worker' (full write access). Default: explore",
          required: false,
          enum: %w[explore worker]
        }
      }.freeze
      RISK_LEVEL = :execute

      # These get injected by the executor or the REPL
      attr_writer :llm_client, :on_status

      def execute(prompt:, agent_type: "explore")
        type = agent_type.to_sym
        callback = @on_status || method(:default_status)
        @tool_count = 0

        callback.call(:started, "Spawning #{type} agent...")

        tools = tools_for_type(type)

        result, hit_limit = run_sub_agent(prompt: prompt, tools: tools, type: type, callback: callback)

        callback.call(:done, "Agent finished (#{@tool_count} tool calls).")

        summary = RubynCode::SubAgents::Summarizer.call(result, max_length: 3000)

        if hit_limit
          "## Sub-Agent Result (#{type}) — INCOMPLETE (reached #{@tool_count} tool calls)\n\n" \
            "The sub-agent ran out of turns before finishing. Here is what it accomplished so far:\n\n#{summary}"
        else
          "## Sub-Agent Result (#{type})\n\n#{summary}"
        end
      end

      private

      # Returns [result_text, hit_limit] tuple
      def run_sub_agent(prompt:, tools:, type:, callback:)
        conversation = RubynCode::Agent::Conversation.new
        conversation.add_user_message(prompt)

        max_iterations = type == :explore ?
          Config::Defaults::MAX_EXPLORE_AGENT_ITERATIONS :
          Config::Defaults::MAX_SUB_AGENT_ITERATIONS
        iteration = 0
        last_text = nil

        loop do
          if iteration >= max_iterations
            # Ask the LLM for a final summary of what it accomplished so far
            conversation.add_user_message(
              "You have reached your turn limit. Summarize everything you found or accomplished so far. " \
              "Be thorough — this is your last chance to report back."
            )
            response = @llm_client.chat(
              messages: conversation.to_api_format,
              tools: [],
              system: sub_agent_system_prompt(type)
            )
            content = response.respond_to?(:content) ? Array(response.content) : []
            text_blocks = content.select { |b| b.respond_to?(:type) && b.type == "text" }
            summary = text_blocks.map(&:text).join("\n")

            return [summary.empty? ? (last_text || '') : summary, true]
          end

          response = @llm_client.chat(
            messages: conversation.to_api_format,
            tools: tools,
            system: sub_agent_system_prompt(type)
          )

          content = response.respond_to?(:content) ? Array(response.content) : []
          tool_calls = content.select { |b| b.respond_to?(:type) && b.type == "tool_use" }

          # Track the latest text output for partial results
          text_blocks = content.select { |b| b.respond_to?(:type) && b.type == "text" }
          last_text = text_blocks.map(&:text).join("\n") unless text_blocks.empty?

          if tool_calls.empty?
            conversation.add_assistant_message(content)
            return [last_text || '', false]
          end

          # Add assistant message with tool calls
          conversation.add_assistant_message(content)

          # Execute each tool call
          tool_calls.each do |tc|
            name = tc.respond_to?(:name) ? tc.name : tc[:name]
            input = tc.respond_to?(:input) ? tc.input : tc[:input]
            id = tc.respond_to?(:id) ? tc.id : tc[:id]

            @tool_count += 1
            callback.call(:tool, "#{name}")

            begin
              tool_class = RubynCode::Tools::Registry.get(name)

              # Block recursive spawning
              if %w[spawn_agent].include?(name)
                conversation.add_tool_result(id, name, "Error: Sub-agents cannot spawn other agents.", is_error: true)
                next
              end

              # Block write tools for explore agents
              if type == :explore && tool_class.risk_level != :read
                conversation.add_tool_result(id, name, "Error: Explore agents can only use read-only tools.", is_error: true)
                next
              end

              tool = tool_class.new(project_root: project_root)
              result = tool.execute(**input.transform_keys(&:to_sym))
              truncated = tool.truncate(result.to_s)

              conversation.add_tool_result(id, name, truncated)
            rescue StandardError => e
              conversation.add_tool_result(id, name, "Error: #{e.message}", is_error: true)
            end
          end

          iteration += 1
        end
      end

      def tools_for_type(type)
        all_tools = RubynCode::Tools::Registry.tool_definitions
        blocked = %w[spawn_agent send_message read_inbox compact memory_write]

        if type == :explore
          # Read-only tools
          read_tools = %w[read_file glob grep bash load_skill memory_search]
          all_tools.select { |t| read_tools.include?(t[:name]) }
        else
          # Worker gets everything except agent-spawning and team tools
          all_tools.reject { |t| blocked.include?(t[:name]) }
        end
      end

      def sub_agent_system_prompt(type)
        base = "You are a Rubyn sub-agent. Complete your task efficiently and return a clear summary of what you found or did."

        case type
        when :explore
          "#{base}\nYou have read-only access. Search, read files, and analyze. Do NOT attempt to write or modify anything."
        when :worker
          "#{base}\nYou have full read/write access. Make the changes needed, run tests if appropriate, and report what you did."
        else
          base
        end
      end

      def default_status(type, message)
        $stderr.puts "[sub-agent] #{message}" if ENV["RUBYN_DEBUG"]
      end
    end

    Registry.register(SpawnAgent)
  end
end
