  # frozen_string_literal: true

require 'json'
require 'securerandom'

module RubynCode
  module Megaplan
    # Proposes a multi-phase megaplan for a feature description.
    #
    # Asks the LLM to produce a JSON payload that matches the extension's
    # `plan_proposal` shape — one folder per phase, three documents per
    # phase, vertical-slice ordering. The handler validates the response
    # and returns it to the IDE.
    #
    # The LLM call is the slow part (~5-30s); callers should run this
    # off the main JSON-RPC thread.
    class PlanProposer
      class InvalidProposalError < RubynCode::Error; end

      MAX_PHASES = 12
      DEFAULT_SYSTEM_PROMPT = <<~PROMPT.freeze
        You are a senior Ruby/Rails architect breaking a feature request into a megaplan.

        A megaplan is a multi-phase development plan where each phase is a
        VERTICAL SLICE that can ship independently. Trunk works at every phase
        boundary. No "scaffolding first, behavior later" — every phase delivers
        a thin, end-to-end working increment.

        Output a single JSON object with this exact shape:

        {
          "slug": "kebab-case-feature-slug",
          "feature": "Short feature description",
          "phases": [
            {
              "number": 1,
              "slug": "kebab-case-phase-slug",
              "name": "Human-readable phase name",
              "summary": "One-sentence summary of what this phase ships",
              "requirements_md": "# Phase 1 — <name>: Requirements\\n\\n...",
              "design_md":       "# Phase 1 — <name>: Design\\n\\n...",
              "tasks_md":        "# Phase 1 — <name>: Tasks\\n\\n## [ ] 1. ...\\n\\n- [ ] 1.1 ..."
            }
          ]
        }

        Constraints:
          - 1 to 12 phases. Smaller, sharper phases beat fewer mega-phases.
          - Each phase must be a vertical slice.
          - tasks_md is a checklist with `[ ]` boxes (megaplan convention).
          - Every phase needs requirements_md, design_md, tasks_md.
          - Return ONLY the JSON. No markdown fences. No commentary.
      PROMPT

      def initialize(llm_client: nil, system_prompt: nil, max_phases: MAX_PHASES)
        @llm_client = llm_client || LLM::Client.new
        @system_prompt = system_prompt || DEFAULT_SYSTEM_PROMPT
        @max_phases = max_phases
      end

      # @param feature [String] the user's feature description
      # @return [Hash] payload with `slug`, `feature`, `phases`
      # @raise [InvalidProposalError] if the LLM response can't be parsed
      def propose(feature)
        raise ArgumentError, 'feature is required' if feature.nil? || feature.strip.empty?

        response = @llm_client.chat(
          messages: [{ role: 'user', content: feature_prompt(feature) }],
          system: @system_prompt
        )

        text = extract_text(response)
        payload = parse_payload(text)
        validate!(payload, feature)
        normalize(payload, feature)
      end

      # Validate a parsed plan_proposal Hash. Public so the interview path
      # (which produces the same shape via a different LLM workflow) can
      # reuse the rule set without reaching into a private method.
      def validate!(payload, _feature = nil)
        raise InvalidProposalError, 'payload is not an object' unless payload.is_a?(Hash)

        phases = payload['phases']
        raise InvalidProposalError, 'phases must be an array' unless phases.is_a?(Array)
        raise InvalidProposalError, 'phases is empty' if phases.empty?
        raise InvalidProposalError, "too many phases (max #{@max_phases})" if phases.size > @max_phases

        phases.each_with_index do |phase, idx|
          %w[name summary requirements_md design_md tasks_md].each do |key|
            next unless phase[key].nil? || phase[key].to_s.strip.empty?

            raise InvalidProposalError, "phase #{idx + 1} missing #{key}"
          end
        end
      end

      private

      # LLM::Client#chat returns a `LLM::Response` Data object whose `.text`
      # joins all text blocks. Tests and older callers may pass a String or
      # a Hash — handle all three so the proposer doesn't crash with
      # `#<data ...>` ending up as parser input.
      def extract_text(response)
        return response.text if response.respond_to?(:text) && !response.is_a?(String)
        return response[:text] || response['text'] if response.is_a?(Hash)

        response.to_s
      end

      def feature_prompt(feature)
        "Plan this feature as a megaplan:\n\n#{feature.strip}"
      end

      def parse_payload(text)
        # The LLM can leak fences despite the prompt — strip a leading/trailing
        # ``` block if present.
        cleaned = text.to_s.strip
        cleaned = cleaned.sub(/\A```(?:json)?\s*\n?/, '').sub(/\n?```\s*\z/, '')
        JSON.parse(cleaned)
      rescue JSON::ParserError => e
        raise InvalidProposalError, "LLM response is not valid JSON: #{e.message}"
      end

      def normalize(payload, feature)
        slug = payload['slug'].to_s.strip
        slug = slugify(feature) if slug.empty?
        phases = payload['phases'].each_with_index.map do |phase, idx|
          {
            'number' => phase['number'] || idx + 1,
            'slug' => (phase['slug'].to_s.strip.empty? ? slugify(phase['name']) : phase['slug']),
            'name' => phase['name'],
            'summary' => phase['summary'],
            'requirements_md' => phase['requirements_md'],
            'design_md' => phase['design_md'],
            'tasks_md' => phase['tasks_md']
          }
        end
        {
          'slug' => slug,
          'feature' => payload['feature'] || feature,
          'phases' => phases
        }
      end

      def slugify(text)
        cleaned = text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')
        cleaned = cleaned[0, 80]
        cleaned.empty? ? 'feature' : cleaned
      end
    end
  end
end
