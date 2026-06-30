# frozen_string_literal: true

require 'fileutils'
require 'json'

module RubynCode
  module CLI
    module Commands
      # Export the current conversation transcript to a file.
      #
      #   /export path/to/transcript.md              # markdown (default)
      #   /export --format jsonl path/to/transcript.jsonl
      #   /export path/to/transcript.md --force      # overwrite existing
      class Export < Base
        def self.command_name = '/export'
        def self.description = 'Export conversation transcript to markdown or JSONL'

        MAX_LINE_LENGTH = 100

        # -- CLI arg parsing is intrinsically procedural
        def execute(args, ctx)
          opts = parse_args(args)
          return unless opts

          messages = ctx.conversation.to_a
          if messages.empty?
            ctx.renderer.warning('No messages to export.')
            return
          end

          path = File.expand_path(opts[:path])
          dir  = File.dirname(path)
          FileUtils.mkdir_p(dir) unless File.directory?(dir)

          if File.exist?(path) && !opts[:force] && !tty_yes?(ctx, "File exists at #{path}. Overwrite? [y/N]")
            ctx.renderer.info('Export cancelled.')
            return
          end

          body = opts[:format] == 'jsonl' ? render_jsonl(messages) : render_markdown(messages)
          File.write(path, body)
          plural = messages.size == 1 ? '' : 's'
          ctx.renderer.info("Exported #{messages.size} message#{plural} to #{path}")
        end

        private

        # @return [Hash{Symbol=>Object}, nil] nil on bad input
        # -- arg parsing is intrinsically branchy
        def parse_args(args) # rubocop:disable Metrics/MethodLength -- arg parsing is intrinsically procedural
          format = 'markdown'
          force  = false
          path   = nil

          if (idx = args.index('--format') || args.index('-f'))
            format = args[idx + 1].to_s
          end
          format = case format
                   when 'md' then 'markdown'
                   else format
                   end

          args.each do |a|
            case a
            when '--jsonl'
              format = 'jsonl'
            when '--markdown', '--md'
              format = 'markdown'
            when '--format', '-f'
              # already handled above
            when '--force', '-y'
              force = true
            when /\A--.+/
              next
            else
              path ||= a
            end
          end

          return nil if path.to_s.empty?

          { path: path, format: format, force: force }
        end

        def render_markdown(messages)
          title  = 'Rubyn transcript'
          buffer = String.new
          buffer << "# #{title}\n\n"
          buffer << "_Exported at #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}_\n\n"
          messages.each { |msg| render_markdown_message(buffer, msg) }
          buffer
        end

        def render_markdown_message(buffer, msg)
          role = msg[:role] || msg['role']
          case role
          when 'user'
            text = render_user_text(msg[:content] || msg['content'])
            buffer << "## User\n\n#{text}\n\n"
          when 'assistant'
            render_assistant_blocks(buffer, msg[:content] || msg['content'])
          when 'tool'
            buffer << "### tool result\n\n```\n#{msg[:content] || msg['content']}\n```\n\n"
          end
        end

        def render_user_text(content)
          blocks = normalize_content(content)
          if blocks.any? { |b| block_type(b) == 'image' }
            blocks.map { |b| block_type(b) == 'image' ? '_(image attachment)_' : text_of(b) }.join("\n")
          else
            blocks.map { |b| text_of(b) }.join("\n")
          end
        end

        def render_assistant_blocks(buffer, content)
          blocks = normalize_content(content)
          if blocks.empty?
            buffer << "## Assistant\n\n_(empty response)_\n\n"
            return
          end
          blocks.each do |b|
            render_assistant_block(buffer, b)
          end
        end

        def render_assistant_block(buffer, b) # rubocop:disable Naming/MethodParameterName -- short names are clearer here than "block"
          case block_type(b)
          when 'text'
            buffer << "## Assistant\n\n#{text_of(b)}\n\n"
          when 'thinking'
            buffer << "<details><summary>thinking</summary>\n\n#{text_of(b)}\n\n</details>\n\n"
          when 'tool_use'
            buffer << "[tool: #{b[:name] || b['name']}]\n\n```json\n#{JSON.pretty_generate(input_of(b))}\n```\n\n"
          end
        end

        def render_jsonl(messages)
          lines = messages.map do |msg|
            role    = msg[:role] || msg['role']
            raw     = msg[:content] || msg['content']
            content = raw.is_a?(String) ? raw : normalize_content(raw)
            "#{JSON.generate(role: role, content: content, timestamp: Time.now.utc.iso8601)}\n"
          end
          lines.join
        end

        # Wrap a String content into a single text block so we can render uniformly.
        def normalize_content(content)
          return [{ type: 'text', text: content.to_s }] if content.is_a?(String)
          return [{ type: 'text', text: '' }] if content.nil?

          content
        end

        def block_type(block)
          block[:type] || block['type']
        end

        def text_of(block)
          (block[:text] || block['text']).to_s
        end

        def input_of(block)
          (block[:input] || block['input']) || {}
        end

        def tty_yes?(ctx, prompt)
          ctx.renderer.respond_to?(:ask) ? ctx.renderer.ask(prompt, default: false) : true
        end
      end
    end
  end
end
