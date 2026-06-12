# frozen_string_literal: true

module RubynCode
  module Debug
    @enabled = false
    @output = $stderr

    class << self
      attr_reader :enabled

      def enable!
        @enabled = true
      end

      def disable!
        @enabled = false
      end

      def enabled?
        @enabled || ENV.fetch('RUBYN_DEBUG', nil)
      end

      attr_writer :output

      # ── Core logging ──────────────────────────────────────────────

      def log(tag, message, color: :dim)
        return unless enabled?

        timestamp = Time.now.strftime('%H:%M:%S.%L')
        prefix = "#{pastel.dim("[#{timestamp}]")} #{pastel.send(color, "[#{tag}]")}"
        @output.puts "#{prefix} #{message}"
      end

      # ── Convenience methods ───────────────────────────────────────

      def llm(message)
        log('llm', message, color: :magenta)
      end

      def tool(message)
        log('tool', message, color: :cyan)
      end

      def agent(message)
        log('agent', message, color: :yellow)
      end

      def loop_tick(message)
        log('loop', message, color: :green)
      end

      def recovery(message)
        log('recovery', message, color: :red)
      end

      def token(message)
        log('token', message, color: :blue)
      end

      def warn(message)
        log('warn', message, color: :yellow)
      end

      def error(message)
        log('error', message, color: :red)
      end

      private

      # Lazy so boot never pays for pastel when debug output is off.
      def pastel
        @pastel ||= begin
          require 'pastel'
          Pastel.new
        end
      end
    end
  end
end
