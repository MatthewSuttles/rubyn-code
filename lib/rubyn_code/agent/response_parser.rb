# frozen_string_literal: true

require_relative 'usage_tracker'

module RubynCode
  module Agent
    # Extracts and interprets content from LLM responses: tool calls, text
    # blocks, truncation detection, and multi-turn recovery.
    module ResponseParser
      include UsageTracker

      private

      def extract_tool_calls(response)
        get_content(response).select { |block| block_type(block) == 'tool_use' }
      end

      def response_content(response)
        get_content(response)
      end

      def extract_response_text(response)
        get_content(response)
          .select { |b| block_type(b) == 'text' }
          .map { |b| text_from_block(b) }
          .compact.join("\n")
      end

      def text_from_block(block)
        block.respond_to?(:text) ? block.text : (block[:text] || block['text'])
      end

      def get_content(response)
        case response
        when ->(r) { r.respond_to?(:content) }
          Array(response.content)
        when Hash
          Array(response[:content] || response['content'])
        else
          []
        end
      end

      def block_type(block)
        if block.respond_to?(:type)
          block.type.to_s
        elsif block.is_a?(Hash)
          (block[:type] || block['type']).to_s
        end
      end

      def truncated?(response)
        extract_stop_reason(response) == 'max_tokens'
      end

      def extract_stop_reason(response)
        if response.respond_to?(:stop_reason)
          response.stop_reason
        elsif response.is_a?(Hash)
          response[:stop_reason] || response['stop_reason']
        end
      end

      def recover_truncated_response(response)
        @max_tokens_override ||= Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS
        @conversation.add_assistant_message(response_content(response))
        max_retries = Config::Defaults::MAX_OUTPUT_TOKENS_RECOVERY_LIMIT

        max_retries.times do |attempt|
          response = attempt_recovery(attempt, max_retries)
          break unless truncated?(response)

          RubynCode::Debug.recovery("Still truncated after attempt #{attempt + 1}")
          @conversation.add_assistant_message(response_content(response))
        end

        log_exhausted(max_retries) if truncated?(response)
        response
      end

      def attempt_recovery(attempt, max_retries)
        @output_recovery_count += 1
        RubynCode::Debug.recovery("Tier 2: Recovery attempt #{attempt + 1}/#{max_retries}")
        @conversation.add_user_message(
          'Output token limit hit. Resume directly — no apology, no recap, just continue exactly where you left off.'
        )
        response = call_llm
        RubynCode::Debug.recovery("Recovery successful on attempt #{attempt + 1}") unless truncated?(response)
        response
      end

      def log_exhausted(max_retries)
        RubynCode::Debug.recovery("Tier 3: Exhausted #{max_retries} recovery attempts, returning partial response")
      end

      def field(obj, key)
        if obj.respond_to?(key)
          obj.send(key)
        elsif obj.is_a?(Hash)
          obj[key] || obj[key.to_s]
        end
      end

      def symbolize_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym)
      end
    end
  end
end
