# frozen_string_literal: true

module RubynCode
  module Context
    # Triggers compaction at logical decision boundaries rather than
    # only at capacity limits. This prevents late-session context bloat
    # by compacting after meaningful milestones.
    class DecisionCompactor
      # Percentage of context threshold at which to trigger compaction
      # on decision boundaries (lower than the default 95%).
      EARLY_COMPACT_RATIO = 0.6

      TRIGGERS = %i[
        specs_passed
        topic_switch
        multi_file_edit_complete
      ].freeze

      attr_reader :pending_trigger

      def initialize(context_manager:, threshold: nil)
        @context_manager = context_manager
        @threshold = threshold || Config::Defaults::CONTEXT_THRESHOLD_TOKENS
        @pending_trigger = nil
        @last_topic_keywords = Set.new
        @edited_files = Set.new
      end

      # Signal that specs passed after implementation.
      def signal_specs_passed!
        @pending_trigger = :specs_passed
      end

      # Signal that a file was edited (for multi-file tracking).
      def signal_file_edited!(path)
        @edited_files << path
      end

      # Signal that multi-file editing is complete.
      def signal_edit_batch_complete!
        return unless @edited_files.size > 1

        @pending_trigger = :multi_file_edit_complete
        @edited_files.clear
      end

      # Detect topic switch from user message keywords.
      def detect_topic_switch(user_message)
        keywords = extract_keywords(user_message)
        overlap = keywords & @last_topic_keywords

        @pending_trigger = :topic_switch if @last_topic_keywords.any? && overlap.empty? && keywords.any?

        @last_topic_keywords = keywords
      end

      # Check if compaction should run based on decision boundaries.
      # Returns true if compaction was triggered.
      def check!(conversation) # rubocop:disable Naming/PredicateMethod -- side-effectful: triggers compaction, not just a query
        return false unless should_compact?(conversation)

        trigger = @pending_trigger
        @pending_trigger = nil
        RubynCode::Debug.token("Decision compaction triggered: #{trigger}")
        @context_manager.check_compaction!(conversation)
        true
      end

      # Reset all tracked state.
      def reset!
        @pending_trigger = nil
        @last_topic_keywords.clear
        @edited_files.clear
      end

      STOPWORDS = %w[the and for this that with from have been will your what].to_set.freeze

      private

      def should_compact?(conversation)
        return false unless @pending_trigger

        est = @context_manager.estimated_tokens(conversation.messages)
        est > (@threshold * EARLY_COMPACT_RATIO)
      end

      def extract_keywords(text)
        text.to_s.downcase
            .scan(/\b[a-z]{3,}\b/)
            .reject { |w| stopword?(w) }
            .to_set
      end

      def stopword?(word)
        STOPWORDS.include?(word)
      end
    end
  end
end
