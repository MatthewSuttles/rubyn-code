# frozen_string_literal: true

require 'json'
require 'time'

module RubynCode
  module Learning
    # Injects relevant learned instincts into the system prompt so the agent
    # can leverage past experience for the current project and context.
    module Injector
      # Minimum confidence score for an instinct to be included.
      MIN_CONFIDENCE = 0.3

      # Default maximum number of instincts to inject.
      DEFAULT_MAX_INSTINCTS = 10

      INSTINCTS_TABLE = 'instincts'

      class << self
        # Queries and formats relevant instincts for system prompt injection.
        #
        # @param db [DB::Connection] the database connection
        # @param project_path [String] the project root path
        # @param context_tags [Array<String>] optional tags to filter by
        # @param max_instincts [Integer] maximum number of instincts to include
        # @return [String] formatted instincts block, or empty string if none found
        def call(db:, project_path:, context_tags: [], max_instincts: DEFAULT_MAX_INSTINCTS)
          rows = fetch_instincts(db, project_path)
          return '' if rows.empty?

          instincts = rows.map { |row| row_to_instinct(row) }

          # Apply time-based decay to get current confidence
          now = Time.now
          instincts = instincts.map { |inst| InstinctMethods.apply_decay(inst, now) }

          # Filter below minimum confidence
          instincts = instincts.select { |inst| inst.confidence >= MIN_CONFIDENCE }

          # Filter by context tags if provided
          instincts = filter_by_tags(instincts, context_tags) unless context_tags.empty?

          # Sort by confidence descending and take top N
          instincts = instincts
                      .sort_by { |inst| -inst.confidence }
                      .first(max_instincts)

          return '' if instincts.empty?

          format_instincts(instincts)
        end

        private

        def fetch_instincts(db, project_path)
          db.query(
            "SELECT * FROM #{INSTINCTS_TABLE} WHERE project_path = ? AND confidence >= ?",
            [project_path, MIN_CONFIDENCE]
          ).to_a
        rescue StandardError => e
          warn "[Learning::Injector] Failed to query instincts: #{e.message}"
          []
        end

        def row_to_instinct(row)
          Instinct.new(
            id: row['id'],
            project_path: row['project_path'],
            pattern: row['pattern'],
            context_tags: parse_tags(row['context_tags']),
            confidence: row['confidence'].to_f,
            decay_rate: row['decay_rate'].to_f,
            times_applied: row['times_applied'].to_i,
            times_helpful: row['times_helpful'].to_i,
            created_at: parse_time(row['created_at']),
            updated_at: parse_time(row['updated_at'])
          )
        end

        def parse_tags(tags)
          case tags
          when String
            begin
              JSON.parse(tags)
            rescue JSON::ParserError
              tags.split(',').map(&:strip)
            end
          when Array
            tags
          else
            []
          end
        end

        def parse_time(value)
          case value
          when Time
            value
          when String
            Time.parse(value)
          else
            Time.now
          end
        end

        # Filters instincts to those that share at least one tag with the
        # requested context tags.
        #
        # @param instincts [Array<Instinct>] candidate instincts
        # @param tags [Array<String>] required context tags
        # @return [Array<Instinct>] filtered instincts
        def filter_by_tags(instincts, tags)
          tag_set = tags.to_set(&:downcase)

          instincts.select do |inst|
            inst_tags = inst.context_tags.map(&:downcase)
            inst_tags.any? { |t| tag_set.include?(t) }
          end
        end

        # Formats instincts into a block suitable for system prompt injection.
        #
        # @param instincts [Array<Instinct>] the instincts to format
        # @return [String] formatted instincts block
        def format_instincts(instincts)
          lines = instincts.map do |inst|
            label = InstinctMethods.confidence_label(inst.confidence)
            rounded = inst.confidence.round(2)
            "- #{inst.pattern} (confidence: #{rounded}, #{label})"
          end

          "<instincts>\n#{lines.join("\n")}\n</instincts>"
        end
      end
    end
  end
end
