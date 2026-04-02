# frozen_string_literal: true

module RubynCode
  module Agent
    class Conversation
      attr_reader :messages

      def initialize
        @messages = []
      end

      # Append a user turn to the conversation.
      #
      # @param content [String]
      # @return [Hash] the appended message
      def add_user_message(content)
        message = { role: "user", content: content }
        @messages << message
        message
      end

      # Append an assistant turn to the conversation.
      #
      # @param content [Array<Hash>, String, nil] text blocks from the response
      # @param tool_calls [Array<Hash>] tool_use blocks from the response
      # @return [Hash] the appended message
      def add_assistant_message(content, tool_calls: [])
        blocks = normalize_content(content, tool_calls)
        message = { role: "assistant", content: blocks }
        @messages << message
        message
      end

      # Append a tool result turn to the conversation.
      #
      # @param tool_use_id [String]
      # @param tool_name [String]
      # @param output [String]
      # @param is_error [Boolean]
      # @return [Hash] the appended message
      def add_tool_result(tool_use_id, tool_name, output, is_error: false)
        result_block = {
          type: "tool_result",
          tool_use_id: tool_use_id,
          content: output.to_s
        }
        result_block[:is_error] = true if is_error

        # The Claude API expects tool results as a user message whose content
        # is an array of tool_result blocks.  When the previous message is
        # already a user/tool_result message we append to it so that multiple
        # tool results for the same assistant turn are batched together.
        if @messages.last && @messages.last[:role] == "user" && tool_result_message?(@messages.last)
          @messages.last[:content] << result_block
        else
          @messages << { role: "user", content: [result_block] }
        end

        result_block
      end

      # Extract the text from the most recent assistant message.
      #
      # @return [String, nil]
      def last_assistant_text
        assistant_msg = @messages.reverse_each.find { |m| m[:role] == "assistant" }
        return nil unless assistant_msg

        extract_text(assistant_msg[:content])
      end

      # @return [Integer]
      def length
        @messages.length
      end

      # Reset the conversation to an empty state.
      #
      # @return [void]
      def clear!
        @messages.clear
      end

      # Return the messages array formatted for the Claude API.
      # Ensures proper role alternation and content structure.
      #
      # @return [Array<Hash>]
      def to_api_format
        @messages.map do |msg|
          {
            role: msg[:role],
            content: format_content(msg[:content])
          }
        end
      end

      # Remove the last user + assistant exchange. Useful for undo.
      # If the last two messages are assistant then user (most recent first),
      # removes both. Otherwise removes only the last message.
      #
      # @return [void]
      def undo_last!
        return if @messages.empty?

        # Walk backwards and remove the most recent user+assistant pair.
        # The typical pattern is: [..., user, assistant] or
        # [..., assistant, user(tool_results)].
        removed = 0
        while @messages.any? && removed < 2
          last = @messages.last
          break if removed == 1 && last[:role] != "assistant" && last[:role] != "user"

          @messages.pop
          removed += 1
        end
      end

      private

      # Normalize content and tool_calls into a single array of content blocks.
      def normalize_content(content, tool_calls)
        blocks = []

        case content
        when Array
          content.each { |b| blocks << block_to_hash(b) }
        when String
          blocks << { type: "text", text: content } unless content.empty?
        when Hash
          blocks << content
        else
          blocks << block_to_hash(content) if content.respond_to?(:type)
        end

        tool_calls.each do |tc|
          blocks << block_to_hash(tc)
        end

        blocks
      end

      # Format message content for the API. Converts Data objects to hashes.
      def format_content(content)
        case content
        when String then content
        when Array
          content.map { |block| block_to_hash(block) }
        else ""
        end
      end

      def block_to_hash(block)
        return block if block.is_a?(Hash)

        if block.respond_to?(:type)
          case block.type.to_s
          when "text"
            { type: "text", text: block.text }
          when "tool_use"
            { type: "tool_use", id: block.id, name: block.name, input: block.input }
          when "tool_result"
            h = { type: "tool_result", tool_use_id: block.tool_use_id, content: block.content.to_s }
            h[:is_error] = true if block.respond_to?(:is_error) && block.is_error
            h
          else
            block.respond_to?(:to_h) ? block.to_h : block
          end
        else
          block
        end
      end

      # Extract text from content blocks.
      def extract_text(content)
        case content
        when String
          content
        when Array
          text_blocks = content.select { |b| b.is_a?(Hash) && b[:type] == "text" }
          texts = text_blocks.map { |b| b[:text] }
          texts.empty? ? nil : texts.join("\n")
        end
      end

      # Check whether a message is a tool-result-bearing user message.
      def tool_result_message?(msg)
        return false unless msg[:content].is_a?(Array)

        msg[:content].all? { |b| b.is_a?(Hash) && b[:type] == "tool_result" }
      end
    end
  end
end
