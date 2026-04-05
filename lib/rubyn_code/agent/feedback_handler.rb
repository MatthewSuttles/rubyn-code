# frozen_string_literal: true

module RubynCode
  module Agent
    # Detects positive/negative user feedback and reinforces learned instincts.
    module FeedbackHandler
      POSITIVE_PATTERNS =
        /\b(yes that fixed it|that worked|perfect|thanks|exactly|great|nailed it|that.s right|correct)\b/i
      NEGATIVE_PATTERNS =
        /\b(no[, ]+use|wrong|that.s not right|instead use|don.t do that|actually[, ]+use|incorrect)\b/i

      private

      def check_user_feedback(user_input)
        return unless @project_root

        recent_instincts = fetch_recent_instincts
        return if recent_instincts.empty?

        reinforce_instincts(user_input, recent_instincts)
      rescue StandardError
        # Non-critical; don't interrupt the conversation
      end

      def fetch_recent_instincts
        db = DB::Connection.instance
        db.query(
          'SELECT id FROM instincts WHERE project_path = ? ORDER BY updated_at DESC LIMIT 5',
          [@project_root]
        ).to_a
      end

      def reinforce_instincts(user_input, recent_instincts)
        if user_input.match?(POSITIVE_PATTERNS)
          reinforce_top(recent_instincts, helpful: true)
        elsif user_input.match?(NEGATIVE_PATTERNS)
          reinforce_top(recent_instincts, helpful: false)
        end
      end

      def reinforce_top(instincts, helpful:)
        db = DB::Connection.instance
        instincts.first(2).each do |row|
          Learning::InstinctMethods.reinforce_in_db(row['id'], db, helpful: helpful)
        end
      end
    end
  end
end
