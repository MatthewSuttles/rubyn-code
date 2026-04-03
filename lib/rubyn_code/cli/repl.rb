# frozen_string_literal: true

require "readline"

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

        setup_readline!
        setup_components!
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
            @renderer.info("Press Ctrl-C again to exit, or type /quit")
          end
        end

        shutdown!
      end

      private

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
        @sub_agent_tool_count = 0
        @in_sub_agent = false
        @tool_executor.on_agent_status = ->(type, msg) {
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
          on_tool_call: ->(name, params) {
            @spinner.stop
            unless @streaming_first_chunk
              @stream_formatter&.flush
              @stream_formatter = nil
              puts
              @streaming_first_chunk = true
            end
            @renderer.tool_call(name, params)
          },
          on_tool_result: ->(name, result, is_error) {
            unless @in_sub_agent
              @renderer.tool_result(name, result)
            end
            @streaming_first_chunk = true
            @spinner.start unless @in_sub_agent
          },
          on_text: ->(text) {
            if @streaming_first_chunk
              @spinner.stop
              @streaming_first_chunk = false
              @stream_formatter ||= StreamFormatter.new(@renderer)
            end
            @spinner.stop if @spinner.spinning?
            @stream_formatter.feed(text)
          },
          skill_loader: @skill_loader,
          project_root: @project_root
        )

        resume_session! if @session_id
      end

      def handle_command(command)
        case command.action
        when :quit
          @running = false
        when :message
          handle_message(command.args.first)
        when :compact
          handle_compact(command.args.first)
        when :cost
          handle_cost
        when :clear
          system("clear")
        when :undo
          @conversation.undo_last!
          @renderer.info("Last exchange removed.")
        when :help
          display_help
        when :tasks
          handle_tasks
        when :budget
          handle_budget(command.args.first)
        when :skill
          handle_skill(command.args.first)
        when :version
          @renderer.info("Rubyn Code v#{RubynCode::VERSION}")
        when :review
          handle_review(command.args)
        when :spawn_teammate
          handle_spawn_teammate(command.args)
        when :resume
          handle_resume(command.args.first)
        when :empty
          nil
        when :list_commands
          display_commands
        when :unknown_command
          @renderer.warning("Unknown command: #{command.args.first}. Type / to see available commands.")
        end
      end

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

      def handle_compact(focus = nil)
        @spinner.start("Compacting context...")
        compactor = Context::Compactor.new(llm_client: @llm_client)
        new_messages = compactor.manual_compact!(@conversation.messages, focus: focus)
        @conversation.replace!(new_messages)
        @spinner.success
        @renderer.info("Context compacted. #{@conversation.length} messages remaining.")
      end

      def handle_cost
        @renderer.cost_summary(
          session_cost: @budget_enforcer.session_cost,
          daily_cost: @budget_enforcer.daily_cost,
          tokens: {
            input: @context_manager.total_input_tokens,
            output: @context_manager.total_output_tokens
          }
        )
      end

      def handle_tasks
        task_manager = Tasks::Manager.new(@db)
        tasks = task_manager.list
        if tasks.empty?
          @renderer.info("No tasks.")
        else
          tasks.each do |t|
            status_color = case t[:status]
                           when "completed" then :green
                           when "in_progress" then :yellow
                           when "blocked" then :red
                           else :white
                           end
            puts "  [#{t[:status]}] #{t[:title]} (#{t[:id][0..7]})"
          end
        end
      end

      def handle_budget(amount)
        if amount
          @budget_enforcer = Observability::BudgetEnforcer.new(
            @db,
            session_id: current_session_id,
            session_limit: amount.to_f
          )
          @renderer.info("Session budget set to $#{amount}")
        else
          @renderer.info("Remaining budget: $#{'%.4f' % @budget_enforcer.remaining_budget}")
        end
      end

      def handle_skill(name)
        if name
          content = @skill_loader.load(name)
          @renderer.info("Loaded skill: #{name}")
          @conversation.add_user_message("<skill>#{content}</skill>")
        else
          @renderer.info("Available skills:")
          puts @skill_loader.descriptions_for_prompt
        end
      end

      def handle_resume(session_id)
        if session_id
          data = @session_persistence.load_session(session_id)
          if data
            @conversation.replace!(data[:messages])
            @session_id = session_id
            @renderer.info("Resumed session #{session_id[0..7]}")
          else
            @renderer.error("Session not found: #{session_id}")
          end
        else
          sessions = @session_persistence.list_sessions(project_path: @project_root, limit: 10)
          if sessions.empty?
            @renderer.info("No previous sessions.")
          else
            sessions.each do |s|
              puts "  #{s[:id][0..7]} | #{s[:title] || 'untitled'} | #{s[:created_at]}"
            end
          end
        end
      end

      def handle_review(args)
        base = args[0] || "main"
        focus = args[1] || "all"
        handle_message("Use the review_pr tool to review my current branch against #{base}. Focus: #{focus}. Load relevant best practice skills for any issues you find.")
      end

      def handle_spawn_teammate(args)
        name = args[0]
        unless name
          @renderer.error("Usage: /spawn <name> [role]")
          return
        end

        role = args[1] || "coder"

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
        $stderr.puts "[Teammate #{teammate.name}] Error: #{e.message}" if ENV["RUBYN_DEBUG"]
      end

      def display_commands
        @renderer.info("Available commands:")
        CLI::InputHandler::SLASH_COMMANDS.each do |cmd, action|
          puts "  #{cmd.ljust(15)} #{action}"
        end
        puts ""
      end

      def display_help
        puts <<~HELP
          Commands:
            /help          Show this help message
            /quit          Exit Rubyn Code
            /compact       Compress conversation context
            /cost          Show token usage and costs
            /clear         Clear the terminal
            /undo          Remove last exchange
            /tasks         List all tasks
            /budget [amt]  Show or set session budget
            /skill [name]  Load a skill or list available skills
            /resume [id]   Resume a session or list recent sessions
            /version       Show version

          Tips:
            - Use @filename to include file contents in your message
            - End a line with \\ for multiline input
        HELP
      end

      def setup_readline!
        slash_commands = CLI::InputHandler::SLASH_COMMANDS.keys

        Readline.completion_proc = proc do |input|
          if input.start_with?("/")
            slash_commands.select { |c| c.start_with?(input) }
          else
            []
          end
        end
        Readline.completion_append_character = " "
      end

      def read_input
        lines = []
        prompt_str = lines.empty? ? @renderer.prompt : "  ... "

        loop do
          line = Readline.readline(prompt_str, true)
          return nil if line.nil?

          if @input_handler.multiline?(line)
            lines << @input_handler.strip_continuation(line)
            prompt_str = "  ... "
          else
            lines << line
            break
          end
        end

        lines.join("\n")
      end

      def ensure_home_dir!
        dir = Config::Defaults::HOME_DIR
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def ensure_auth!
        if Auth::TokenStore.valid?
          tokens = Auth::TokenStore.load
          source = tokens&.fetch(:source, :unknown)
          @renderer.info("Authenticated via #{source}") if source == :keychain
          return true
        end

        @renderer.error("No valid authentication found.")
        @renderer.info("Options:")
        @renderer.info("  1. Run Claude Code once to authenticate (Rubyn Code reads the keychain token)")
        @renderer.info("  2. Set ANTHROPIC_API_KEY environment variable")
        @renderer.info("  3. Run 'rubyn-code --auth' to enter an API key")
        exit(1)
      end

      def skill_dirs
        dirs = [File.expand_path("../../../skills", __dir__)]
        project_skills = File.join(@project_root, ".rubyn-code", "skills")
        dirs << project_skills if Dir.exist?(project_skills)
        user_skills = File.join(Config::Defaults::HOME_DIR, "skills")
        dirs << user_skills if Dir.exist?(user_skills)
        dirs
      end

      def current_session_id
        @session_id ||= SecureRandom.hex(16)
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
        "Freezing strings and saving memories... See ya! 💎",
        "Memoizing this session... Until next time! 🧠",
        "Committing learnings to memory... Later! 🤙",
        "Saving state, yielding control... Bye for now! 👋",
        "Session.save! && Rubyn.sleep... Catch you later! 😴",
        "GC.start on this session... Stay Ruby, friend! ✌️",
        "Writing instincts to disk... Don't forget me! 💾",
        "at_exit { puts 'Thanks for coding with Rubyn!' } 🎸",
      ].freeze

      def shutdown!
        return if @shutdown_complete

        @shutdown_complete = true
        @spinner.stop
        puts
        @renderer.info(GOODBYE_MESSAGES.sample)

        @renderer.info("Saving session...")
        save_session!
        @background_worker&.shutdown!

        if @conversation.length > 5
          begin
            @renderer.info("Extracting learnings from this session...")
            Learning::Extractor.call(
              @conversation.messages,
              llm_client: @llm_client,
              project_path: @project_root
            )
            @renderer.success("Instincts saved.")
          rescue StandardError => e
            @renderer.warning("Instinct extraction skipped: #{e.message}") if ENV["RUBYN_DEBUG"]
          end
        end

        begin
          db = DB::Connection.instance
          Learning::InstinctMethods.decay_all(db, project_path: @project_root)
        rescue StandardError
          # Silent — decay is best-effort
        end

        @renderer.info("Session saved. Rubyn out. ✌️")
      rescue StandardError
        # Best effort on shutdown
      end
    end
  end
end
