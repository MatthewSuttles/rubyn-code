# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # Discovers, registers, and dispatches slash commands.
      #
      # Commands are registered by class reference. The registry builds
      # a lookup table from command names + aliases → command class.
      class Registry
        def initialize
          @commands = {} # '/name' => CommandClass
          @classes = []
        end

        # Register a command class.
        #
        # @param command_class [Class<Commands::Base>]
        # @return [void]
        def register(command_class)
          @classes << command_class
          command_class.all_names.each do |name|
            @commands[name] = command_class
          end
        end

        # Look up and execute a command by name.
        #
        # @param name [String] the slash command (e.g. '/doctor')
        # @param args [Array<String>] arguments
        # @param ctx [Commands::Context] shared context
        # @return [Symbol, nil] :quit if the command signals exit, nil otherwise
        def dispatch(name, args, ctx)
          command_class = @commands[name]
          return :unknown unless command_class

          command_class.new.execute(args, ctx)
        end

        # All registered command names (for tab completion).
        #
        # @return [Array<String>]
        def completions
          @commands.keys.sort.freeze
        end

        # Visible commands for /help (excludes hidden commands).
        #
        # @return [Array<Class<Commands::Base>>] unique, sorted by name
        def visible_commands
          @classes
            .reject(&:hidden?)
            .sort_by(&:command_name)
        end

        # @param name [String]
        # @return [Boolean]
        def known?(name)
          @commands.key?(name)
        end
      end
    end
  end
end
