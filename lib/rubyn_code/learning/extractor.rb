# frozen_string_literal: true

require 'json'
require 'securerandom'

module RubynCode
  module Learning
    # Extracts reusable patterns from session messages using an LLM.
    #
    # After a session, the extractor sends recent conversation history to a
    # cheaper model (Haiku) and asks it to identify patterns that could be
    # useful in future sessions for the same project.
    module Extractor # rubocop:disable Metrics/ModuleLength -- LLM extraction logic with DB persistence
      # Maximum number of recent messages to analyze.
      MESSAGE_WINDOW = 30

      # Valid pattern types that the LLM is asked to produce.
      VALID_TYPES = %w[
        error_resolution
        user_correction
        workaround
        debugging_technique
        project_specific
      ].freeze

      EXTRACTION_PROMPT = "Analyze the following conversation between a developer and an AI coding assistant.\n" \
                          "Extract reusable patterns that could help in future sessions for this project.\n\n" \
                          "For each pattern, provide:\n" \
                          "- type: one of #{VALID_TYPES.join(', ')}\n" \
                          "- pattern: a concise description of the learned behavior or fix\n" \
                          "- context_tags: relevant tags (e.g., framework names, error types, file patterns)\n" \
                          "- confidence: initial confidence score between 0.3 and 0.8\n\n" \
                          "Respond with a JSON array of objects. If no patterns are found, respond with [].\n" \
                          'Only extract patterns that are genuinely reusable, not one-off fixes.'.freeze

      class << self
        # Extracts instinct patterns from a session's message history.
        #
        # @param messages [Array<Hash>] the conversation messages
        # @param llm_client [LLM::Client] the LLM client for extraction
        # @param project_path [String] the project root path
        # @return [Array<Hash>] extracted instinct hashes ready for persistence
        def call(messages, llm_client:, project_path:)
          recent = messages.last(MESSAGE_WINDOW)
          return [] if recent.empty?

          response = request_extraction(recent, llm_client)
          raw_patterns = parse_response(response)

          instincts = raw_patterns.filter_map do |raw|
            normalize_pattern(raw, project_path)
          end

          save_to_db(instincts) unless instincts.empty?

          instincts
        end

        DECAY_RATES = {
          'project_specific' => 0.02,
          'error_resolution' => 0.03,
          'debugging_technique' => 0.04,
          'user_correction' => 0.05,
          'workaround' => 0.07
        }.freeze

        private

        def request_extraction(messages, llm_client)
          transcript = serialize_transcript(messages)

          llm_client.chat(
            messages: [{ role: 'user', content: "#{EXTRACTION_PROMPT}\n\nConversation:\n#{transcript}" }],
            max_tokens: 2000
          )
        rescue StandardError => e
          warn "[Learning::Extractor] LLM extraction failed: #{e.message}"
          nil
        end

        def serialize_transcript(messages)
          messages.map { |m| format_turn(m) }.join("\n\n")
        end

        def format_turn(msg) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- content polymorphism
          role = (msg[:role] || msg['role'] || 'unknown').capitalize
          content = msg[:content] || msg['content']
          text = if content.is_a?(Array)
                   content.filter_map do |b|
                     b.respond_to?(:text) ? b.text : (b[:text] || b['text'])
                   end.join("\n")
                 else
                   content.to_s
                 end
          "#{role}: #{text}"
        end

        def save_to_db(instincts)
          db = DB::Connection.instance
          now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

          instincts.each { |inst| insert_instinct(db, inst, now) }
        rescue StandardError => e
          warn "[Learning::Extractor] Failed to save instincts: #{e.message}"
        end

        def insert_instinct(db, inst, now)
          db.execute(
            <<~SQL.tr("\n", ' ').strip,
              INSERT INTO instincts (id, project_path, pattern, context_tags,
                confidence, decay_rate, times_applied, times_helpful,
                created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            SQL
            [
              SecureRandom.uuid, inst[:project_path], inst[:pattern],
              JSON.generate(inst[:context_tags]), inst[:confidence],
              inst[:decay_rate], inst[:times_applied], inst[:times_helpful],
              now, now
            ]
          )
        end

        def parse_response(response) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- response parsing with multiple fallbacks
          return [] if response.nil?

          text = if response.respond_to?(:content)
                   response.content.find do |b|
                     b.respond_to?(:text)
                   end&.text
                 else
                   response.is_a?(Hash) ? response.dig('content', 0, 'text') : nil
                 end
          return [] if text.nil? || text.empty?

          json_str = text[/\[.*\]/m]
          return [] unless json_str

          parsed = JSON.parse(json_str)
          parsed.is_a?(Array) ? parsed : []
        rescue JSON::ParserError => e
          warn "[Learning::Extractor] Failed to parse extraction response: #{e.message}"
          []
        end

        def normalize_pattern(raw, project_path)
          type = raw['type'].to_s
          pattern = raw['pattern'].to_s.strip
          context_tags = Array(raw['context_tags']).map(&:to_s)
          confidence = raw['confidence'].to_f

          return nil if pattern.empty?
          return nil unless VALID_TYPES.include?(type)

          confidence = confidence.clamp(0.3, 0.8)

          {
            project_path: project_path,
            pattern: "[#{type}] #{pattern}",
            context_tags: context_tags,
            confidence: confidence,
            decay_rate: decay_rate_for_type(type),
            times_applied: 0,
            times_helpful: 0
          }
        end

        def decay_rate_for_type(type)
          DECAY_RATES.fetch(type, 0.05)
        end
      end
    end
  end
end
