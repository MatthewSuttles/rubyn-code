# frozen_string_literal: true

module RubynCode
  module CLI
    # Infrastructure and service setup for the REPL.
    module ReplSetup # rubocop:disable Metrics/ModuleLength -- REPL setup requires many service initializations
      private

      def setup_components!
        setup_infrastructure!
        setup_services!
        setup_executor_callbacks!
        setup_hooks!
        setup_mcp_servers!
        setup_agent_loop!
      end

      def setup_infrastructure!
        ensure_home_dir!
        @db = DB::Connection.instance
        DB::Migrator.new(@db).migrate!
        @auth = ensure_auth!
      end

      def setup_services!
        setup_core_services!
        setup_auxiliary_services!
      end

      def setup_core_services!
        @llm_client = LLM::Client.new
        @conversation = Agent::Conversation.new
        @tool_executor = Tools::Executor.new(project_root: @project_root)
        @context_manager = Context::Manager.new(llm_client: @llm_client)
        @hook_registry = Hooks::Registry.new
        @hook_runner = Hooks::Runner.new(registry: @hook_registry)
        @stall_detector = Agent::LoopDetector.new
      end

      def setup_auxiliary_services!
        @deny_list = Permissions::DenyList.new
        @budget_enforcer = Observability::BudgetEnforcer.new(@db, session_id: current_session_id)
        @background_worker = Background::Worker.new(project_root: @project_root)
        @skill_loader = Skills::Loader.new(Skills::Catalog.new(skill_dirs))
        @session_persistence = Memory::SessionPersistence.new(@db)
      end

      def setup_executor_callbacks!
        @tool_executor.llm_client = @llm_client
        @tool_executor.background_worker = @background_worker
        @tool_executor.db = @db
        @tool_executor.ask_user_callback = build_ask_user_callback
        @sub_agent_tool_count = 0
        @in_sub_agent = false
        @tool_executor.on_agent_status = build_agent_status_callback
      end

      def build_ask_user_callback
        ->(question) { prompt_user_for_answer(question) }
      end

      def prompt_user_for_answer(question)
        @spinner.stop
        @renderer.warning('Rubyn is asking:')
        puts "  #{question}"
        print '  > '
        $stdout.flush
        answer = Reline.readline('', false)&.strip
        answer.nil? || answer.empty? ? '[no response]' : answer
      end

      def build_agent_status_callback
        ->(type, msg) { handle_agent_status(type, msg) }
      end

      def handle_agent_status(type, msg)
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
      end

      def setup_hooks!
        Hooks::BuiltIn.register_all!(@hook_registry)
        Hooks::UserHooks.load!(@hook_registry, project_root: @project_root)
      end

      def setup_agent_loop!
        @agent_loop = Agent::Loop.new(
          llm_client: @llm_client, tool_executor: @tool_executor,
          context_manager: @context_manager, hook_runner: @hook_runner,
          conversation: @conversation, permission_tier: @permission_tier,
          deny_list: @deny_list, budget_enforcer: @budget_enforcer,
          background_manager: @background_worker, stall_detector: @stall_detector,
          on_tool_call: ->(name, params) { handle_on_tool_call(name, params) },
          on_tool_result: ->(name, result, _is_error = false) { handle_on_tool_result(name, result) },
          on_text: ->(text) { handle_on_text(text) },
          skill_loader: @skill_loader, project_root: @project_root
        )
      end

      def ensure_home_dir!
        FileUtils.mkdir_p(Config::Defaults::HOME_DIR)
      end

      def ensure_auth!
        provider = config_settings.provider
        tokens = Auth::TokenStore.load_for_provider(provider)

        if tokens
          announce_auth_source(tokens)
          return true
        end

        print_auth_help(provider)
        exit(1)
      end

      def announce_auth_source(tokens)
        source = tokens.fetch(:source, :unknown)
        display_name = Auth::TokenStore.display_name_for(source)
        @renderer.info("Authenticated via #{display_name}") if display_name
      end

      def print_auth_help(provider)
        @renderer.error("No valid authentication found for provider '#{provider}'.")
        @renderer.info('Options:')
        Auth::TokenStore.setup_hints_for(provider).each_with_index do |hint, idx|
          @renderer.info("  #{idx + 1}. #{hint}")
        end
      end

      def config_settings
        @config_settings ||= Config::Settings.new
      end

      def skill_dirs
        dirs = [File.expand_path('../../../skills', __dir__)]
        project_skills = File.join(@project_root, '.rubyn-code', 'skills')
        dirs << project_skills if Dir.exist?(project_skills)
        user_skills = File.join(Config::Defaults::HOME_DIR, 'skills')
        dirs << user_skills if Dir.exist?(user_skills)
        dirs
      end

      # ── MCP Server Wiring ─────────────────────────────────────────

      def setup_mcp_servers!
        @mcp_clients = []
        server_configs = MCP::Config.load(@project_root)
        return if server_configs.empty?

        server_configs.each do |config|
          connect_mcp_server(config)
        end

        at_exit { disconnect_mcp_clients! unless defined?(RSpec) }
      end

      def connect_mcp_server(config)
        client = MCP::Client.from_config(config)
        client.connect!
        MCP::ToolBridge.bridge(client)
        @mcp_clients << client
        @renderer.info("MCP server '#{config[:name]}' connected (#{client.tools.size} tools)")
      rescue StandardError => e
        warn "[MCP] Failed to connect '#{config[:name]}': #{e.message}"
      end

      def disconnect_mcp_clients!
        return if @mcp_clients.nil? || @mcp_clients.empty?

        @mcp_clients.each do |client|
          client.disconnect!
        rescue StandardError => e
          warn "[MCP] Error disconnecting '#{client.name}': #{e.message}"
        end
        @mcp_clients.clear
      end
    end
  end
end
