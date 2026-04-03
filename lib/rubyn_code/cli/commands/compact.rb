# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Compact < Base
        def self.command_name = '/compact'
        def self.description = 'Compress conversation context'

        def execute(args, ctx)
          focus = args.first

          compactor = ::RubynCode::Context::Compactor.new(llm_client: ctx.llm_client)
          new_messages = compactor.manual_compact!(ctx.conversation.messages, focus: focus)
          ctx.conversation.replace!(new_messages)
          ctx.renderer.info("Context compacted. #{ctx.conversation.length} messages remaining.")
        end
      end
    end
  end
end
