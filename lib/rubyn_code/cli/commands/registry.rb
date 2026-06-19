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

        # Register a command. Accepts either a command class (built-ins, which
        # are instantiated per dispatch) or a ready command instance
        # (user-defined; see Commands::CustomCommand).
        #
        # @param command [Class<Commands::Base>, #execute]
        # @return [void]
        def register(command)
          @classes << command
          command.all_names.each do |name|
            @commands[name] = command
          end
        end

        # Look up and execute a command by name.
        #
        # @param name [String] the slash command (e.g. '/doctor')
        # @param args [Array<String>] arguments
        # @param ctx [Commands::Context] shared context
        # @return [Symbol, nil] :quit if the command signals exit, nil otherwise
        def dispatch(name, args, ctx)
          command = @commands[name]
          return :unknown unless command

          # Built-ins are registered as classes (instantiate per call);
          # user-defined commands are registered as ready instances.
          instance = command.respond_to?(:new) ? command.new : command
          instance.execute(args, ctx)
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
