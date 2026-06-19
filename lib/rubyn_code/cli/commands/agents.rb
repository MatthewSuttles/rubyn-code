# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/agents` — list the sub-agent types available to spawn_agent: the
      # built-in explore/worker plus any custom agents defined in
      # .rubyn-code/agents/*.md or ~/.rubyn-code/agents/*.md.
      class Agents < Base
        def self.command_name = '/agents'
        def self.description  = 'List available sub-agent types (built-in + custom)'

        def execute(_args, ctx)
          catalog = RubynCode::SubAgents::Catalog.new(project_root: ctx.project_root)
          ctx.renderer.info('Available sub-agent types:')
          catalog.all.each do |agent|
            tag = agent.custom? ? '(custom)' : '(built-in)'
            access = agent.read_only? ? 'read-only' : 'read/write'
            puts "  #{agent.name.ljust(18)} #{tag} [#{access}] — #{agent.description}"
          end
          puts
          ctx.renderer.info('Define your own in .rubyn-code/agents/<name>.md') if catalog.custom_names.empty?
          nil
        rescue StandardError => e
          ctx.renderer.error("Could not list agents: #{e.message}")
          nil
        end
      end
    end
  end
end
