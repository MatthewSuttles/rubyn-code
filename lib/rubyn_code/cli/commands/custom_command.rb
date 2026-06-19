# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # A slash command defined by a user markdown file (loaded by
      # CustomLoader). Unlike the built-in commands — which are registered as
      # classes — this is a ready instance: the Registry dispatches it directly.
      #
      # Executing it renders the template (argument / bash substitution) and
      # sends the result to the agent as a normal prompt.
      class CustomCommand
        # @return [String] command name without the leading slash
        attr_reader :name
        # @return [String] one-line description for /help
        attr_reader :description
        # @return [String, nil] originating file path
        attr_reader :source

        def initialize(name:, description:, body:, source: nil)
          @name = name
          @description = description
          @template = CommandTemplate.new(body)
          @source = source
        end

        def command_name = "/#{@name}"
        def aliases = [].freeze
        def hidden? = false
        def all_names = [command_name].freeze

        # @param args [Array<String>]
        # @param ctx [Commands::Context]
        # @return [nil]
        def execute(args, ctx)
          ctx.send_message(@template.render(args))
          nil
        end
      end
    end
  end
end
