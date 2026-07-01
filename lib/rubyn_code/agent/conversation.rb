# frozen_string_literal: true

require 'json'

module RubynCode
  module Agent
    class Conversation # rubocop:disable Metrics/ClassLength -- message log + incremental token/tool-ID bookkeeping
      attr_reader :messages

      def initialize
        @messages = []
        reset_derived_state!
      end

      # Append a user turn to the conversation.
      #
      # @param content [String, Array<Hash>] either a plain string or an
      #   array of content blocks (text, image, etc.). Strings get wrapped
      #   as `[{ type: 'text', text: content }]` only if there's a planned
      #   Array; we keep raw String for backward compatibility with the API.
      # @return [Hash] the appended message
      def add_user_message(content)
        message = { role: 'user', content: content }
        @messages << message
        track_added_message(message)
        message
      end

      # Append an assistant turn to the conversation.
      #
      # @param content [Array<Hash>, String, nil] text blocks from the response
      # @param tool_calls [Array<Hash>] tool_use blocks from the response
      # @return [Hash] the appended message
      def add_assistant_message(content, tool_calls: [])
        blocks = normalize_content(content, tool_calls)
        message = { role: 'assistant', content: blocks }
        @messages << message
        track_added_message(message)
        message
      end

      # Append a tool result turn to the conversation.
      #
      # @param tool_use_id [String]
      # @param tool_name [String]
      # @param output [String]
      # @param is_error [Boolean]
      # @return [Hash] the appended message
      def add_tool_result(tool_use_id, _tool_name, output, is_error: false)
        result_block = {
          type: 'tool_result',
          tool_use_id: tool_use_id,
          content: output.to_s
        }
        result_block[:is_error] = true if is_error

        # The Claude API expects tool results as a user message whose content
        # is an array of tool_result blocks.  When the previous message is
        # already a user/tool_result message we append to it so that multiple
        # tool results for the same assistant turn are batched together.
        if @messages.last && @messages.last[:role] == 'user' && tool_result_message?(@messages.last)
          @messages.last[:content] << result_block
          track_appended_block(result_block)
        else
          message = { role: 'user', content: [result_block] }
          @messages << message
          track_added_message(message)
        end

        result_block
      end

      # Extract the text from the most recent assistant message.
      #
      # @return [String, nil]
      def last_assistant_text
        assistant_msg = @messages.reverse_each.find { |m| m[:role] == 'assistant' }
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
        reset_derived_state!
      end

      # Character length of the JSON-serialized messages array, maintained
      # incrementally on append so per-turn token estimation doesn't have to
      # re-serialize the whole history. Matches JSON.generate(messages).length.
      #
      # @return [Integer]
      def estimated_json_chars
        @json_chars ||= @messages.sum { |msg| JSON.generate(msg).length }
        return 2 if @messages.empty?

        # "[" + per-message JSON joined by "," + "]"
        @json_chars + @messages.length + 1
      end

      # Drops cached serialization/tool-ID bookkeeping. Must be called after
      # messages are mutated in place from outside this class (e.g. by
      # Context::MicroCompact); the caches rebuild lazily on next access.
      #
      # @return [void]
      def refresh_derived_state!
        reset_derived_state!
      end

      # Return the messages array formatted for the Claude API.
      # Ensures proper role alternation and content structure.
      #
      # @return [Array<Hash>]
      def to_api_format
        formatted = @messages.map do |msg|
          {
            role: msg[:role],
            content: format_content(msg[:content])
          }
        end

        repair_orphaned_tool_uses(formatted)
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
          break if removed == 1 && last[:role] != 'assistant' && last[:role] != 'user'

          @messages.pop
          removed += 1
        end
        reset_derived_state!
      end

      # Replace messages with a new array (used after compaction).
      def replace!(new_messages)
        @messages.replace(new_messages)
        reset_derived_state!
      end

      # Alias for `messages`. Common shorthand for callers that want to
      # treat the conversation as an Array of message hashes.
      def to_a
        @messages
      end
      alias to_ary to_a

      private

      # Derived bookkeeping kept in sync with @messages so hot paths stay
      # cheap: per-message JSON char total (token estimation) and
      # tool_use/tool_result ID sets (orphan repair). nil means "rebuild
      # lazily from @messages on next access".
      def reset_derived_state!
        @json_chars = nil
        @tool_use_ids = nil
        @tool_result_ids = nil
      end

      def track_added_message(message)
        register_tool_ids(message)
        return if @json_chars.nil?

        @json_chars += JSON.generate(message).length
      rescue StandardError
        @json_chars = nil
      end

      # A tool_result block appended to an existing user message grows that
      # message's JSON by the block plus one separator comma.
      def track_appended_block(result_block)
        @tool_result_ids << result_block[:tool_use_id] if @tool_result_ids
        return if @json_chars.nil?

        @json_chars += JSON.generate(result_block).length + 1
      rescue StandardError
        @json_chars = nil
      end

      def register_tool_ids(message)
        return unless @tool_use_ids && message[:content].is_a?(Array)

        message[:content].each do |block|
          next unless block.is_a?(Hash)

          if message[:role] == 'assistant' && block_matches_type?(block, 'tool_use')
            @tool_use_ids << (block[:id] || block['id'])
          elsif message[:role] == 'user' && block_matches_type?(block, 'tool_result')
            @tool_result_ids << (block[:tool_use_id] || block['tool_use_id'])
          end
        end
      end

      def rebuild_tool_id_sets!
        @tool_use_ids = collect_tool_use_ids(@messages)
        @tool_result_ids = collect_tool_result_ids(@messages)
      end

      # Ensure every tool_use block has a matching tool_result.
      # If a tool_use is orphaned (e.g. from Ctrl-C interruption),
      # inject a synthetic tool_result immediately after the assistant
      # message that contains the orphaned tool_use.
      #
      # The ID sets are tracked incrementally as messages are appended, so
      # the common no-orphan case skips the full-history scans.
      def repair_orphaned_tool_uses(formatted)
        rebuild_tool_id_sets! if @tool_use_ids.nil?
        orphaned = @tool_use_ids - @tool_result_ids
        return formatted if orphaned.empty?

        insert_orphan_results(formatted, orphaned)
      end

      # Walk backwards to find the assistant message containing each orphaned
      # tool_use and insert a user/tool_result message right after it.
      # -- walks messages to find insertion point
      def insert_orphan_results(formatted, orphaned)
        orphan_set = orphaned.to_a.to_set
        insert_idx = find_orphan_insert_index(formatted, orphan_set)

        results = orphaned.map do |id|
          { type: 'tool_result', tool_use_id: id, content: '[interrupted]', is_error: true }
        end

        formatted.insert(insert_idx, { role: 'user', content: results })
        formatted
      end

      # Find the index right after the last assistant message that contains
      # any of the orphaned tool_use IDs.
      def find_orphan_insert_index(formatted, orphan_set)
        formatted.each_with_index.reverse_each do |msg, idx|
          next unless msg[:role] == 'assistant' && msg[:content].is_a?(Array)
          return idx + 1 if assistant_has_orphan?(msg, orphan_set)
        end

        formatted.length # fallback: append at end
      end

      def assistant_has_orphan?(msg, orphan_set)
        msg[:content].any? do |block|
          block.is_a?(Hash) && block_matches_type?(block, 'tool_use') &&
            orphan_set.include?(block[:id] || block['id'])
        end
      end

      def collect_tool_use_ids(formatted)
        collect_block_ids(formatted, role: 'assistant', type: 'tool_use', id_key: :id, id_str_key: 'id')
      end

      def collect_tool_result_ids(formatted)
        collect_block_ids(formatted, role: 'user', type: 'tool_result', id_key: :tool_use_id,
                                     id_str_key: 'tool_use_id')
      end

      # -- iterates blocks with type+role guards
      def collect_block_ids(formatted, role:, type:, id_key:, id_str_key:)
        ids = Set.new
        formatted.each do |msg|
          next unless msg[:role] == role && msg[:content].is_a?(Array)

          msg[:content].each do |block|
            next unless block.is_a?(Hash) && block_matches_type?(block, type)

            ids << (block[id_key] || block[id_str_key])
          end
        end
        ids
      end

      def block_matches_type?(block, type)
        block[:type] == type || block['type'] == type
      end

      # Normalize content and tool_calls into a single array of content blocks.
      def normalize_content(content, tool_calls)
        blocks = content_to_blocks(content)
        tool_calls.each { |tc| blocks << block_to_hash(tc) }
        blocks
      end

      def content_to_blocks(content)
        case content
        when Array  then content.map { |b| block_to_hash(b) }
        when String then content.empty? ? [] : [{ type: 'text', text: content }]
        when Hash   then [content]
        else content.respond_to?(:type) ? [block_to_hash(content)] : []
        end
      end

      # Format message content for the API. Converts Data objects to hashes.
      def format_content(content)
        case content
        when String then content
        when Array
          content.map { |block| block_to_hash(block) }
        else ''
        end
      end

      def block_to_hash(block)
        return block if block.is_a?(Hash)
        return block unless block.respond_to?(:type)

        typed_block_to_hash(block)
      end

      def typed_block_to_hash(block)
        case block.type.to_s
        when 'text'
          { type: 'text', text: block.text }
        when 'tool_use'
          { type: 'tool_use', id: block.id, name: block.name, input: block.input }
        when 'tool_result'
          tool_result_block_to_hash(block)
        else
          block.respond_to?(:to_h) ? block.to_h : block
        end
      end

      def tool_result_block_to_hash(block)
        h = { type: 'tool_result', tool_use_id: block.tool_use_id, content: block.content.to_s }
        h[:is_error] = true if block.respond_to?(:is_error) && block.is_error
        h
      end

      # Extract text from content blocks.
      def extract_text(content)
        case content
        when String
          content
        when Array
          text_blocks = content.select { |b| b.is_a?(Hash) && b[:type] == 'text' }
          texts = text_blocks.map { |b| b[:text] }
          texts.empty? ? nil : texts.join("\n")
        end
      end

      # Check whether a message is a tool-result-bearing user message.
      def tool_result_message?(msg)
        return false unless msg[:content].is_a?(Array)

        msg[:content].all? { |b| b.is_a?(Hash) && b[:type] == 'tool_result' }
      end
    end
  end
end
