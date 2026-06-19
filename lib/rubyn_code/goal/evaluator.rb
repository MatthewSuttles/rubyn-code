# frozen_string_literal: true

module RubynCode
  # Session goals: a goal is a plain-language condition the user wants
  # satisfied before the agent stops working. The Goal::Evaluator judges,
  # via a lightweight LLM call, whether the condition has been met based on
  # the recent conversation. Used by Hooks::GoalHook on the :stop event.
  module Goal
    # Judges whether a goal condition has been satisfied.
    #
    # The evaluator is deliberately conservative: it returns true only when
    # the model is confident the goal is genuinely complete. Any error or
    # ambiguous answer is treated as "not met" so the agent keeps working
    # rather than stopping prematurely.
    class Evaluator
      SYSTEM_PROMPT = <<~PROMPT
        You are a strict completion judge. Given a GOAL and a transcript of an
        AI coding agent's recent work, decide whether the goal is genuinely and
        fully satisfied. Be conservative: if there is any doubt, or the work is
        only partially done, answer NO. Answer with exactly one word on the
        first line: YES or NO. Optionally add a short reason on the next line.
      PROMPT

      # Number of trailing conversation messages to show the judge.
      TRANSCRIPT_WINDOW = 12

      # @param llm_client [LLM::Client]
      def initialize(llm_client:)
        @llm_client = llm_client
      end

      # @param condition [String] the goal condition
      # @param conversation [Agent::Conversation, nil] recent work to judge
      # @return [Boolean] true only when the goal is confidently complete
      def call(condition:, conversation: nil)
        response = @llm_client.chat(
          messages: [{ role: 'user', content: prompt(condition, conversation) }],
          system: SYSTEM_PROMPT
        )
        verdict_yes?(answer_text(response))
      rescue StandardError => e
        RubynCode::Debug.warn("Goal evaluation failed: #{e.message}")
        false
      end

      private

      def prompt(condition, conversation)
        <<~TEXT
          GOAL:
          #{condition}

          RECENT WORK:
          #{transcript(conversation)}

          Is the goal genuinely and fully satisfied? Answer YES or NO.
        TEXT
      end

      def transcript(conversation)
        return '(no work recorded yet)' unless conversation.respond_to?(:messages)

        Array(conversation.messages).last(TRANSCRIPT_WINDOW).map do |msg|
          "#{msg[:role]}: #{message_text(msg[:content])}"
        end.join("\n").slice(0, 6000)
      end

      def message_text(content)
        case content
        when String then content
        when Array
          content.filter_map { |b| b.is_a?(Hash) ? (b[:text] || b['text']) : nil }.join(' ')
        else
          content.to_s
        end
      end

      def answer_text(response)
        if response.respond_to?(:content)
          Array(response.content).filter_map { |b| b.respond_to?(:text) ? b.text : nil }.join("\n")
        elsif response.is_a?(Hash)
          Array(response[:content] || response['content'])
            .filter_map { |b| b.is_a?(Hash) ? (b[:text] || b['text']) : nil }.join("\n")
        else
          response.to_s
        end
      end

      def verdict_yes?(text)
        first = text.to_s.strip.split("\n").first.to_s.strip.upcase
        first.start_with?('YES')
      end
    end
  end
end
