# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class SpawnTeammate < Base
      TOOL_NAME = 'spawn_teammate'
      DESCRIPTION = 'Spawn a persistent named teammate agent with a role and an initial task. ' \
                    'The teammate gets its own conversation, processes the initial prompt, and ' \
                    'remains available via the mailbox for further messages.'
      PARAMETERS = {
        name: {
          type: :string,
          description: 'Unique name for the teammate',
          required: true
        },
        role: {
          type: :string,
          description: "The teammate's role (e.g. 'coder', 'reviewer', 'tester')",
          required: true
        },
        prompt: {
          type: :string,
          description: 'Initial task or instruction for the teammate',
          required: true
        }
      }.freeze
      RISK_LEVEL = :execute

      attr_writer :llm_client, :on_status, :db

      def execute(name:, role:, prompt:)
        callback = @on_status || method(:default_status)

        raise Error, 'LLM client not available' unless @llm_client
        raise Error, 'Database not available' unless @db

        mailbox = Teams::Mailbox.new(@db)
        manager = Teams::Manager.new(@db, mailbox: mailbox)

        teammate = manager.spawn(name: name, role: role)
        callback.call(:started, "Spawning teammate '#{name}' as #{role}...")

        Thread.new do
          run_teammate_agent(teammate, prompt, mailbox, callback)
        end

        "Spawned teammate '#{name}' as #{role}. Initial task: #{prompt[0..100]}"
      end

      private

      def run_teammate_agent(teammate, initial_prompt, mailbox, callback)
        conversation = Agent::Conversation.new
        conversation.add_user_message(initial_prompt)

        system_prompt = build_system_prompt(teammate)
        tools = tools_for_teammate
        max_iterations = Config::Defaults::MAX_SUB_AGENT_ITERATIONS

        max_iterations.times do
          done = process_teammate_iteration(
            conversation, tools, system_prompt, teammate, mailbox, callback
          )
          return if done
        end

        callback.call(:done, "Teammate '#{teammate.name}' reached iteration limit.")
      rescue StandardError => e
        callback.call(:done, "Teammate '#{teammate.name}' error: #{e.message}")
        RubynCode::Debug.agent(
          "Teammate #{teammate.name} error: #{e.class}: #{e.message}"
        )
      end

      def build_system_prompt(teammate)
        "You are #{teammate.name}, a #{teammate.role} teammate agent. " \
          'Complete tasks efficiently. Use tools when needed. ' \
          'When done, provide a clear summary of what you accomplished.'
      end

      # rubocop:disable Metrics/ParameterLists
      def process_teammate_iteration(conversation, tools, system_prompt, teammate, mailbox, callback) # rubocop:disable Naming/PredicateMethod -- returns boolean but is an action method, not a predicate
        response = @llm_client.chat(
          messages: conversation.to_api_format,
          tools: tools,
          system: system_prompt
        )

        content = response_content(response)
        tool_calls = content.select { |b| block_type?(b, 'tool_use') }

        if tool_calls.empty?
          finish_teammate_task(content, conversation, teammate, mailbox, callback)
          poll_inbox(teammate, conversation, tools, system_prompt, mailbox)
          return true
        end

        conversation.add_assistant_message(content)
        execute_tool_calls(tool_calls, conversation, callback)
        false
      end
      # rubocop:enable Metrics/ParameterLists

      def finish_teammate_task(content, conversation, teammate, mailbox, callback)
        text = content.select { |b| block_type?(b, 'text') }
                      .map(&:text).join("\n")
        conversation.add_assistant_message(content)
        callback.call(:done, "Teammate '#{teammate.name}' finished initial task.")
        mailbox.send(from: teammate.name, to: 'rubyn', content: text)
      end

      def poll_inbox(teammate, conversation, tools, system_prompt, mailbox)
        loop do
          sleep Config::Defaults::POLL_INTERVAL

          messages = mailbox.read_inbox(teammate.name)
          next if messages.empty?

          messages.each do |msg|
            handle_inbox_message(
              msg, conversation, tools, system_prompt, teammate, mailbox
            )
          end
        end
      rescue StandardError => e
        RubynCode::Debug.agent(
          "Teammate #{teammate.name} poll error: #{e.message}"
        )
      end

      # rubocop:disable Metrics/ParameterLists
      def handle_inbox_message(msg, conversation, tools, system_prompt, teammate, mailbox)
        conversation.add_user_message(msg[:content])

        response = @llm_client.chat(
          messages: conversation.to_api_format,
          tools: tools,
          system: system_prompt
        )

        content = response_content(response)
        conversation.add_assistant_message(content)

        text = content.select { |b| block_type?(b, 'text') }
                      .map(&:text).join("\n")
        return if text.empty?

        mailbox.send(from: teammate.name, to: msg[:from], content: text)
      end
      # rubocop:enable Metrics/ParameterLists

      def execute_tool_calls(tool_calls, conversation, callback)
        tool_calls.each do |tc|
          name, input, id = extract_tool_call(tc)
          callback.call(:tool, "  [teammate] > #{name}")

          run_single_tool(name, input, id, conversation)
        end
      end

      def run_single_tool(name, input, id, conversation)
        if %w[spawn_agent spawn_teammate].include?(name)
          conversation.add_tool_result(
            id, name, 'Error: Teammates cannot spawn other agents.',
            is_error: true
          )
          return
        end

        tool_class = Registry.get(name)
        tool = tool_class.new(project_root: project_root)
        result = tool.execute(**input.transform_keys(&:to_sym))
        conversation.add_tool_result(id, name, tool.truncate(result.to_s))
      rescue StandardError => e
        conversation.add_tool_result(
          id, name, "Error: #{e.message}", is_error: true
        )
      end

      def tools_for_teammate
        all_tools = Registry.tool_definitions
        blocked = %w[spawn_agent spawn_teammate send_message read_inbox compact]
        all_tools.reject { |t| blocked.include?(t[:name]) }
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
        RubynCode::Debug.agent("spawn_teammate: #{message}")
      end
    end

    Registry.register(SpawnTeammate)
  end
end
