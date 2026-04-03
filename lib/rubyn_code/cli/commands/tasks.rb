# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Tasks < Base
        def self.command_name = '/tasks'
        def self.description = 'List all tasks'

        STATUS_COLORS = {
          'completed' => :green,
          'in_progress' => :yellow,
          'blocked' => :red
        }.freeze

        def execute(_args, ctx)
          task_manager = ::RubynCode::Tasks::Manager.new(ctx.db)
          tasks = task_manager.list

          if tasks.empty?
            ctx.renderer.info('No tasks.')
            return
          end

          tasks.each do |t|
            puts "  [#{t[:status]}] #{t[:title]} (#{t[:id][0..7]})"
          end
        end
      end
    end
  end
end
