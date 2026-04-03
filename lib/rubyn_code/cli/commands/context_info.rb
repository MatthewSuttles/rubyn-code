# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class ContextInfo < Base
        def self.command_name = '/context'
        def self.description = 'Show context window usage'

        CONTEXT_WINDOW = 200_000

        def execute(_args, ctx)
          stats = estimate_context(ctx)
          render_context_bar(stats, ctx)
        end

        private

        def estimate_context(ctx)
          messages = ctx.conversation.messages
          estimated = Observability::TokenCounter.estimate_messages(messages)
          pct = ((estimated.to_f / CONTEXT_WINDOW) * 100).round(1)
          { estimated: estimated, pct: pct, message_count: messages.size }
        end

        def render_context_bar(stats, ctx)
          puts
          puts "  Context: [#{progress_bar(stats[:pct])}] #{stats[:pct]}%"
          puts "  #{fmt(stats[:estimated])} / #{fmt(CONTEXT_WINDOW)} tokens  •  #{stats[:message_count]} messages"
          puts "  Model: #{Config::Defaults::DEFAULT_MODEL}#{plan_label(ctx)}"
          puts
        end

        def progress_bar(pct, width: 30)
          filled = [(pct / 100.0 * width).round, width].min
          "#{bar_color(pct)}#{'█' * filled}\e[0m#{'░' * (width - filled)}"
        end

        def bar_color(pct)
          return "\e[31m" if pct >= 80
          return "\e[33m" if pct >= 50

          "\e[32m"
        end

        def plan_label(ctx)
          ctx.plan_mode? ? ' • 🧠 plan mode' : ''
        end

        def fmt(num)
          num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
        end
      end
    end
  end
end
