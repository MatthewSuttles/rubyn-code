# frozen_string_literal: true

module RubynCode
  module CLI
    # Command registration and dispatch for the REPL.
    module ReplCommands # rubocop:disable Metrics/ModuleLength -- REPL command dispatch and teammate handling
      private

      def setup_command_registry!
        @command_registry = Commands::Registry.new
        register_all_commands!
        Commands::Help.registry = @command_registry
        @input_handler = InputHandler.new(command_registry: @command_registry)
      end

      def register_all_commands!
        [
          Commands::Help, Commands::Quit, Commands::Compact,
          Commands::Cost, Commands::Clear, Commands::Undo,
          Commands::Tasks, Commands::Budget, Commands::Skill,
          Commands::Version, Commands::Review, Commands::Resume,
          Commands::Spawn, Commands::Doctor, Commands::Tokens,
          Commands::Plan, Commands::ContextInfo, Commands::Diff,
          Commands::Model, Commands::NewSession, Commands::Mcp,
          Commands::Provider, Commands::InstallSkills,
          Commands::RemoveSkills, Commands::Skills,
          Commands::Megaplan, Commands::Goal, Commands::Loop,
          Commands::Agents, Commands::Learning, Commands::Rewind,
          Commands::Chisel, Commands::ChiselReview, Commands::ChiselAudit,
          Commands::ChiselDebt, Commands::ChiselGain, Commands::Think, Commands::Effort, Commands::Export
        ].each { |cmd| @command_registry.register(cmd) }
        register_custom_commands!
      end

      # Load user-defined slash commands from .rubyn-code/commands/*.md and
      # ~/.rubyn-code/commands/*.md. Built-in commands always win — a custom
      # file can't shadow /help, /quit, etc.
      def register_custom_commands!
        Commands::CustomLoader.load_all(project_root: @project_root).each do |cmd|
          next if @command_registry.known?(cmd.command_name)

          @command_registry.register(cmd)
        end
      rescue StandardError => e
        RubynCode::Debug.warn("Custom command load failed: #{e.message}")
      end

      def handle_command(command)
        case command.action
        when :quit            then @running = false
        when :message         then handle_message(command.args.first)
        when :empty           then nil
        when :list_commands   then display_commands
        when :unknown_command
          @renderer.warning("Unknown command: #{command.args.first}. Type / to see available commands.")
        when :slash_command then dispatch_slash_command(command.args[0], command.args[1..])
        end
      end

      def dispatch_slash_command(name, args)
        ctx = build_context
        result = @command_registry.dispatch(name, args, ctx)

        case result
        when :quit    then @running = false
        when :unknown then @renderer.warning("Unknown command: #{name}. Type / to see available commands.")
        when Hash     then handle_command_result(result)
        end
      end

      def build_context
        Commands::Context.new(
          renderer: @renderer,
          conversation: @conversation,
          agent_loop: @agent_loop,
          context_manager: @context_manager,
          budget_enforcer: @budget_enforcer,
          llm_client: @llm_client,
          db: @db,
          session_id: current_session_id,
          project_root: @project_root,
          skill_loader: @skill_loader,
          session_persistence: @session_persistence,
          background_worker: @background_worker,
          permission_tier: @permission_tier,
          plan_mode: @plan_mode,
          message_handler: method(:handle_message),
          hook_registry: @hook_registry,
          checkpoint_manager: @checkpoint_manager
        )
      end

      def handle_command_result(result)
        case result
        in { action: :set_budget, amount: Float => amount }
          apply_budget(amount)
        in { action: :set_plan_mode, enabled: true | false => enabled }
          apply_plan_mode(enabled)
        in { action: :set_session_id, session_id: String => sid }
          start_new_session(sid)
        in { action: :set_model, model: String => model }
          apply_model(model)
        in { action: :set_provider, provider: String => provider, **rest }
          apply_provider(provider, rest[:model])
        in { action: :spawn_teammate, name: String => name, role: String => role }
          spawn_teammate(name, role)
        in { action: :run_loop, interval:, max: Integer => max, payload: String => payload }
          run_loop(interval, max, payload)
        in { action: :rewound }
          save_session!
        else
          # Unknown result hash — ignore
        end
      end

      # Drive a /loop. Owned by the REPL so it runs on the main thread (Ctrl-C
      # stops it) and can re-dispatch slash-command payloads.
      def run_loop(interval, max, payload)
        announce_loop(interval, max)
        payload = decorate_self_paced(payload) unless interval
        @current_loop = CLI::LoopRunner.new(
          interval: interval, max_iterations: max,
          runner: ->(_i) { run_loop_payload(payload) },
          on_iteration: ->(n, total) { @renderer.system_message("🔁 loop #{n}/#{total}") }
        )
        completed = @current_loop.run
        @renderer.info("🔁 Loop finished after #{completed} iteration#{'s' unless completed == 1}.")
      rescue Interrupt
        @renderer.warning('Loop interrupted.')
      ensure
        @current_loop = nil
      end

      def announce_loop(interval, max)
        cadence = interval ? "every #{format_interval(interval)}" : 'self-paced'
        @renderer.info("🔁 Looping #{cadence} (up to #{max}×). Press Ctrl-C to stop.")
      end

      # Execute one iteration. Slash-command payloads are re-dispatched; plain
      # prompts go through the agent. Returns the agent's text so self-paced
      # loops can detect the LOOP_DONE sentinel.
      def run_loop_payload(payload)
        if payload.start_with?('/')
          name, *rest = payload.split
          dispatch_slash_command(name, rest)
          ''
        else
          handle_message(payload).to_s
        end
      end

      def decorate_self_paced(payload)
        return payload if payload.start_with?('/')

        "#{payload}\n\n(You are in a self-paced loop. Keep handling this " \
          'recurring task. When it no longer needs to run, end your reply ' \
          "with #{CLI::LoopRunner::DONE_SENTINEL}.)"
      end

      def format_interval(seconds)
        return "#{seconds / 3600}h" if (seconds % 3600).zero? && seconds >= 3600
        return "#{seconds / 60}m" if (seconds % 60).zero? && seconds >= 60

        "#{seconds}s"
      end

      def start_new_session(new_id)
        @session_id = new_id
        @skills_injected = false # re-inject skills on next message
        system('clear')
      end

      def apply_budget(amount)
        @budget_enforcer = Observability::BudgetEnforcer.new(
          @db, session_id: current_session_id, session_limit: amount
        )
      end

      def apply_plan_mode(enabled)
        @plan_mode = enabled
        @agent_loop.plan_mode = enabled if @agent_loop.respond_to?(:plan_mode=)
      end

      def apply_model(model)
        @llm_client.model = model
        @renderer.info("Model set to #{model}")
      end

      def apply_provider(provider, model)
        @llm_client.switch_provider!(provider, model: model)
        label = "Provider set to #{provider}"
        label += ", model: #{model}" if model
        @renderer.info(label)
      end

      def display_commands
        @renderer.info('Available commands:')
        @command_registry.visible_commands.each do |cmd_class|
          names = cmd_class.all_names.join(', ')
          puts "  #{names.ljust(25)} #{cmd_class.description}"
        end
        puts
      end

      def spawn_teammate(name, role)
        mailbox = Teams::Mailbox.new(@db)
        manager = Teams::Manager.new(@db, mailbox: mailbox)
        teammate = manager.spawn(name: name, role: role)

        Thread.new { run_teammate_loop(teammate, mailbox) }

        @renderer.info("Spawned teammate #{name} as #{role}")
      rescue StandardError => e
        @renderer.error("Failed to spawn teammate: #{e.message}")
      end

      def run_teammate_loop(teammate, mailbox)
        conversation = Agent::Conversation.new
        tool_executor = Tools::Executor.new(project_root: @project_root)
        tool_executor.llm_client = @llm_client

        loop do
          messages = mailbox.read_inbox(teammate.name)
          break if messages.empty?

          process_teammate_messages(teammate, mailbox, conversation, tool_executor, messages)
          sleep 5
        end
      rescue StandardError => e
        RubynCode::Debug.agent("Teammate #{teammate.name} error: #{e.message}")
      end

      def process_teammate_messages(teammate, mailbox, conversation, tool_executor, messages)
        messages.each do |msg|
          text = run_teammate_turn(teammate, conversation, tool_executor, msg[:content])
          mailbox.send(from: teammate.name, to: msg[:from], content: text)
        end
      end

      def run_teammate_turn(teammate, conversation, tool_executor, message_content)
        conversation.add_user_message(message_content)
        response = @llm_client.chat(
          messages: conversation.to_api_format,
          tools: tool_executor.tool_definitions,
          system: "You are #{teammate.name}, a #{teammate.role} teammate agent. Complete tasks sent to your inbox."
        )
        content = response.respond_to?(:content) ? Array(response.content) : []
        conversation.add_assistant_message(content)
        content.select { |b| b.respond_to?(:text) }.map(&:text).join("\n")
      end
    end
  end
end
