# frozen_string_literal: true

module RubynCode
  module CLI
    class App
      def self.start(argv)
        new(argv).run
      end

      def initialize(argv)
        @argv = argv
        @options = parse_options(argv)
      end

      def run
        RubynCode::Debug.enable! if @options[:debug]

        case @options[:command]
        when :version
          puts "rubyn-code #{RubynCode::VERSION}"
        when :auth
          run_auth
        when :setup
          run_setup
        when :help
          display_help
        when :run
          run_single_prompt(@options[:prompt])
        when :daemon
          run_daemon
        when :repl
          run_repl
        end
      end

      private

      def parse_options(argv) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
        options = { command: :repl }

        i = 0
        while i < argv.length
          case argv[i]
          when '--version', '-v'
            options[:command] = :version
          when '--help', '-h'
            options[:command] = :help
          when '--auth'
            options[:command] = :auth
          when '--resume', '-r'
            options[:session_id] = argv[i + 1]
            i += 1
          when '-p', '--prompt'
            options[:command] = :run
            options[:prompt] = argv[i + 1]
            i += 1
          when '--yolo'
            options[:yolo] = true
          when '--debug'
            options[:debug] = true
          when '--setup'
            options[:command] = :setup
          when 'daemon'
            options[:command] = :daemon
            parse_daemon_options!(argv, i + 1, options)
            break
          end
          i += 1
        end

        options
      end

      # Parses daemon-specific flags from the argv starting at the given index.
      #
      # @param argv [Array<String>]
      # @param start [Integer]
      # @param options [Hash]
      # @return [void]
      def parse_daemon_options!(argv, start, options) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
        options[:daemon] = {
          max_runs: 100,
          max_cost: 10.0,
          idle_timeout: 60,
          poll_interval: 5,
          agent_name: "golem-#{SecureRandom.hex(4)}",
          role: 'autonomous coding agent'
        }

        i = start
        while i < argv.length
          case argv[i]
          when '--max-runs'
            options[:daemon][:max_runs] = argv[i + 1].to_i
            i += 1
          when '--max-cost'
            options[:daemon][:max_cost] = argv[i + 1].to_f
            i += 1
          when '--idle-timeout'
            options[:daemon][:idle_timeout] = argv[i + 1].to_i
            i += 1
          when '--poll-interval'
            options[:daemon][:poll_interval] = argv[i + 1].to_i
            i += 1
          when '--name'
            options[:daemon][:agent_name] = argv[i + 1]
            i += 1
          when '--role'
            options[:daemon][:role] = argv[i + 1]
            i += 1
          when '--debug'
            options[:debug] = true
          end
          i += 1
        end
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

      def run_daemon
        DaemonRunner.new(@options).run
      end

      def run_repl
        REPL.new(
          session_id: @options[:session_id],
          project_root: Dir.pwd,
          yolo: @options[:yolo]
        ).run
      end

      def display_help
        puts <<~HELP
          rubyn-code - Ruby & Rails Agentic Coding Assistant

          Usage:
            rubyn-code                    Start interactive REPL
            rubyn-code -p "prompt"        Run a single prompt and exit
            rubyn-code --resume [ID]      Resume a previous session
            rubyn-code --setup            Pin rubyn-code to bypass rbenv/rvm
            rubyn-code --auth             Authenticate with Claude
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

          Environment:
            Config:  ~/.rubyn-code/config.yml
            Data:    ~/.rubyn-code/rubyn_code.db
            Tokens:  ~/.rubyn-code/tokens.yml
        HELP
      end
    end
  end
end
