# frozen_string_literal: true

require "time"

module RubynCode
  module Learning
    # Represents a learned pattern with confidence tracking and time-based decay.
    #
    # Instincts are project-scoped patterns extracted from user sessions that
    # can be injected into future system prompts to improve agent behavior.
    Instinct = Data.define(
      :id,
      :project_path,
      :pattern,
      :context_tags,
      :confidence,
      :decay_rate,
      :times_applied,
      :times_helpful,
      :created_at,
      :updated_at
    ) do
      def initialize(id:, project_path:, pattern:, context_tags: [], confidence: 0.5,
                     decay_rate: 0.05, times_applied: 0, times_helpful: 0,
                     created_at: Time.now, updated_at: Time.now)
        super(
          id: id,
          project_path: project_path,
          pattern: pattern,
          context_tags: Array(context_tags),
          confidence: confidence.to_f.clamp(0.0, 1.0),
          decay_rate: decay_rate.to_f,
          times_applied: times_applied.to_i,
          times_helpful: times_helpful.to_i,
          created_at: created_at,
          updated_at: updated_at
        )
      end
    end

    module InstinctMethods
      # The minimum confidence threshold below which instincts are considered stale.
      MIN_CONFIDENCE = 0.05

      # Confidence label thresholds, checked in descending order.
      CONFIDENCE_LABELS = [
        [0.9, "near-certain"],
        [0.7, "confident"],
        [0.5, "moderate"],
        [0.3, "tentative"]
      ].freeze

      class << self
        # Applies time-based decay to an instinct's confidence score.
        # Confidence decays based on how long it has been since the instinct
        # was last used (updated_at).
        #
        # @param instinct [Instinct] the instinct to decay
        # @param current_time [Time] the reference time for decay calculation
        # @return [Instinct] a new instinct with decayed confidence
        def apply_decay(instinct, current_time)
          elapsed_days = (current_time - instinct.updated_at).to_f / 86_400
          return instinct if elapsed_days <= 0

          decay_factor = Math.exp(-instinct.decay_rate * elapsed_days)
          new_confidence = (instinct.confidence * decay_factor).clamp(MIN_CONFIDENCE, 1.0)

          instinct.with(confidence: new_confidence)
        end

        # Reinforces an instinct by increasing or decreasing confidence
        # based on whether the application was helpful.
        #
        # @param instinct [Instinct] the instinct to reinforce
        # @param helpful [Boolean] whether the instinct was helpful this time
        # @return [Instinct] a new instinct with updated confidence and counters
        def reinforce(instinct, helpful: true)
          new_applied = instinct.times_applied + 1

          if helpful
            new_helpful = instinct.times_helpful + 1
            boost = 0.1 * (1.0 - instinct.confidence) # Diminishing returns
            new_confidence = (instinct.confidence + boost).clamp(0.0, 1.0)
          else
            new_helpful = instinct.times_helpful
            penalty = 0.15 * instinct.confidence # Proportional penalty
            new_confidence = (instinct.confidence - penalty).clamp(MIN_CONFIDENCE, 1.0)
          end

          instinct.with(
            confidence: new_confidence,
            times_applied: new_applied,
            times_helpful: new_helpful,
            updated_at: Time.now
          )
        end

        # Returns a human-readable label for a confidence score.
        #
        # @param score [Float] the confidence score (0.0 to 1.0)
        # @return [String] one of "near-certain", "confident", "moderate",
        #   "tentative", or "unreliable"
        def confidence_label(score)
          CONFIDENCE_LABELS.each do |(threshold, label)|
            return label if score >= threshold
          end

          "unreliable"
        end

        # Reinforces an instinct in the database by updating confidence
        # and counters based on whether the application was helpful.
        #
        # @param instinct_id [String] the instinct ID in the database
        # @param db [DB::Connection] the database connection
        # @param helpful [Boolean] whether the instinct was helpful
        # @return [void]
        def reinforce_in_db(instinct_id, db, helpful: true)
          now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

          if helpful
            db.execute(
              "UPDATE instincts SET confidence = MIN(1.0, confidence + 0.1 * (1.0 - confidence)), times_applied = times_applied + 1, times_helpful = times_helpful + 1, updated_at = ? WHERE id = ?",
              [now, instinct_id]
            )
          else
            db.execute(
              "UPDATE instincts SET confidence = MAX(#{MIN_CONFIDENCE}, confidence - 0.15 * confidence), times_applied = times_applied + 1, updated_at = ? WHERE id = ?",
              [now, instinct_id]
            )
          end
        rescue StandardError => e
          warn "[Learning::InstinctMethods] Failed to reinforce instinct #{instinct_id}: #{e.message}"
        end

        # Applies time-based decay to all instincts in the database for a given
        # project, removing any that fall below minimum confidence.
        #
        # @param db [DB::Connection] the database connection
        # @param project_path [String] the project root path
        # @return [void]
        def decay_all(db, project_path:)
          rows = db.query(
            "SELECT id, confidence, decay_rate, updated_at FROM instincts WHERE project_path = ?",
            [project_path]
          ).to_a

          now = Time.now
          rows.each do |row|
            updated_at = Time.parse(row["updated_at"].to_s) rescue Time.now
            elapsed_days = (now - updated_at).to_f / 86_400
            next if elapsed_days <= 0

            decay_factor = Math.exp(-row["decay_rate"].to_f * elapsed_days)
            new_confidence = (row["confidence"].to_f * decay_factor).clamp(MIN_CONFIDENCE, 1.0)

            if new_confidence <= MIN_CONFIDENCE
              db.execute("DELETE FROM instincts WHERE id = ?", [row["id"]])
            else
              db.execute(
                "UPDATE instincts SET confidence = ? WHERE id = ?",
                [new_confidence, row["id"]]
              )
            end
          end
        rescue StandardError => e
          warn "[Learning::InstinctMethods] Failed to decay instincts: #{e.message}"
        end
      end
    end
  end
end
