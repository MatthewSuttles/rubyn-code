# frozen_string_literal: true

module RubynCode
  module LLM
    module Adapters
      # Translates Anthropic-format messages to OpenAI Chat Completions format.
      #
      # Anthropic uses content blocks (tool_result, tool_use) inside message arrays,
      # while OpenAI uses separate message roles and tool_calls arrays.
      module OpenAIMessageTranslator
        private

        def build_messages(messages, system)
          result = []
          result << { role: 'system', content: system } if system
          messages.each do |msg|
            translated = translate_message(msg)
            translated.is_a?(Array) ? result.concat(translated) : result.push(translated)
          end
          result
        end

        def translate_message(msg)
          content = msg[:content] || msg['content']
          role = msg[:role] || msg['role']

          return translate_tool_results(content) if tool_results?(content)
          return translate_assistant_tool_use(content) if role == 'assistant' && tool_use_blocks?(content)

          { role: role, content: stringify_content(content) }
        end

        def tool_results?(content)
          content.is_a?(Array) && content.any? { |b| block_type(b) == 'tool_result' }
        end

        def tool_use_blocks?(content)
          content.is_a?(Array) && content.any? { |b| block_type(b) == 'tool_use' }
        end

        def translate_tool_results(content_blocks)
          content_blocks.select { |b| block_type(b) == 'tool_result' }.map do |block|
            tool_use_id = block[:tool_use_id] || block['tool_use_id']
            text = stringify_content(block[:content] || block['content'])
            { role: 'tool', tool_call_id: tool_use_id, content: text }
          end
        end

        def translate_assistant_tool_use(content_blocks)
          text_blocks, tool_blocks = partition_assistant_blocks(content_blocks)
          msg = { role: 'assistant' }
          msg[:content] = stringify_content(text_blocks) unless text_blocks.empty?
          msg[:tool_calls] = tool_blocks.map { |b| build_tool_call_hash(b) } unless tool_blocks.empty?
          msg
        end

        def partition_assistant_blocks(content_blocks)
          texts, tools = content_blocks.partition { |b| block_type(b) != 'tool_use' }
          [texts, tools]
        end

        def build_tool_call_hash(block)
          input = block[:input] || block['input'] || {}
          {
            id: block[:id] || block['id'],
            type: 'function',
            function: {
              name: block[:name] || block['name'],
              arguments: input.is_a?(String) ? input : JSON.generate(input)
            }
          }
        end

        def stringify_content(content)
          case content
          when String then content
          when Array
            content.map { |b| b[:text] || b['text'] || b.to_s }.join
          else
            content.to_s
          end
        end

        def block_type(block)
          block[:type] || block['type']
        end
      end
    end
  end
end
