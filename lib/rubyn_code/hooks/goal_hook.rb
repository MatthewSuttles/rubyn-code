# frozen_string_literal: true

module RubynCode
  module Hooks
    # A Stop hook that keeps the agent working until a session goal is met.
    #
    # When active, firing the :stop event asks an evaluator whether the goal
    # condition is satisfied. If it is, the hook deactivates itself (the goal
    # "auto-clears") and allows the agent to stop. If not, it returns a block
    # decision whose reason is re-injected into the conversation, nudging the
    # agent to keep working.
    #
    # A max-attempts safety valve prevents an unsatisfiable goal from looping
    # forever — after MAX_ATTEMPTS consecutive blocks the hook gives up and
    # lets the agent stop.
    class GoalHook
      DEFAULT_MAX_ATTEMPTS = 12

      # @return [String] the goal condition
      attr_reader :condition

      # @param condition [String] plain-language goal condition
      # @param evaluator [#call, nil] judges completion; nil disables auto-clear
      # @param max_attempts [Integer] consecutive blocks before giving up
      def initialize(condition:, evaluator: nil, max_attempts: DEFAULT_MAX_ATTEMPTS)
        @condition = condition
        @evaluator = evaluator
        @max_attempts = max_attempts
        @attempts = 0
        @active = true
      end

      # @return [Boolean]
      def active? = @active

      # Cancel the goal early (e.g. `/goal clear`).
      # @return [void]
      def clear!
        @active = false
      end

      # Fired on the :stop event by Hooks::Runner.
      #
      # @param conversation [Agent::Conversation, nil] recent work, for judging
      # @return [Hash, nil] { block: true, reason: } to keep working, else nil
      def call(conversation: nil, **_kwargs)
        return nil unless @active

        if goal_met?(conversation)
          @active = false
          return nil
        end

        @attempts += 1
        if @attempts >= @max_attempts
          @active = false
          RubynCode::Debug.warn("Goal abandoned after #{@max_attempts} attempts: #{@condition}")
          return nil
        end

        { block: true, reason: reminder }
      end

      private

      def goal_met?(conversation)
        return false unless @evaluator

        @evaluator.call(condition: @condition, conversation: conversation)
      rescue StandardError => e
        RubynCode::Debug.warn("Goal hook evaluation error: #{e.message}")
        false
      end

      def reminder
        <<~TEXT.strip
          Your active goal is not yet complete:

            #{@condition}

          Keep working toward it now — do not stop or ask what to do next.
          If you are certain the goal is genuinely and fully met, state that
          explicitly and explain how it was satisfied.
        TEXT
      end
    end
  end
end
