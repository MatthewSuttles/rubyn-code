# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/goal` — set a session goal that Rubyn keeps working toward until it
      # is met. Installs a Stop hook (Hooks::GoalHook) that blocks the agent
      # from finishing while the goal is unmet; the goal auto-clears once an
      # evaluator judges it satisfied.
      #
      #   /goal <condition>   set a goal and start working toward it
      #   /goal               show the current goal (if any)
      #   /goal clear         cancel the active goal early
      class Goal < Base
        def self.command_name = '/goal'
        def self.description  = 'Set a goal Rubyn works toward until met (/goal clear to cancel)'

        CLEAR_WORDS = %w[clear cancel off stop].freeze

        def execute(args, ctx)
          first = args.first&.strip&.downcase
          return clear_goal(ctx) if CLEAR_WORDS.include?(first)

          condition = args.join(' ').strip
          return show_status(ctx) if condition.empty?

          set_goal(ctx, condition)
        end

        private

        def set_goal(ctx, condition)
          deactivate_existing(ctx)
          evaluator = RubynCode::Goal::Evaluator.new(llm_client: ctx.llm_client)
          ctx.hook_registry.on(:stop, Hooks::GoalHook.new(condition: condition, evaluator: evaluator), priority: 10)

          ctx.renderer.info("🎯 Goal set: #{condition}")
          ctx.renderer.info("Rubyn will keep working until it's met. /goal clear to cancel.")
          ctx.send_message(kickoff_prompt(condition))
          nil
        end

        def clear_goal(ctx)
          if deactivate_existing(ctx).positive?
            ctx.renderer.info('Goal cleared. ✌️')
          else
            ctx.renderer.info('No active goal to clear.')
          end
          nil
        end

        def show_status(ctx)
          active = active_goals(ctx)
          if active.empty?
            ctx.renderer.info('No active goal. Set one with: /goal <what you want done>')
          else
            ctx.renderer.info("🎯 Active goal: #{active.first.condition}")
          end
          nil
        end

        # Deactivate any active GoalHook(s) on the registry.
        # @return [Integer] number of goals deactivated
        def deactivate_existing(ctx)
          active_goals(ctx).each(&:clear!).size
        end

        def active_goals(ctx)
          return [] unless ctx.hook_registry

          ctx.hook_registry.hooks_for(:stop).select do |hook|
            hook.is_a?(Hooks::GoalHook) && hook.active?
          end
        end

        def kickoff_prompt(condition)
          <<~PROMPT.strip
            New session goal: #{condition}

            Start working toward this goal now. Keep going until it is genuinely
            met — don't stop to ask what to do next.
          PROMPT
        end
      end
    end
  end
end
