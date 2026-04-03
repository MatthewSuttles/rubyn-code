# frozen_string_literal: true

module RubynCode
  module Context
    # Zero-cost compression that runs every turn. Replaces old tool results
    # (except the most recent N) with short placeholders to reduce token count
    # without losing conversational continuity.
    module MicroCompact
      PLACEHOLDER_TEMPLATE = "[Previous: used %<tool_name>s]"
      MIN_CONTENT_LENGTH = 100

      # Mutates +messages+ in place, replacing old tool_result content with
      # compact placeholders.
      #
      # @param messages [Array<Hash>] the conversation messages array
      # @param keep_recent [Integer] number of most-recent tool results to preserve
      # @param preserve_tools [Array<String>] tool names whose results are never compacted
      # @return [Integer] count of compacted tool results
      def self.call(messages, keep_recent: 2, preserve_tools: [])
        tool_result_refs = collect_tool_results(messages)
        return 0 if tool_result_refs.size <= keep_recent

        tool_name_index = build_tool_name_index(messages)
        candidates = tool_result_refs[0..-(keep_recent + 1)]
        compacted = 0

        candidates.each do |ref|
          block = ref[:block]
          content = extract_content(block)
          next if content.nil? || content.length < MIN_CONTENT_LENGTH

          tool_name = resolve_tool_name(block, tool_name_index)
          next if preserve_tools.include?(tool_name)

          placeholder = format(PLACEHOLDER_TEMPLATE, tool_name: tool_name || "tool")
          replace_content!(block, placeholder)
          compacted += 1
        end

        compacted
      end

      # Collects all tool_result content blocks across user messages, preserving
      # encounter order so the most recent ones can be kept intact.
      #
      # @return [Array<Hash>] each entry has :message, :block, :index keys
      def self.collect_tool_results(messages)
        refs = []

        messages.each do |msg|
          next unless msg[:role] == "user" && msg[:content].is_a?(Array)

          msg[:content].each_with_index do |block, idx|
            next unless tool_result_block?(block)

            refs << { message: msg, block: block, index: idx }
          end
        end

        refs
      end

      # Builds a lookup from tool_use_id to tool name by scanning assistant
      # messages for tool_use blocks.
      #
      # @return [Hash{String => String}]
      def self.build_tool_name_index(messages)
        index = {}

        messages.each do |msg|
          next unless msg[:role] == "assistant" && msg[:content].is_a?(Array)

          msg[:content].each do |block|
            case block
            when Hash
              index[block[:id] || block["id"]] = block[:name] || block["name"] if block_type(block) == "tool_use"
            when LLM::ToolUseBlock
              index[block.id] = block.name
            end
          end
        end

        index
      end

      def self.tool_result_block?(block)
        case block
        when Hash
          block_type(block) == "tool_result"
        when LLM::ToolResultBlock
          true
        else
          false
        end
      end

      def self.block_type(hash)
        hash[:type] || hash["type"]
      end

      def self.extract_content(block)
        case block
        when Hash
          val = block[:content] || block["content"]
          val.is_a?(String) ? val : val.to_s
        when LLM::ToolResultBlock
          block.content.to_s
        end
      end

      def self.resolve_tool_name(block, index)
        tool_use_id = case block
                      when Hash then block[:tool_use_id] || block["tool_use_id"]
                      when LLM::ToolResultBlock then block.tool_use_id
                      end

        index[tool_use_id]
      end

      def self.replace_content!(block, placeholder)
        case block
        when Hash
          key = block.key?(:content) ? :content : "content"
          block[key] = placeholder
        end
        # Note: Data.define instances are frozen; for ToolResultBlock objects
        # we rely on messages being stored as hashes in the conversation array.
      end

      private_class_method :collect_tool_results, :build_tool_name_index,
                           :tool_result_block?, :block_type, :extract_content,
                           :resolve_tool_name, :replace_content!
    end
  end
end
