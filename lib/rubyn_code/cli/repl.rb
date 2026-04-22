# frozen_string_literal: true

require 'reline'
require_relative 'repl_setup'
require_relative 'repl_lifecycle'
require_relative 'repl_commands'

module RubynCode
  module CLI
    class REPL
      include ReplSetup
      include ReplLifecycle
      include ReplCommands

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
        check_skill_suggestions!

        at_exit { shutdown! }

        @last_interrupt = nil
        run_input_loop
        shutdown!
      end

      private

      def check_skill_suggestions!
        suggest = Skills::AutoSuggest.new(project_root: @project_root)
        message = suggest.check
        @renderer.info(message) if message
      rescue StandardError
        # Never block session start on suggestion failure
      end

      def run_input_loop
        while @running
          begin
            input = read_input
            break if input.nil?

            @last_interrupt = nil
            command = @input_handler.parse(input)
            handle_command(command)
          rescue Interrupt
            handle_interrupt
          end
        end
      end

      def handle_interrupt
        @spinner.stop
        now = Time.now.to_f
        if @last_interrupt && (now - @last_interrupt) < 2.0
          puts
          @running = false
          return
        end
        @last_interrupt = now
        puts
        @renderer.info('Press Ctrl-C again to exit, or type /quit')
      end

      def handle_on_tool_call(name, params)
        @spinner.stop
        unless @streaming_first_chunk
          @stream_formatter&.flush
          @stream_formatter = nil
          puts
          @streaming_first_chunk = true
        end
        @renderer.tool_call(name, params)
      end

      def handle_on_tool_result(name, result)
        @renderer.tool_result(name, result)
        @spinner.start
      end

      def handle_on_text(text)
        @spinner.stop
        if @streaming_first_chunk
          @stream_formatter = StreamFormatter.new
          puts
          @streaming_first_chunk = false
        end
        @stream_formatter&.feed(text)
      end

      def handle_message(input) # rubocop:disable Metrics/AbcSize -- sequential steps with interrupt rescue
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
      rescue Interrupt
        @spinner.stop
        puts
        @renderer.warning('Interrupted — session state preserved')
        save_session!
      rescue BudgetExceededError => e
        @spinner.error
        @renderer.error("Budget exceeded: #{e.message}")
      rescue StandardError => e
        @spinner.error
        @renderer.error("Error: #{e.message}")
      end

      def setup_readline!
        completions = @command_registry.completions

        Reline.completion_proc = proc do |input|
          input.start_with?('/') ? completions.select { |c| c.start_with?(input) } : []
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
    end
  end
end
