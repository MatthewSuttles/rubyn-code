  # frozen_string_literal: true

require 'json'
require 'securerandom'

module RubynCode
  module Megaplan
    # Drives a multi-turn LLM conversation that gathers enough context to
    # produce a megaplan. Each turn the LLM emits one of two JSON shapes:
    #
    #   { "question": { "text": "...", "options": ["a", "b"] | null } }
    #   { "plan": { "slug": ..., "feature": ..., "phases": [...] } }
    #
    # The session ends when the LLM emits a plan or the caller cancels.
    # Validation of the plan payload is delegated to PlanProposer's
    # existing rules so both /megaplan paths stay consistent.
    class InterviewSession
      class InvalidAnswerError < RubynCode::Error; end
      class MalformedResponseError < RubynCode::Error; end

      Question = Data.define(:id, :text, :options) do
        def open? = options.nil? || options.empty?
      end

      SKILL_PATH = File.expand_path('megaplan_skill.md', __dir__)

      # Strict output contract bolted on top of the megaplan skill body.
      # The skill teaches *what* a megaplan is and *how* to interview; this
      # contract teaches the LLM the wire format the gem expects on every
      # turn. Drift means the JSON parser rejects the response and the
      # interview surfaces an error.
      JSON_OUTPUT_CONTRACT = <<~CONTRACT.freeze
        # Output contract (overrides any other formatting instinct)

        You are NOT in a coding session. You do NOT have tools available. You
        must NOT search files, read code, edit, or call any function. Your
        entire job is to either ask the next interview question OR emit the
        final megaplan, by writing a single JSON object.

        On EVERY turn, respond with exactly one JSON object — no markdown
        fences, no prose before or after — in one of these two shapes:

          { "question": { "text": "<one focused question>", "options": ["a", "b", "c"] | null } }

          { "plan": { "slug": "<kebab-case>", "feature": "<short description>",
                      "phases": [{ "number": 1, "slug": "<kebab>", "name": "<name>",
                                   "summary": "<one sentence>",
                                   "requirements_md": "<markdown>",
                                   "design_md": "<markdown>",
                                   "tasks_md": "<markdown>" }, ...] } }

        Interview rules:
          - Ask one question at a time. Never bundle multiple.
          - Prefer numbered options (3-5 choices) when there's an obvious option set.
          - Use null `options` only for genuinely open questions (end-state, constraints prose).
          - Walk the megaplan-skill agenda (goal → constraints → assets → ordering
            → external deps → destructive ops → tests → done-per-phase). Skip
            topics already obvious from context.
          - Stop interviewing when you're 95% sure of the shape; emit the plan.

        Plan rules:
          - 1 to 12 phases. Each phase is a vertical slice that ships independently.
          - Trunk works at every phase boundary.
          - tasks_md uses `[ ]` checkboxes; requirements_md uses EARS-style SHALL
            statements when phrasing acceptance criteria.

        Output ONLY the JSON object. No prefatory text. No trailing commentary.
        Never produce free-form coding-agent output.
      CONTRACT

      DEFAULT_INTERVIEW_PROMPT = "#{File.read(SKILL_PATH)}\n\n#{JSON_OUTPUT_CONTRACT}".freeze

      attr_reader :session_id

      def initialize(llm_client: nil, system_prompt: nil)
        @llm_client = llm_client || LLM::Client.new
        @system_prompt = system_prompt || DEFAULT_INTERVIEW_PROMPT
        @session_id = SecureRandom.uuid
        @history = []
        @last_question = nil
      end

      # Returns a Question to ask the user, or a Hash (validated plan payload)
      # if the LLM jumped straight to the plan.
      def start
        ask_llm('Begin the interview. Ask your first question.')
      end

      # @param question_id [String] echoes back the question's id (anti-race)
      # @param answer_text [String] the user's answer
      # @return [Question, Hash] the next question OR the final plan payload
      def answer(question_id, answer_text)
        raise InvalidAnswerError, 'no question awaiting answer' unless @last_question
        raise InvalidAnswerError, 'wrong question id' unless @last_question.id == question_id

        @history << { role: 'user', content: answer_text.to_s }
        ask_llm(answer_text.to_s)
      end

      private

      def ask_llm(prompt)
        @history << { role: 'user', content: prompt } if @history.empty? || @history.last[:content] != prompt
        # tools: nil + a JSON-only system prompt is how we keep the LLM out
        # of "coding agent" mode. Passing the gem's regular tools here
        # would let the model search/edit instead of conducting the interview.
        response = @llm_client.chat(messages: @history, system: @system_prompt, tools: nil)
        text = extract_text(response)
        @history << { role: 'assistant', content: text }
        parse_outcome(text)
      end

      # Mirrors PlanProposer#extract_text so both /megaplan paths handle
      # LLM::Response Data objects, Hash legacy shapes, and raw Strings.
      def extract_text(response)
        return response.text if response.respond_to?(:text) && !response.is_a?(String)
        return response[:text] || response['text'] if response.is_a?(Hash)

        response.to_s
      end

      def parse_outcome(text)
        cleaned = text.to_s.strip
                      .sub(/\A```(?:json)?\s*\n?/, '')
                      .sub(/\n?```\s*\z/, '')
        payload = JSON.parse(cleaned)
        if payload.is_a?(Hash) && payload['question']
          q = build_question(payload['question'])
          @last_question = q
          q
        elsif payload.is_a?(Hash) && payload['plan']
          plan = payload['plan']
          PlanProposer.new.validate!(plan)
          @last_question = nil
          plan
        else
          raise MalformedResponseError, 'LLM response is neither a question nor a plan'
        end
      rescue JSON::ParserError => e
        raise MalformedResponseError, "LLM response is not valid JSON: #{e.message}"
      end

      def build_question(payload)
        options = payload['options']
        options = nil if options.is_a?(Array) && options.empty?
        Question.new(id: SecureRandom.uuid, text: payload['text'].to_s, options: options)
      end
    end
  end
end
