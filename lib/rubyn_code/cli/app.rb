# frozen_string_literal: true

module RubynCode
  module CLI
    class App # rubocop:disable Metrics/ClassLength -- CLI dispatch requires many small methods
      def self.start(argv)
        new(argv).run
      end

      def initialize(argv)
        @argv = argv
        @options = parse_options(argv)
      end

      def run
        RubynCode::Debug.enable! if @options[:debug]
        dispatch_command(@options[:command])
      end

      HELP_TEXT = <<~HELP
        rubyn-code - Ruby & Rails Agentic Coding Assistant

        Usage:
          rubyn-code                    Start interactive REPL
          rubyn-code -p "prompt"        Run a single prompt and exit
          rubyn-code --resume [ID]      Resume a previous session
          rubyn-code --setup            Pin rubyn-code to bypass rbenv/rvm
          rubyn-code --auth             Authenticate with Claude
          rubyn-code --install-skills NAME  Install a skill pack from the registry
          rubyn-code --ide              Start IDE server (VS Code extension)
          rubyn-code --permission-mode MODE  Set permission mode (default, accept_edits, plan_only, auto, dont_ask, bypass)
          rubyn-code --version          Show version
          rubyn-code --help             Show this help

        Daemon Mode:
          rubyn-code daemon             Start autonomous daemon (GOLEM)
          rubyn-code daemon --name NAME Agent name (default: golem-<random>)
          rubyn-code daemon --role ROLE Agent role description
          rubyn-code daemon --max-runs N     Max tasks before shutdown (default: 100)
          rubyn-code daemon --max-cost N     Max USD spend before shutdown (default: 10.0)
          rubyn-code daemon --idle-timeout N Seconds idle before shutdown (default: 60)
          rubyn-code daemon --poll-interval N Seconds between polls (default: 5)

        Interactive Commands:
          /help          Show available commands
          /quit          Exit
          /compact       Compress context
          /cost          Show usage costs
          /tasks         List tasks
          /skill [name]  Load or list skills
          /skills        List installed and community skill packs
          /install-skills Install skill packs from rubyn.ai
          /remove-skills  Remove an installed skill pack

        Environment:
          Config:  ~/.rubyn-code/config.yml
          Data:    ~/.rubyn-code/rubyn_code.db
          Tokens:  ~/.rubyn-code/tokens.yml
      HELP

      SIMPLE_FLAGS = {
        '--version' => :version, '-v' => :version,
        '--help' => :help, '-h' => :help,
        '--auth' => :auth, '--setup' => :setup
      }.freeze
      BOOLEAN_FLAGS = { '--yolo' => :yolo, '--debug' => :debug, '--skip-setup' => :skip_setup, '--ide' => :ide }.freeze
      VALUE_FLAGS = { '--permission-mode' => :permission_mode }.freeze
      DAEMON_INT_FLAGS = { '--max-runs' => :max_runs, '--idle-timeout' => :idle_timeout,
                           '--poll-interval' => :poll_interval }.freeze
      DAEMON_STR_FLAGS = { '--name' => :agent_name, '--role' => :role }.freeze

      private

      def dispatch_command(command) # rubocop:disable Metrics/CyclomaticComplexity -- unavoidable dispatch switch
        case command
        when :version        then puts "rubyn-code #{RubynCode::VERSION}"
        when :auth           then run_auth
        when :setup          then run_setup
        when :help           then display_help
        when :run            then run_single_prompt(@options[:prompt])
        when :ide            then run_ide
        when :daemon         then run_daemon
        when :install_skills then run_install_skills(@options[:install_skills_names])
        when :repl           then run_repl
        end
      end

      def parse_options(argv)
        options = { command: :repl }
        idx = 0
        while idx < argv.length
          idx = parse_single_option(argv, idx, options)
          idx += 1
        end
        options[:command] = :ide if options[:ide]
        options
      end

      # -- option parser
      def parse_single_option(argv, idx, options)
        arg = argv[idx]
        if SIMPLE_FLAGS.key?(arg)
          options[:command] = SIMPLE_FLAGS[arg]
        elsif BOOLEAN_FLAGS.key?(arg)
          options[BOOLEAN_FLAGS[arg]] = true
        elsif VALUE_FLAGS.key?(arg)
          options[VALUE_FLAGS[arg]] = argv[idx + 1]
          idx += 1
        else
          idx = parse_value_option(argv, idx, options)
        end
        idx
      end

      def parse_value_option(argv, idx, options)
        case argv[idx]
        when '--resume', '-r'
          options[:session_id] = argv[idx + 1]
          idx + 1
        when '-p', '--prompt'
          options[:command] = :run
          options[:prompt] = argv[idx + 1]
          idx + 1
        when '--install-skills'
          options[:command] = :install_skills
          options[:install_skills_names] = collect_pack_names(argv, idx + 1)
          argv.length - 1
        when 'daemon'
          options[:command] = :daemon
          parse_daemon_options!(argv, idx + 1, options)
          argv.length - 1
        else
          idx
        end
      end

      def parse_daemon_options!(argv, start, options)
        options[:daemon] = default_daemon_options
        idx = start
        while idx < argv.length
          idx = parse_single_daemon_option(argv, idx, options)
          idx += 1
        end
      end

      def default_daemon_options
        {
          max_runs: 100,
          max_cost: 10.0,
          idle_timeout: 60,
          poll_interval: 5,
          agent_name: "golem-#{SecureRandom.hex(4)}",
          role: 'autonomous coding agent'
        }
      end

      def parse_single_daemon_option(argv, idx, options)
        case argv[idx]
        when '--debug'
          options[:debug] = true
        else
          idx = parse_daemon_value_option(argv, idx, options)
        end
        idx
      end

      def parse_daemon_value_option(argv, idx, options) # rubocop:disable Metrics/AbcSize -- option dispatch with hash lookup
        arg = argv[idx]
        daemon = options[:daemon]
        if DAEMON_INT_FLAGS.key?(arg)
          daemon[DAEMON_INT_FLAGS[arg]] = argv[idx + 1].to_i
        elsif arg == '--max-cost'
          daemon[:max_cost] = argv[idx + 1].to_f
        elsif DAEMON_STR_FLAGS.key?(arg)
          daemon[DAEMON_STR_FLAGS[arg]] = argv[idx + 1]
        else
          return idx
        end
        idx + 1
      end

      def run_auth
        renderer = Renderer.new
        renderer.info('Starting Claude OAuth authentication...')

        begin
          Auth::OAuth.new.authenticate!
          renderer.success('Authentication successful! Token stored.')
        rescue AuthenticationError => e
          renderer.error("Authentication failed: #{e.message}")
          exit(1)
        end
      end

      def run_setup
        Setup.run
      end

      def run_single_prompt(prompt)
        return display_help unless prompt

        repl = REPL.new(project_root: Dir.pwd)
        # Non-interactive: send one message and exit
        response = repl.instance_variable_get(:@agent_loop).send_message(prompt)
        puts response
      end

      def run_ide
        mode = resolve_permission_mode
        IDE::Server.new(permission_mode: mode).run
      end

      def run_daemon
        DaemonRunner.new(@options).run
      end

      def run_install_skills(names)
        renderer = Renderer.new
        client = Skills::RegistryClient.new
        installer = Skills::PackInstaller.new(
          registry_client: client,
          project_root: Dir.pwd,
          global: @options[:install_skills_global]
        )

        if names.empty? || names.include?('--update')
          renderer.info('Checking for updates on all installed packs...')
          results = installer.update_all do |event, data|
            report_install_progress(renderer, event, data)
          end
          updated = results.select { |r| r[:status] == :installed }
          if updated.empty?
            renderer.info('All packs are up to date.')
          else
            renderer.info("Updated #{updated.size} pack(s).")
          end
        else
          installer.install(names) do |event, data|
            report_install_progress(renderer, event, data)
          end
        end
      rescue Skills::RegistryError => e
        renderer.error("Registry error: #{e.message}")
        exit(1)
      rescue StandardError => e
        renderer.error("Install failed: #{e.message}")
        exit(1)
      end

      def report_install_progress(renderer, event, data)
        case event
        when :fetching   then renderer.info("Fetching #{data[:name]} from rubyn.ai...")
        when :downloading then renderer.info("  Downloading #{data[:total]} skill files...")
        when :installed
          data[:files].each { |f| puts "  → #{data[:name]}/#{f}" }
          renderer.info("Installed #{data[:files].size} skills to .rubyn-code/skills/#{data[:name]}/")
        when :up_to_date then renderer.info("#{data[:name]} is already up to date (v#{data[:version]}).")
        when :error      then renderer.error("Failed: #{data[:name]}: #{data[:message]}")
        end
      end

      def collect_pack_names(argv, start)
        names = []
        idx = start
        while idx < argv.length
          arg = argv[idx]
          break if arg.start_with?('-') && arg != '--update' && arg != '--global'

          if arg == '--global'
            @options ||= {}
            @options[:install_skills_global] = true
          else
            names << arg
          end
          idx += 1
        end
        names
      end

      def run_repl
        maybe_first_run!
        REPL.new(
          session_id: @options[:session_id],
          project_root: Dir.pwd,
          yolo: @options[:yolo]
        ).run
      end

      def maybe_first_run!
        return unless FirstRun.needed?
        return if FirstRun.skipped?(skip_flag: @options[:skip_setup])

        FirstRun.new.run
      end

      def resolve_permission_mode
        if @options[:permission_mode]
          @options[:permission_mode].to_sym
        elsif @options[:yolo]
          :bypass
        else
          :default
        end
      end

      def display_help
        puts HELP_TEXT
      end
    end
  end
end
