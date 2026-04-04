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

        # Spawn a background thread running the teammate agent
        Thread.new do
          run_teammate_agent(teammate, prompt, mailbox, callback)
        end

        "Spawned teammate '#{name}' as #{role}. Initial task: #{prompt[0..100]}"
      end

      private

      def run_teammate_agent(teammate, initial_prompt, mailbox, callback)
        conversation = Agent::Conversation.new
        conversation.add_user_message(initial_prompt)

        system_prompt = "You are #{teammate.name}, a #{teammate.role} teammate agent. " \
                        'Complete tasks efficiently. Use tools when needed. ' \
                        'When done, provide a clear summary of what you accomplished.'

        tools = tools_for_teammate
        max_iterations = Config::Defaults::MAX_SUB_AGENT_ITERATIONS

        max_iterations.times do
          response = @llm_client.chat(
            messages: conversation.to_api_format,
            tools: tools,
            system: system_prompt
          )

          content = response.respond_to?(:content) ? Array(response.content) : []
          tool_calls = content.select { |b| b.respond_to?(:type) && b.type == 'tool_use' }

          if tool_calls.empty?
            text = content.select { |b| b.respond_to?(:type) && b.type == 'text' }
                          .map(&:text).join("\n")
            conversation.add_assistant_message(content)
            callback.call(:done, "Teammate '#{teammate.name}' finished initial task.")

            # Send result back to main agent inbox
            mailbox.send(from: teammate.name, to: 'rubyn', content: text)

            # Now loop waiting for new messages
            poll_inbox(teammate, conversation, tools, system_prompt, mailbox, callback)
            return
          end

          conversation.add_assistant_message(content)
          execute_tool_calls(tool_calls, conversation, callback)
        end

        callback.call(:done, "Teammate '#{teammate.name}' reached iteration limit.")
      rescue StandardError => e
        callback.call(:done, "Teammate '#{teammate.name}' error: #{e.message}")
        RubynCode::Debug.agent("Teammate #{teammate.name} error: #{e.class}: #{e.message}")
      end

      def poll_inbox(teammate, conversation, tools, system_prompt, mailbox, _callback)
        loop do
          sleep Config::Defaults::POLL_INTERVAL

          messages = mailbox.read_inbox(teammate.name)
          next if messages.empty?

          messages.each do |msg|
            conversation.add_user_message(msg[:content])

            response = @llm_client.chat(
              messages: conversation.to_api_format,
              tools: tools,
              system: system_prompt
            )

            content = response.respond_to?(:content) ? Array(response.content) : []
            conversation.add_assistant_message(content)

            text = content.select { |b| b.respond_to?(:type) && b.type == 'text' }
                          .map(&:text).join("\n")
            mailbox.send(from: teammate.name, to: msg[:from], content: text) unless text.empty?
          end
        end
      rescue StandardError => e
        RubynCode::Debug.agent("Teammate #{teammate.name} poll error: #{e.message}")
      end

      def execute_tool_calls(tool_calls, conversation, callback)
        tool_calls.each do |tc|
          name = tc.respond_to?(:name) ? tc.name : tc[:name]
          input = tc.respond_to?(:input) ? tc.input : tc[:input]
          id = tc.respond_to?(:id) ? tc.id : tc[:id]

          callback.call(:tool, "  [teammate] > #{name}")

          begin
            # Block recursive spawning
            if %w[spawn_agent spawn_teammate].include?(name)
              conversation.add_tool_result(id, name, 'Error: Teammates cannot spawn other agents.', is_error: true)
              next
            end

            tool_class = Registry.get(name)
            tool = tool_class.new(project_root: project_root)
            result = tool.execute(**input.transform_keys(&:to_sym))
            truncated = tool.truncate(result.to_s)
            conversation.add_tool_result(id, name, truncated)
          rescue StandardError => e
            conversation.add_tool_result(id, name, "Error: #{e.message}", is_error: true)
          end
        end
      end

      def tools_for_teammate
        all_tools = Registry.tool_definitions
        blocked = %w[spawn_agent spawn_teammate send_message read_inbox compact]
        all_tools.reject { |t| blocked.include?(t[:name]) }
      end

      def default_status(_type, message)
        RubynCode::Debug.agent("spawn_teammate: #{message}")
      end
    end

    Registry.register(SpawnTeammate)
  end
end
