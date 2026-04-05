# frozen_string_literal: true

module RubynCode
  module LLM
    module Adapters
      # Anthropic prompt caching logic.
      #
      # Injects `cache_control: { type: 'ephemeral' }` into system blocks,
      # tool definitions, and the last message — enabling Anthropic's prompt
      # caching to skip re-processing static content across turns.
      module PromptCaching
        CACHE_EPHEMERAL = { type: 'ephemeral' }.freeze

        OAUTH_GATE = "You are Claude Code, Anthropic's official CLI for Claude.".freeze

        private

        def apply_system_blocks(body, system)
          if oauth_token?
            blocks = [{ type: 'text', text: OAUTH_GATE, cache_control: CACHE_EPHEMERAL }]
            blocks << { type: 'text', text: system, cache_control: CACHE_EPHEMERAL } if system
            body[:system] = blocks
          elsif system
            body[:system] = [{ type: 'text', text: system, cache_control: CACHE_EPHEMERAL }]
          end
        end

        def apply_tool_cache(body, tools)
          return if tools.nil? || tools.empty?

          cached_tools = tools.map(&:dup)
          cached_tools.last[:cache_control] = CACHE_EPHEMERAL
          body[:tools] = cached_tools
        end

        def add_message_cache_breakpoint(messages)
          return messages if messages.nil? || messages.empty?

          tagged = messages.map(&:dup)
          tag_last_message_content(tagged.last)
          tagged
        end

        def tag_last_message_content(last_msg)
          content = last_msg[:content]
          case content
          when Array
            return if content.empty?

            last_msg[:content] = content.map(&:dup)
            last_block = last_msg[:content].last
            last_block[:cache_control] = CACHE_EPHEMERAL if last_block.is_a?(Hash)
          when String
            last_msg[:content] = [{ type: 'text', text: content, cache_control: CACHE_EPHEMERAL }]
          end
        end
      end
    end
  end
end
