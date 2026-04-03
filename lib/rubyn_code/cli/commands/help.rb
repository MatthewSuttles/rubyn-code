# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Help < Base
        def self.command_name = '/help'
        def self.description = 'Show this help message'

        def execute(_args, ctx)
          ctx.renderer.info('Available commands:')
          puts
          render_commands(self.class.registry)
          render_tips
        end

        private

        def render_commands(registry)
          registry.visible_commands.each do |cmd_class|
            names = cmd_class.all_names.join(', ')
            puts "  #{names.ljust(25)} #{cmd_class.description}"
          end
        end

        def render_tips
          puts
          puts '  Tips:'
          puts '    - Use @filename to include file contents in your message'
          puts '    - End a line with \ for multiline input'
          puts '    - Type / to list all commands'
          puts
        end

        class << self
          attr_accessor :registry
        end
      end
    end
  end
end
