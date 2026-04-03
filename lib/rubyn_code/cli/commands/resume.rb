# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Resume < Base
        def self.command_name = '/resume'
        def self.description = 'Resume a session or list recent sessions'

        def execute(args, ctx)
          session_id = args.first

          if session_id
            resume_session(session_id, ctx)
          else
            list_sessions(ctx)
          end
        end

        private

        def resume_session(session_id, ctx)
          data = ctx.session_persistence.load_session(session_id)

          if data
            ctx.conversation.replace!(data[:messages])
            ctx.renderer.info("Resumed session #{session_id[0..7]}")
            { action: :set_session_id, session_id: session_id }
          else
            ctx.renderer.error("Session not found: #{session_id}")
          end
        end

        def list_sessions(ctx)
          sessions = ctx.session_persistence.list_sessions(
            project_path: ctx.project_root,
            limit: 10
          )

          if sessions.empty?
            ctx.renderer.info('No previous sessions.')
          else
            sessions.each do |s|
              puts "  #{s[:id][0..7]} | #{s[:title] || 'untitled'} | #{s[:created_at]}"
            end
          end
        end
      end
    end
  end
end
