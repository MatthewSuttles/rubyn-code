# frozen_string_literal: true

require 'json'
require 'securerandom'

# Eager-load so LLM::TextBlock / LLM::ToolUseBlock constants resolve at
# class definition time — we reference them directly in `assistant_turn_blocks`
# before any MessageBuilder call has had a chance to trigger autoload.
require_relative '../llm/message_builder'

module RubynCode
  module Megaplan
    # Drives a multi-turn LLM conversation that gathers enough context to
    # produce a megaplan. The model has a small whitelist of READ-ONLY
    # tools (read_file, grep, glob, git_status, git_diff, git_log) so it
    # can inspect the codebase before asking sharper questions — but it
    # cannot edit, run shell mutations, or call any side-effecting tool.
    #
    # Each interview turn ends in one of two JSON shapes:
    #
    #   { "question": { "text": "...", "options": ["a", "b"] | null } }
    #   { "plan": { "slug": ..., "feature": ..., "phases": [...] } }
    #
    # Validation of the plan payload is delegated to PlanProposer's
    # existing rules so both /megaplan paths stay consistent.
    class InterviewSession
      class InvalidAnswerError < RubynCode::Error; end
      class MalformedResponseError < RubynCode::Error; end

      Question = Data.define(:id, :text, :options) do
        def open? = options.nil? || options.empty?
      end

      # The megaplan skill lives in the gem's shared skill catalog
      # (skills/megaplan/megaplan.md) so it's also reachable as
      # `/skill megaplan` from the REPL and the chat. We load the file
      # body directly (skipping the YAML frontmatter) for the system
      # prompt.
      SKILL_PATH = File.expand_path('../../../skills/megaplan/megaplan.md', __dir__)

      def self.load_skill_body
        raw = File.read(SKILL_PATH)
        raw.sub(/\A---\s*\n.+?\n---\s*\n/m, '')
      end

      # Whitelist of read-only tools the interviewer may call. Picked from
      # the existing Tools::Registry by name. Anything that writes, runs
      # shell mutations, or spawns sub-agents is intentionally excluded.
      INTERVIEW_TOOLS = %w[
        read_file
        glob
        grep
        git_status
        git_diff
        git_log
      ].freeze

      # Safety cap on the interview's per-turn tool loop. A well-behaved
      # interviewer should read at most a handful of files before asking
      # its next question; this stops a runaway model from stalling the
      # session indefinitely. Per-turn, not per-session.
      MAX_TOOL_TURNS = 10

      # Strict output contract bolted on top of the megaplan skill body.
      # The skill teaches *what* a megaplan is and *how* to interview; this
      # contract teaches the LLM the wire format the gem expects on every
      # turn AND that its tool palette is read-only.
      JSON_OUTPUT_CONTRACT = <<~CONTRACT
        # Output contract (overrides any other formatting instinct)

        You are an interviewer, not a coding agent. You have a READ-ONLY
        tool palette: `read_file`, `glob`, `grep`, `git_status`, `git_diff`,
        `git_log`. Use them sparingly — only when looking at the code would
        let you ask a SHARPER question (e.g. confirming a column already
        exists before asking about it). You must NOT edit, write, run
        shell mutations, or call any other tool. There are no other tools
        available.

        After any tool use, your next message must be a single JSON object
        — no markdown fences, no prose before or after — in one of these
        two shapes:

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
            topics already obvious from context — including anything you've
            confirmed via a read-only tool.
          - Stop interviewing when you're 95% sure of the shape; emit the plan.

        Plan rules:
          - 1 to 12 phases. Each phase is a vertical slice that ships independently.
          - Trunk works at every phase boundary.
          - tasks_md uses `[ ]` checkboxes; requirements_md uses EARS-style SHALL
            statements when phrasing acceptance criteria.

        When you emit your final answer for a turn (a question or a plan),
        produce ONLY the JSON object. No prefatory text. No trailing
        commentary. Never produce free-form coding-agent output.
      CONTRACT

      DEFAULT_INTERVIEW_PROMPT = "#{load_skill_body}\n\n#{JSON_OUTPUT_CONTRACT}".freeze

      attr_reader :session_id

      def initialize(llm_client: nil, system_prompt: nil, workspace_path: nil, executor: nil)
        @llm_client = llm_client || LLM::Client.new
        @system_prompt = system_prompt || DEFAULT_INTERVIEW_PROMPT
        @session_id = SecureRandom.uuid
        @history = []
        @last_question = nil
        @workspace_path = workspace_path || Dir.pwd
        @executor = executor || Tools::Executor.new(project_root: @workspace_path)
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

        MAX_TOOL_TURNS.times do
          response = @llm_client.chat(
            messages: @history,
            system: @system_prompt,
            tools: interview_tool_definitions
          )

          tool_calls = response.respond_to?(:tool_calls) ? response.tool_calls : []
          if tool_calls.any?
            @history << assistant_turn_blocks(response)
            @history << tool_results_turn(tool_calls)
            next
          end

          text = extract_text(response)
          @history << { role: 'assistant', content: text }
          return parse_outcome(text)
        end

        raise MalformedResponseError,
              "Interview tool loop exceeded #{MAX_TOOL_TURNS} turns without producing a question or plan"
      end

      def interview_tool_definitions
        @executor.tool_definitions.select do |defn|
          INTERVIEW_TOOLS.include?(defn[:name].to_s)
        end
      end

      def assistant_turn_blocks(response)
        blocks = response.content.filter_map do |block|
          case block
          when LLM::TextBlock
            { type: 'text', text: block.text }
          when LLM::ToolUseBlock
            { type: 'tool_use', id: block.id, name: block.name, input: block.input }
          end
        end
        { role: 'assistant', content: blocks }
      end

      def tool_results_turn(tool_calls)
        content = tool_calls.map do |call|
          result = if INTERVIEW_TOOLS.include?(call.name.to_s)
                     @executor.execute(call.name, stringify_keys(call.input))
                   else
                     unavailable_tool_message(call.name)
                   end
          { type: 'tool_result', tool_use_id: call.id, content: result.to_s }
        end
        { role: 'user', content: content }
      end

      def unavailable_tool_message(name)
        "Tool '#{name}' is not available in interview mode " \
          "(read-only palette: #{INTERVIEW_TOOLS.join(', ')})."
      end

      def stringify_keys(input)
        return input unless input.is_a?(Hash)

        input.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
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
