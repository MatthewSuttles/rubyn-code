# frozen_string_literal: true

require 'json'
require 'time'

module RubynCode
  module Observability
    # Tracks per-skill usage and ROI metrics. Records when skills are loaded,
    # how long they stay in context, whether suggestions from them are accepted,
    # and their token cost. Enables monthly pruning of low-usage skills.
    class SkillAnalytics
      TABLE_NAME = 'skill_usage'

      Entry = Data.define(
        :skill_name, :loaded_at_turn, :last_referenced_turn,
        :tokens_cost, :accepted, :session_id
      )

      attr_reader :entries

      def initialize(db: nil)
        @db = db
        @entries = []
      end

      # Record a skill usage event.
      def record(skill_name:, loaded_at_turn:, last_referenced_turn: nil, tokens_cost: 0, accepted: nil)
        entry = Entry.new(
          skill_name: skill_name.to_s,
          loaded_at_turn: loaded_at_turn,
          last_referenced_turn: last_referenced_turn || loaded_at_turn,
          tokens_cost: tokens_cost.to_i,
          accepted: accepted,
          session_id: nil
        )
        @entries << entry
        persist(entry) if @db
        entry
      end

      # Calculate usage statistics across all recorded entries.
      def usage_stats
        return {} if @entries.empty?

        by_skill = @entries.group_by(&:skill_name)
        by_skill.transform_values do |entries|
          {
            load_count: entries.size,
            total_tokens: entries.sum(&:tokens_cost),
            avg_tokens: (entries.sum(&:tokens_cost).to_f / entries.size).round(0),
            acceptance_rate: acceptance_rate(entries),
            avg_lifespan: avg_lifespan(entries)
          }
        end
      end

      # Returns skills with usage rate below threshold (candidates for pruning).
      def low_usage_skills(threshold: 0.05)
        stats = usage_stats
        total = @entries.size.to_f
        return [] if total.zero?

        stats.select do |_, s|
          (s[:load_count] / total) < threshold
        end.keys
      end

      # Returns skills sorted by ROI (accepted suggestions per token spent).
      def roi_ranking
        stats = usage_stats
        stats.sort_by do |_, s|
          tokens = s[:total_tokens]
          rate = s[:acceptance_rate] || 0
          tokens.positive? ? -(rate / tokens) : 0
        end.map(&:first)
      end

      # Format a report for the /cost command.
      def report
        stats = usage_stats
        return 'No skill usage data.' if stats.empty?

        lines = ['Skill Usage:']
        stats.each do |name, s|
          lines << "  #{name}: #{s[:load_count]}x loaded, #{s[:total_tokens]} tokens"
        end
        lines.join("\n")
      end

      private

      def acceptance_rate(entries)
        rated = entries.reject { |e| e.accepted.nil? }
        return nil if rated.empty?

        (rated.count(&:accepted).to_f / rated.size).round(3)
      end

      def avg_lifespan(entries)
        spans = entries.map { |e| e.last_referenced_turn - e.loaded_at_turn }
        (spans.sum.to_f / spans.size).round(1)
      end

      def persist(entry)
        @db.execute(
          "INSERT INTO #{TABLE_NAME} (skill_name, loaded_at_turn, last_referenced_turn, " \
          'tokens_cost, accepted, created_at) VALUES (?, ?, ?, ?, ?, ?)',
          [entry.skill_name, entry.loaded_at_turn, entry.last_referenced_turn,
           entry.tokens_cost, entry.accepted ? 1 : 0, Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')]
        )
      rescue StandardError => e
        RubynCode::Debug.warn("SkillAnalytics: #{e.message}")
      end
    end
  end
end
