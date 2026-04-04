# frozen_string_literal: true

module RubynCode
  module LLM
    TextBlock = Data.define(:text) do
      def type = 'text'
    end

    ToolUseBlock = Data.define(:id, :name, :input) do
      def type = 'tool_use'
    end

    ToolResultBlock = Data.define(:tool_use_id, :content, :is_error) do
      def type = 'tool_result'

      def initialize(tool_use_id:, content:, is_error: false)
        super
      end
    end

    Usage = Data.define(:input_tokens, :output_tokens, :cache_creation_input_tokens, :cache_read_input_tokens) do
      def initialize(input_tokens:, output_tokens:, cache_creation_input_tokens: 0, cache_read_input_tokens: 0)
        super
      end
    end

    Response = Data.define(:id, :content, :stop_reason, :usage) do
      def text
        content.select { |b| b.type == 'text' }.map(&:text).join
      end

      def tool_calls
        content.select { |b| b.type == 'tool_use' }
      end

      def tool_use?
        stop_reason == 'tool_use'
      end
    end

    class MessageBuilder
      SYSTEM_TEMPLATE = <<~PROMPT
        You are an AI coding assistant operating inside a developer's project.

        Project path: %<project_path>s

        %<skills_section>s
        %<instincts_section>s
      PROMPT

      def build_system_prompt(skills: [], instincts: [], project_path: Dir.pwd)
        skills_section = if skills.empty?
                           ''
                         else
                           "## Available Skills\n#{skills.map { |s| "- #{s}" }.join("\n")}"
                         end

        instincts_section = if instincts.empty?
                              ''
                            else
                              "## Learned Instincts\n#{instincts.map { |i| "- #{i}" }.join("\n")}"
                            end

        format(
          SYSTEM_TEMPLATE,
          project_path: project_path,
          skills_section: skills_section,
          instincts_section: instincts_section
        ).strip
      end

      def format_messages(conversation)
        conversation.map do |msg|
          case msg
          in { role: String => role, content: String => content }
            { role: role, content: content }
          in { role: String => role, content: Array => blocks }
            { role: role, content: format_content_blocks(blocks) }
          else
            msg.transform_keys(&:to_s)
          end
        end
      end

      def format_tool_results(results)
        content = results.map do |result|
          {
            type: 'tool_result',
            tool_use_id: result[:tool_use_id] || result[:id],
            content: result[:content].to_s,
            **(result[:is_error] ? { is_error: true } : {})
          }
        end

        { role: 'user', content: content }
      end

      private

      def format_content_blocks(blocks)
        blocks.map do |block|
          case block
          when TextBlock
            { type: 'text', text: block.text }
          when ToolUseBlock
            { type: 'tool_use', id: block.id, name: block.name, input: block.input }
          when ToolResultBlock
            hash = { type: 'tool_result', tool_use_id: block.tool_use_id, content: block.content.to_s }
            hash[:is_error] = true if block.is_error
            hash
          when Hash
            block
          else
            { type: 'text', text: block.to_s }
          end
        end
      end
    end
  end
end
