# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Tokens < Base
        def self.command_name = '/tokens'
        def self.description = 'Show token usage and context window estimate'

        # Claude's context window
        CONTEXT_WINDOW = 200_000

        TokenStats = Data.define(:estimated, :threshold, :actual_in, :actual_out, :message_count) do
          def pct_window = ((estimated.to_f / CONTEXT_WINDOW) * 100).round(1)
          def pct_threshold = ((estimated.to_f / threshold) * 100).round(1)
          def total = actual_in + actual_out
        end

        def execute(_args, ctx)
          stats = gather_stats(ctx)
          render_estimation(stats)
          render_actual_usage(stats)
          warn_if_near_threshold(stats, ctx.renderer)
        end

        private

        def gather_stats(ctx)
          mgr = ctx.context_manager
          estimated = Observability::TokenCounter.estimate_messages(ctx.conversation.messages)
          threshold = mgr.instance_variable_get(:@threshold) || 50_000

          TokenStats.new(
            estimated: estimated, threshold: threshold,
            actual_in: mgr.total_input_tokens,
            actual_out: mgr.total_output_tokens,
            message_count: ctx.conversation.messages.size
          )
        end

        def render_estimation(stats)
          puts
          puts "  #{bold('Token Estimation')}"
          puts "  #{dim('─' * 40)}"
          puts "  Context estimate:  #{fmt(stats.estimated)} tokens " \
               "(~#{stats.pct_window}% of #{fmt(CONTEXT_WINDOW)} window)"
          puts "  Compaction at:     #{fmt(stats.threshold)} tokens (#{stats.pct_threshold}% used)"
          puts "  Messages:          #{stats.message_count}"
        end

        def render_actual_usage(stats)
          puts
          puts "  #{bold('Actual Usage (this session)')}"
          puts "  #{dim('─' * 40)}"
          puts "  Input tokens:      #{fmt(stats.actual_in)}"
          puts "  Output tokens:     #{fmt(stats.actual_out)}"
          puts "  Total:             #{fmt(stats.total)}"
          puts
        end

        def warn_if_near_threshold(stats, renderer)
          return unless stats.pct_threshold >= 80

          renderer.warning('⚠ Context nearing compaction threshold. Consider /compact.')
        end

        def bold(text) = "\e[1m#{text}\e[0m"
        def dim(text)  = "\e[2m#{text}\e[0m"

        def fmt(num)
          num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
        end
      end
    end
  end
end
