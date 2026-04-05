# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # Saves the current session and starts a fresh conversation.
      # Like pressing Escape in Claude Code — clears context without quitting.
      class NewSession < Base
        def self.command_name = '/new'
        def self.description = 'Save current session and start a fresh conversation'
        def self.aliases = ['/reset'].freeze

        def execute(_args, ctx)
          save_current_session(ctx)
          clear_conversation(ctx)
          new_session_id = generate_session_id

          ctx.renderer.info('Session saved. Starting fresh.')
          ctx.renderer.info("New session: #{new_session_id[0..7]}")

          { action: :new_session, session_id: new_session_id }
        end

        private

        def save_current_session(ctx)
          ctx.session_persistence.save_session(
            session_id: ctx.session_id,
            project_path: ctx.project_root,
            messages: ctx.conversation.messages,
            model: Config::Defaults::DEFAULT_MODEL
          )
        end

        def clear_conversation(ctx)
          ctx.conversation.clear!
        end

        def generate_session_id
          SecureRandom.hex(16)
        end
      end
    end
  end
end
