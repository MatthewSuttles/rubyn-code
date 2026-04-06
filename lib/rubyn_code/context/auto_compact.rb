# frozen_string_literal: true

require 'json'
require 'fileutils'

module RubynCode
  module Context
    # LLM-driven summarization triggered automatically when the context window
    # grows too large. Serializes the conversation tail, asks the LLM to produce
    # a continuity summary, and returns a fresh single-message conversation.
    module AutoCompact
      SUMMARY_INSTRUCTION = <<~PROMPT
        You are a context compaction assistant. Summarize the following conversation transcript for continuity. Cover exactly three areas:

        1) **What was accomplished** - completed tasks, files changed, problems solved
        2) **Current state** - what the user/agent is working on right now, any pending actions
        3) **Key decisions made** - architectural choices, user preferences, constraints established

        Be concise but preserve all details needed to continue the work seamlessly. Use bullet points.
      PROMPT

      MAX_TRANSCRIPT_CHARS = 80_000

      # Compacts the conversation by summarizing it through the LLM.
      #
      # @param messages [Array<Hash>] current conversation messages
      # @param llm_client [#chat] an LLM client that responds to #chat
      # @param transcript_dir [String, nil] directory to save full transcript before compaction
      # @return [Array<Hash>] new messages array containing only the summary
      def self.call(messages, llm_client:, transcript_dir: nil)
        save_transcript(messages, transcript_dir) if transcript_dir

        transcript_text = serialize_tail(messages, MAX_TRANSCRIPT_CHARS)
        summary = request_summary(transcript_text, llm_client)

        [{ role: 'user', content: "[Context compacted]\n\n#{summary}" }]
      end

      # Persists the full conversation to a timestamped JSON file.
      def self.save_transcript(messages, dir)
        FileUtils.mkdir_p(dir)
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        path = File.join(dir, "transcript_#{timestamp}.json")
        File.write(path, JSON.pretty_generate(messages))
        path
      end

      # Takes the last +max_chars+ of the JSON-serialized messages.
      def self.serialize_tail(messages, max_chars)
        json = JSON.generate(messages)
        return json if json.length <= max_chars

        json[-max_chars..]
      end

      # Sends the transcript to the LLM for summarization.
      def self.request_summary(transcript_text, llm_client)
        summary_messages = [
          {
            role: 'user',
            content: "#{SUMMARY_INSTRUCTION}\n\n---\n\n#{transcript_text}"
          }
        ]

        options = {}
        options[:model] = 'claude-sonnet-5-4' if llm_client.respond_to?(:chat)

        response = llm_client.chat(messages: summary_messages, **options)

        case response
        when String then response
        when Hash then response[:content] || response['content'] || response.to_s
        else
          response.respond_to?(:text) ? response.text : response.to_s
        end
      end

      private_class_method :save_transcript, :serialize_tail, :request_summary
    end
  end
end
