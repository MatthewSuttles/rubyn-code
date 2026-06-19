# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/rewind` — restore the session to an earlier checkpoint, mirroring
      # Claude Code's /rewind. A checkpoint is taken at the start of each user
      # turn, capturing the conversation and the original contents of any files
      # changed that turn.
      #
      #   /rewind                list checkpoints
      #   /rewind <id>           restore code + conversation to checkpoint <id>
      #   /rewind <id> code      restore only the files
      #   /rewind <id> chat      restore only the conversation
      class Rewind < Base
        def self.command_name = '/rewind'
        def self.description  = 'Rewind to an earlier checkpoint (/rewind to list)'

        SCOPES = { 'code' => :code, 'chat' => :chat, 'both' => :both }.freeze

        def execute(args, ctx)
          manager = ctx.checkpoint_manager
          return ctx.renderer.info('Checkpoints are not available in this session.') unless manager

          id = args.first
          return list(manager, ctx) if id.nil?

          restore(manager, ctx, id, args[1])
        end

        private

        def list(manager, ctx)
          checkpoints = manager.list
          return ctx.renderer.info('No checkpoints yet — they are created as you work.') if checkpoints.empty?

          ctx.renderer.info('Checkpoints (newest last):')
          checkpoints.each do |cp|
            puts "  #{cp[:id].to_s.rjust(3)}  #{cp[:files]} file(s)  — #{cp[:label]}"
          end
          puts
          ctx.renderer.info('Restore with: /rewind <id> [code|chat]')
          nil
        end

        def restore(manager, ctx, id_arg, scope_arg)
          scope = SCOPES.fetch(scope_arg.to_s, :both)
          result = manager.restore(id_arg.to_i, ctx.conversation, scope: scope)
          return ctx.renderer.warning("No checkpoint ##{id_arg}.") unless result

          ctx.renderer.info(restored_message(result, scope))
          { action: :rewound }
        end

        def restored_message(result, scope)
          case scope
          when :code then "⏪ Restored #{result[:files_restored]} file(s) to checkpoint ##{result[:id]}."
          when :chat then "⏪ Restored conversation to checkpoint ##{result[:id]}."
          else "⏪ Rewound to checkpoint ##{result[:id]} (#{result[:files_restored]} file(s) + conversation)."
          end
        end
      end
    end
  end
end
