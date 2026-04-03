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
        when :help
          display_help
        when :run
          run_single_prompt(@options[:prompt])
        when :repl
          run_repl
        end
      end

      private

      def parse_options(argv)
        options = { command: :repl }

        i = 0
        while i < argv.length
          case argv[i]
          when "--version", "-v"
            options[:command] = :version
          when "--help", "-h"
            options[:command] = :help
          when "--auth"
            options[:command] = :auth
          when "--resume", "-r"
            options[:session_id] = argv[i + 1]
            i += 1
          when "-p", "--prompt"
            options[:command] = :run
            options[:prompt] = argv[i + 1]
            i += 1
          when "--yolo"
            options[:yolo] = true
          when "--debug"
            options[:debug] = true
          end
          i += 1
        end

        options
      end

      def run_auth
        renderer = Renderer.new
        renderer.info("Starting Claude OAuth authentication...")

        begin
          Auth::OAuth.new.authenticate!
          renderer.success("Authentication successful! Token stored.")
        rescue AuthenticationError => e
          renderer.error("Authentication failed: #{e.message}")
          exit(1)
        end
      end

      def run_single_prompt(prompt)
        return display_help unless prompt

        repl = REPL.new(project_root: Dir.pwd)
        # Non-interactive: send one message and exit
        response = repl.instance_variable_get(:@agent_loop).send_message(prompt)
        puts response
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
            rubyn-code --debug            Enable debug output
            rubyn-code --auth             Authenticate with Claude
            rubyn-code --version          Show version
            rubyn-code --help             Show this help

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
