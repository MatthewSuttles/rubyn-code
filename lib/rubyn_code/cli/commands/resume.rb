# frozen_string_literal: true

require 'time'

module RubynCode
  module CLI
    module Commands
      # List saved sessions or restore one into the current conversation.
      #
      #   /resume                # list sessions, recent first
      #   /resume <id>           # load session <id> (prompts before clobber)
      #   /resume <id> --force   # skip the confirm prompt
      class Resume < Base
        def self.command_name = '/resume'
        def self.description = 'List saved sessions or restore one into the current conversation'

        MAX_LIST_ENTRIES = 10

        def execute(args, ctx)
          persistence = ctx.session_persistence
          if persistence.nil?
            ctx.renderer.error('No session persistence wired in. Run a prompt first.')
            return
          end

          opts = parse_args(args)

          if opts[:id].nil?
            list_sessions(persistence, ctx)
            return
          end

          restore_session(persistence, opts, ctx)
        end

        private

        def parse_args(args)
          args.delete('--force')
          force = args.delete('-y')
          { id: args.first, force: force }
        end

        def list_sessions(persistence, ctx)
          rows = persistence.list_sessions
          if rows.empty?
            ctx.renderer.info('No saved sessions yet.')
            return
          end

          ctx.renderer.info("Saved sessions (most recent first, up to #{MAX_LIST_ENTRIES}):")
          rows.first(MAX_LIST_ENTRIES).each do |row|
            count = row[:message_count].to_i
            time  = row[:last_activity]
            title = row[:title].to_s.empty? ? '(untitled)' : row[:title]
            sid   = row[:session_id]
            ctx.renderer.info("  #{sid}  #{count} msg  · #{format_time(time)}  · #{title}")
          end
        end

        def restore_session(persistence, opts, ctx)
          loaded = persistence.load_session(opts[:id])
          if loaded.nil?
            ctx.renderer.error("Session not found: #{opts[:id]}")
            return
          end

          messages = loaded[:messages] || []
          if messages.empty?
            ctx.renderer.warning("Session #{opts[:id]} has no messages — nothing to restore.")
            return
          end

          unless confirm_replace(ctx, opts, loaded, messages)
            ctx.renderer.info('Resume cancelled.')
            return
          end

          ctx.conversation.replace!(messages)
          title = loaded[:title].to_s.empty? ? '(untitled)' : loaded[:title]
          ctx.renderer.info("✓ Resumed session #{opts[:id]} — #{messages.size} messages from '#{title}'")
        end

        def confirm_replace(ctx, opts, loaded, messages)
          return true if opts[:force]
          return true if ctx.conversation.nil?
          return true if ctx.conversation.messages.empty?

          current = ctx.conversation.messages.size
          target  = messages.size
          title   = loaded[:title].to_s.empty? ? '(untitled)' : loaded[:title]
          prompt  = "Replace current conversation (#{current} messages) " \
                    "with session #{opts[:id]} '#{title}' (#{target} messages)? [y/N]"

          return false unless ctx.renderer.respond_to?(:ask)

          ctx.renderer.ask(prompt, default: false)
        end

        def format_time(time)
          return 'never' if time.nil?

          t = begin
            time.is_a?(Time) ? time : Time.parse(time.to_s)
          rescue StandardError
            nil
          end
          return 'never' if t.nil?

          delta = Time.now - t
          case delta
          when 0...60          then 'just now'
          when 60...3600       then "#{delta.to_i / 60} min ago"
          when 3600...86_400   then "#{delta.to_i / 3600} hr ago"
          when 86_400...604_800 then "#{delta.to_i / 86_400} d ago"
          else t.strftime('%Y-%m-%d')
          end
        end
      end
    end
  end
end
