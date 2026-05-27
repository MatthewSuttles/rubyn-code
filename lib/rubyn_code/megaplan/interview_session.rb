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

      DEFAULT_INTERVIEW_PROMPT = <<~PROMPT.freeze
        You are a senior Ruby/Rails architect interviewing a developer to plan a
        multi-phase feature delivery (a "megaplan"). Your job is to ask sharp,
        one-at-a-time questions until you have enough to produce a vertical-slice
        plan, then output the plan.

        On EVERY turn, respond with a single JSON object — no markdown fences,
        no commentary — in exactly one of these two shapes:

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
          - Lead with the goal in user-facing terms, then constraints, then existing
            assets, then ordering, then test strategy, then per-phase done criteria.
          - Skip topics the user has already covered.

        Plan rules:
          - 1 to 12 phases. Each phase is a vertical slice that ships independently.
          - Trunk works at every phase boundary.
          - tasks_md uses `[ ]` checkboxes; requirements_md uses EARS-style SHALL
            statements when phrasing acceptance criteria.
          - Emit the plan when (and only when) you have a clear vertical-slice
            breakdown. Don't pad with filler questions.

        Output ONLY the JSON object. No prefatory text. No trailing commentary.
      PROMPT

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
        response = @llm_client.chat(messages: @history, system: @system_prompt)
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
