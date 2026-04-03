# frozen_string_literal: true

require "pastel"

module RubynCode
  module Debug
    PASTEL = Pastel.new

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
        @enabled || ENV["RUBYN_DEBUG"]
      end

      def output=(io)
        @output = io
      end

      # ── Core logging ──────────────────────────────────────────────

      def log(tag, message, color: :dim)
        return unless enabled?

        timestamp = Time.now.strftime('%H:%M:%S.%L')
        prefix = PASTEL.dim("[#{timestamp}]") + " " + PASTEL.send(color, "[#{tag}]")
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
    end
  end
end
