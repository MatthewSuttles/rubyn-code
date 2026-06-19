# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/loop` — run a prompt or slash command repeatedly, mirroring Claude
      # Code's /loop. Either on a fixed interval, or self-paced (the agent
      # decides when the recurring task is done).
      #
      #   /loop 5m /review            run /review every 5 minutes
      #   /loop 30s check the deploy  send a prompt every 30 seconds
      #   /loop x10 5m /babysit-prs   ...at most 10 times
      #   /loop keep triaging issues  self-paced (until the agent emits LOOP_DONE)
      #
      # Returns a :run_loop action; the REPL owns the actual loop so Ctrl-C
      # stops it cleanly and slash payloads can be re-dispatched.
      class Loop < Base
        def self.command_name = '/loop'
        def self.description  = 'Repeat a prompt or slash command on an interval (/loop 5m /review)'

        MAX_TOKEN = /\Ax(\d+)\z/i

        def execute(args, ctx)
          return usage(ctx) if args.empty?

          max, rest = extract_max(args)
          interval = LoopRunner.parse_interval(rest.first)
          payload = (interval ? rest[1..] : rest).join(' ').strip
          return usage(ctx) if payload.empty?

          { action: :run_loop, interval: interval, max: max, payload: payload }
        end

        private

        # Pull an optional leading "xN" max-iterations token from anywhere in
        # the first two positions (so both `/loop x5 5m ...` and `/loop 5m ...`
        # read naturally).
        def extract_max(args)
          idx = args[0, 2].index { |a| a.match?(MAX_TOKEN) }
          return [LoopRunner::DEFAULT_MAX_ITERATIONS, args] unless idx

          max = args[idx][MAX_TOKEN, 1].to_i
          [max.positive? ? max : LoopRunner::DEFAULT_MAX_ITERATIONS, args[0...idx] + args[(idx + 1)..]]
        end

        def usage(ctx)
          ctx.renderer.info('Usage: /loop [xN] [interval] <prompt-or-/command>')
          ctx.renderer.info('  /loop 5m /review        — run /review every 5 minutes')
          ctx.renderer.info('  /loop 30s check status  — send a prompt every 30s')
          ctx.renderer.info('  /loop x3 1m /babysit    — at most 3 times')
          ctx.renderer.info('  /loop keep triaging     — self-paced (Ctrl-C to stop)')
          nil
        end
      end
    end
  end
end
