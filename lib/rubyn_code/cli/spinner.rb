# frozen_string_literal: true

require 'tty-spinner'

module RubynCode
  module CLI
    class Spinner
      THINKING_MESSAGES = [
        'Massaging the hash...',
        'Refactoring in my head...',
        'Consulting Matz...',
        'Freezing strings...',
        'Monkey-patching reality...',
        'Yielding to the block...',
        'Enumerating possibilities...',
        'Injecting dependencies...',
        'Guard clause-ing my thoughts...',
        'Sharpening the gems...',
        'Duck typing furiously...',
        'Reducing complexity...',
        'Mapping it out...',
        'Selecting the right approach...',
        'Running the mental specs...',
        'Composing a module...',
        'Memoizing the answer...',
        'Digging through the hash...',
        'Pattern matching on this...',
        'Raising my standards...',
        'Rescuing the situation...',
        'Benchmarking my thoughts...',
        'Sending :think to self...',
        'Evaluating the proc...',
        'Opening the eigenclass...',
        'Calling .new on an idea...',
        'Plucking the good bits...',
        'Finding each solution...',
        'Requiring more context...',
        'Bundling my thoughts...'
      ].freeze

      SUB_AGENT_MESSAGES = [
        'Sub-agent is spelunking...',
        'Agent exploring the codebase...',
        'Reading all the things...',
        'Sub-agent doing the legwork...',
        'Agent grepping through files...',
        'Dispatching the intern...'
      ].freeze

      def initialize
        @spinner = nil
      end

      def start(message = nil)
        message ||= THINKING_MESSAGES.sample
        @spinner = TTY::Spinner.new(
          "[:spinner] #{message}",
          format: :dots,
          clear: true
        )
        @spinner.auto_spin
      end

      def start_sub_agent(tool_count = 0)
        msg = if tool_count.positive?
                "#{SUB_AGENT_MESSAGES.sample} (#{tool_count} tools)"
              else
                SUB_AGENT_MESSAGES.sample
              end
        start(msg)
      end

      def update(message)
        return start(message) unless spinning?

        stop
        start(message)
      end

      def success(message = 'Done')
        @spinner&.success("(#{message})")
        @spinner = nil
      end

      def error(message = 'Failed')
        @spinner&.error("(#{message})")
        @spinner = nil
      end

      def stop
        @spinner&.stop
        @spinner = nil
      end

      def spinning?
        @spinner&.spinning? || false
      end
    end
  end
end
