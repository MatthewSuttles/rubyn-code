# frozen_string_literal: true

require 'reline'

module RubynCode
  module CLI
    class REPL
      def initialize(session_id: nil, project_root: Dir.pwd, yolo: false)
        @project_root = project_root
        @input_handler = InputHandler.new
        @renderer = Renderer.new
        @renderer.yolo = yolo
        @spinner = Spinner.new
        @running = true
        @session_id = session_id
        @permission_tier = yolo ? :unrestricted : :allow_read
        @plan_mode = false

        setup_components!
        setup_command_registry!
        setup_readline!
      end

      def run
        @version_check = VersionCheck.new(renderer: @renderer)
        @version_check.start

        @renderer.welcome
        @version_check.notify

        at_exit { shutdown! }

        @last_interrupt = nil

        while @running
          begin
            input = read_input
            break if input.nil?

            @last_interrupt = nil
            command = @input_handler.parse(input)
            handle_command(command)
          rescue Interrupt
            @spinner.stop
            now = Time.now.to_f
            if @last_interrupt && (now - @last_interrupt) < 2.0
              puts
              break
            end
            @last_interrupt = now
            puts
            @renderer.info('Press Ctrl-C again to exit, or type /quit')
          end
        end

        shutdown!
      end

      private

      # ── Component Setup ──────────────────────────────────────────────

      def setup_components!
        ensure_home_dir!
        @db = DB::Connection.instance
        DB::Migrator.new(@db).migrate!

        @auth = ensure_auth!
        @llm_client = LLM::Client.new
        @conversation = Agent::Conversation.new
        @tool_executor = Tools::Executor.new(project_root: @project_root)
        @context_manager = Context::Manager.new
        @hook_registry = Hooks::Registry.new
        @hook_runner = Hooks::Runner.new(registry: @hook_registry)
        @stall_detector = Agent::LoopDetector.new
        @deny_list = Permissions::DenyList.new
        @budget_enforcer = Observability::BudgetEnforcer.new(
          @db,
          session_id: current_session_id
        )
        @background_worker = Background::Worker.new(project_root: @project_root)
        @skill_loader = Skills::Loader.new(Skills::Catalog.new(skill_dirs))
        @session_persistence = Memory::SessionPersistence.new(@db)

        # Inject dependencies into executor for spawn_agent, spawn_teammate, and background_run
        @tool_executor.llm_client = @llm_client
        @tool_executor.background_worker = @background_worker
        @tool_executor.db = @db
        @tool_executor.ask_user_callback = ->(question) {
          @spinner.stop
          @renderer.warning("Rubyn is asking:")
          puts "  #{question}"
          print "  > "
          $stdout.flush
          answer = Reline.readline('', false)&.strip
          answer.nil? || answer.empty? ? '[no response]' : answer
        }
        @sub_agent_tool_count = 0
        @in_sub_agent = false
        @tool_executor.on_agent_status = lambda { |type, msg|
          case type
          when :started
            @spinner.stop
            @in_sub_agent = true
            @sub_agent_tool_count = 0
            @renderer.info(msg)
            @spinner.start_sub_agent
          when :tool
            @sub_agent_tool_count += 1
            @spinner.stop
            @spinner.start_sub_agent(@sub_agent_tool_count)
          when :done
            @spinner.stop
            @in_sub_agent = false
            @renderer.success(msg)
          end
        }

        Hooks::BuiltIn.register_all!(@hook_registry)
        Hooks::UserHooks.load!(@hook_registry, project_root: @project_root)

        @agent_loop = Agent::Loop.new(
          llm_client: @llm_client,
          tool_executor: @tool_executor,
          context_manager: @context_manager,
          hook_runner: @hook_runner,
          conversation: @conversation,
          permission_tier: @permission_tier,
          deny_list: @deny_list,
          budget_enforcer: @budget_enforcer,
          background_manager: @background_worker,
          stall_detector: @stall_detector,
          on_tool_call: lambda { |name, params|
            @spinner.stop
            unless @streaming_first_chunk
              @stream_formatter&.flush
              @stream_formatter = nil
              puts
              @streaming_first_chunk = true
            end
            @renderer.tool_call(name, params)
          },
          on_tool_result: lambda { |name, result, _is_error = false|
            @renderer.tool_result(name, result)
            @spinner.start
          },
          on_text: lambda { |text|
            @spinner.stop
            if @streaming_first_chunk
              @stream_formatter = StreamFormatter.new
              puts
              @streaming_first_chunk = false
            end
            @stream_formatter&.feed(text)
          },
          skill_loader: @skill_loader,
          project_root: @project_root
        )
      end

      # ── Command Registry ─────────────────────────────────────────────

      def setup_command_registry!
        @command_registry = Commands::Registry.new

        # Register all commands
        [
          Commands::Help,
          Commands::Quit,
          Commands::Compact,
          Commands::Cost,
          Commands::Clear,
          Commands::Undo,
          Commands::Tasks,
          Commands::Budget,
          Commands::Skill,
          Commands::Version,
          Commands::Review,
          Commands::Resume,
          Commands::Spawn,
          Commands::Doctor,
          Commands::Tokens,
          Commands::Plan,
          Commands::ContextInfo,
          Commands::Diff,
          Commands::Model
        ].each { |cmd| @command_registry.register(cmd) }

        # Give Help access to the registry for listing commands
        Commands::Help.registry = @command_registry

        # Update input handler to use registry for parsing
        @input_handler = InputHandler.new(command_registry: @command_registry)
      end

      # ── Command Dispatch ─────────────────────────────────────────────

      def handle_command(command)
        case command.action
        when :quit
          @running = false
        when :message
          handle_message(command.args.first)
        when :empty
          nil
        when :list_commands
          display_commands
        when :unknown_command
          @renderer.warning("Unknown command: #{command.args.first}. Type / to see available commands.")
        when :slash_command
          dispatch_slash_command(command.args[0], command.args[1..])
        end
      end

      def dispatch_slash_command(name, args)
        ctx = build_context
        result = @command_registry.dispatch(name, args, ctx)

        case result
        when :quit
          @running = false
        when :unknown
          @renderer.warning("Unknown command: #{name}. Type / to see available commands.")
        when Hash
          handle_command_result(result)
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
          message_handler: method(:handle_message)
        )
      end

      # Handle structured results from commands that need to mutate REPL state
      def handle_command_result(result)
        case result
        in { action: :set_budget, amount: Float => amount }
          @budget_enforcer = Observability::BudgetEnforcer.new(
            @db,
            session_id: current_session_id,
            session_limit: amount
          )
        in { action: :set_plan_mode, enabled: true | false => enabled }
          @plan_mode = enabled
          @agent_loop.plan_mode = enabled if @agent_loop.respond_to?(:plan_mode=)
        in { action: :set_session_id, session_id: String => sid }
          @session_id = sid
        in { action: :set_model, model: String => model }
          @llm_client.model = model if @llm_client.respond_to?(:model=)
          @renderer.info("Model set to #{model}")
        in { action: :spawn_teammate, name: String => name, role: String => role }
          spawn_teammate(name, role)
        else
          # Unknown result hash — ignore
        end
      end

      # ── Message Handling ─────────────────────────────────────────────

      def handle_message(input)
        @spinner.start
        @streaming_first_chunk = true

        response = @agent_loop.send_message(input)

        @spinner.stop
        if @streaming_first_chunk
          @renderer.display(response)
        else
          @stream_formatter&.flush
          @stream_formatter = nil
          puts
        end

        save_session!
      rescue BudgetExceededError => e
        @spinner.error
        @renderer.error("Budget exceeded: #{e.message}")
      rescue StandardError => e
        @spinner.error
        @renderer.error("Error: #{e.message}")
      end

      # ── Teammate Handling ────────────────────────────────────────────

      def spawn_teammate(name, role)
        mailbox = Teams::Mailbox.new(@db)
        manager = Teams::Manager.new(@db, mailbox: mailbox)
        teammate = manager.spawn(name: name, role: role)

        Thread.new do
          run_teammate_loop(teammate, mailbox)
        end

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

          messages.each do |msg|
            conversation.add_user_message(msg[:content])

            response = @llm_client.chat(
              messages: conversation.to_api_format,
              tools: tool_executor.tool_definitions,
              system: "You are #{teammate.name}, a #{teammate.role} teammate agent. Complete tasks sent to your inbox."
            )

            content = response.respond_to?(:content) ? Array(response.content) : []
            text = content.select { |b| b.respond_to?(:text) }.map(&:text).join("\n")
            conversation.add_assistant_message(content)

            mailbox.send(from: teammate.name, to: msg[:from], content: text)
          end

          sleep 5
        end
      rescue StandardError => e
        RubynCode::Debug.agent("Teammate #{teammate.name} error: #{e.message}")
      end

      # ── Display ──────────────────────────────────────────────────────

      def display_commands
        @renderer.info('Available commands:')
        @command_registry.visible_commands.each do |cmd_class|
          names = cmd_class.all_names.join(', ')
          puts "  #{names.ljust(25)} #{cmd_class.description}"
        end
        puts
      end

      # ── Readline ─────────────────────────────────────────────────────

      def setup_readline!
        completions = @command_registry.completions

        Reline.completion_proc = proc do |input|
          if input.start_with?('/')
            completions.select { |c| c.start_with?(input) }
          else
            []
          end
        end
        Reline.completion_append_character = ' '
      end

      def read_input
        lines = []
        prompt_str = lines.empty? ? @renderer.prompt : '  ... '

        loop do
          line = Reline.readline(prompt_str, true)
          return nil if line.nil?

          if @input_handler.multiline?(line)
            lines << @input_handler.strip_continuation(line)
            prompt_str = '  ... '
          else
            lines << line
            break
          end
        end

        lines.join("\n")
      end

      # ── Utilities ────────────────────────────────────────────────────

      def ensure_home_dir!
        dir = Config::Defaults::HOME_DIR
        FileUtils.mkdir_p(dir)
      end

      def ensure_auth!
        if Auth::TokenStore.valid?
          tokens = Auth::TokenStore.load
          source = tokens&.fetch(:source, :unknown)
          @renderer.info("Authenticated via #{source}") if source == :keychain
          return true
        end

        @renderer.error('No valid authentication found.')
        @renderer.info('Options:')
        @renderer.info('  1. Run Claude Code once to authenticate (Rubyn Code reads the keychain token)')
        @renderer.info('  2. Set ANTHROPIC_API_KEY environment variable')
        @renderer.info("  3. Run 'rubyn-code --auth' to enter an API key")
        exit(1)
      end

      def skill_dirs
        dirs = [File.expand_path('../../../skills', __dir__)]
        project_skills = File.join(@project_root, '.rubyn-code', 'skills')
        dirs << project_skills if Dir.exist?(project_skills)
        user_skills = File.join(Config::Defaults::HOME_DIR, 'skills')
        dirs << user_skills if Dir.exist?(user_skills)
        dirs
      end

      def current_session_id
        @current_session_id ||= SecureRandom.hex(16)
      end

      def save_session!
        @session_persistence.save_session(
          session_id: current_session_id,
          project_path: @project_root,
          messages: @conversation.messages,
          model: Config::Defaults::DEFAULT_MODEL
        )
      end

      def resume_session!
        data = @session_persistence.load_session(@session_id)
        return unless data

        @conversation.replace!(data[:messages])
        @renderer.info("Resumed session #{@session_id[0..7]}")
      end

      GOODBYE_MESSAGES = [
        'Freezing strings and saving memories... See ya! 💎',
        'Memoizing this session... Until next time! 🧠',
        'Committing learnings to memory... Later! 🤙',
        'Saving state, yielding control... Bye for now! 👋',
        'Session.save! && Rubyn.sleep... Catch you later! 😴',
        "GC.start on this session... Stay Ruby, friend! ✌\uFE0F",
        "Writing instincts to disk... Don't forget me! 💾",
        "at_exit { puts 'Thanks for coding with Rubyn!' } 🎸"
      ].freeze

      def shutdown!
        return if @shutdown_complete

        @shutdown_complete = true
        @spinner.stop
        puts
        @renderer.info(GOODBYE_MESSAGES.sample)

        @renderer.info('Saving session...')
        save_session!
        @background_worker&.shutdown!

        if @conversation.length > 5
          begin
            @renderer.info('Extracting learnings from this session...')
            Learning::Extractor.call(
              @conversation.messages,
              llm_client: @llm_client,
              project_path: @project_root
            )
            @renderer.success('Instincts saved.')
          rescue StandardError => e
            RubynCode::Debug.warn("Instinct extraction skipped: #{e.message}")
          end
        end

        begin
          db = DB::Connection.instance
          Learning::InstinctMethods.decay_all(db, project_path: @project_root)
        rescue StandardError
          # Silent — decay is best-effort
        end

        @renderer.info("Session saved. Rubyn out. ✌\uFE0F")
      rescue StandardError
        # Best effort on shutdown
      end
    end
  end
end
