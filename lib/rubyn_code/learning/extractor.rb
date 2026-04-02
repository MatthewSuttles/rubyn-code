# frozen_string_literal: true

require "json"
require "securerandom"

module RubynCode
  module Learning
    # Extracts reusable patterns from session messages using an LLM.
    #
    # After a session, the extractor sends recent conversation history to a
    # cheaper model (Haiku) and asks it to identify patterns that could be
    # useful in future sessions for the same project.
    module Extractor
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

      EXTRACTION_PROMPT = <<~PROMPT
        Analyze the following conversation between a developer and an AI coding assistant.
        Extract reusable patterns that could help in future sessions for this project.

        For each pattern, provide:
        - type: one of #{VALID_TYPES.join(', ')}
        - pattern: a concise description of the learned behavior or fix
        - context_tags: relevant tags (e.g., framework names, error types, file patterns)
        - confidence: initial confidence score between 0.3 and 0.8

        Respond with a JSON array of objects. If no patterns are found, respond with [].
        Only extract patterns that are genuinely reusable, not one-off fixes.

        Example response:
        [
          {
            "type": "error_resolution",
            "pattern": "When seeing 'PG::UniqueViolation' on users.email, check for missing unique index migration",
            "context_tags": ["postgresql", "rails", "migration"],
            "confidence": 0.6
          }
        ]
      PROMPT

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

        private

        def request_extraction(messages, llm_client)
          # Serialize conversation into a single user message to avoid
          # "must end with user message" errors
          transcript = messages.map { |m|
            role = (m[:role] || m["role"] || "unknown").capitalize
            content = m[:content] || m["content"]
            text = case content
                   when String then content
                   when Array
                     content.filter_map { |b|
                       b.respond_to?(:text) ? b.text : (b[:text] || b["text"])
                     }.join("\n")
                   else content.to_s
                   end
            "#{role}: #{text}"
          }.join("\n\n")

          llm_client.chat(
            messages: [{ role: "user", content: "#{EXTRACTION_PROMPT}\n\nConversation:\n#{transcript}" }],
            max_tokens: 2000
          )
        rescue StandardError => e
          warn "[Learning::Extractor] LLM extraction failed: #{e.message}"
          nil
        end

        def save_to_db(instincts)
          db = DB::Connection.instance
          now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

          instincts.each do |inst|
            db.execute(
              "INSERT INTO instincts (id, project_path, pattern, context_tags, confidence, decay_rate, times_applied, times_helpful, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
              [
                SecureRandom.uuid,
                inst[:project_path],
                inst[:pattern],
                JSON.generate(inst[:context_tags]),
                inst[:confidence],
                inst[:decay_rate],
                inst[:times_applied],
                inst[:times_helpful],
                now,
                now
              ]
            )
          end
        rescue StandardError => e
          warn "[Learning::Extractor] Failed to save instincts: #{e.message}"
        end

        def parse_response(response)
          return [] if response.nil?

          text = extract_text(response)
          return [] if text.nil? || text.empty?

          # Extract JSON array from response, handling markdown code blocks
          json_str = text[/\[.*\]/m]
          return [] if json_str.nil?

          parsed = JSON.parse(json_str)
          return [] unless parsed.is_a?(Array)

          parsed
        rescue JSON::ParserError => e
          warn "[Learning::Extractor] Failed to parse extraction response: #{e.message}"
          []
        end

        def extract_text(response)
          if response.respond_to?(:content)
            block = response.content.find { |b| b.respond_to?(:text) }
            block&.text
          elsif response.is_a?(Hash)
            response.dig("content", 0, "text")
          end
        end

        def normalize_pattern(raw, project_path)
          type = raw["type"].to_s
          pattern = raw["pattern"].to_s.strip
          context_tags = Array(raw["context_tags"]).map(&:to_s)
          confidence = raw["confidence"].to_f

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

        # Different pattern types decay at different rates.
        # Project-specific knowledge decays slower; workarounds decay faster.
        def decay_rate_for_type(type)
          case type
          when "project_specific"     then 0.02
          when "error_resolution"     then 0.03
          when "debugging_technique"  then 0.04
          when "user_correction"      then 0.05
          when "workaround"           then 0.07
          else 0.05
          end
        end
      end
    end
  end
end
