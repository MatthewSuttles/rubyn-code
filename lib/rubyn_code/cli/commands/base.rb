# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # Abstract base class for all slash commands.
      #
      # Subclasses must implement:
      #   - self.command_name  → String (e.g. '/doctor')
      #   - self.description   → String (one-liner for /help)
      #   - execute(args, ctx) → void
      #
      # Optionally override:
      #   - self.aliases → Array<String> (e.g. ['/q', '/exit'])
      #   - self.hidden? → Boolean (hide from /help listing)
      class Base
        class << self
          def command_name
            raise NotImplementedError, "#{name} must define self.command_name"
          end

          def description
            raise NotImplementedError, "#{name} must define self.description"
          end

          def aliases
            [].freeze
          end

          def hidden?
            false
          end

          # All names this command responds to (primary + aliases).
          #
          # @return [Array<String>]
          def all_names
            [command_name, *aliases].freeze
          end
        end

        # Execute the command.
        #
        # @param args [Array<String>] arguments passed after the command name
        # @param ctx [Commands::Context] shared context with REPL dependencies
        # @return [void]
        def execute(args, ctx)
          raise NotImplementedError, "#{self.class.name}#execute must be implemented"
        end
      end
    end
  end
end
