# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/learning` — inspect and move the instincts Rubyn learns across
      # sessions. Continuous learning runs automatically at the end of each
      # session; this command lets you carry those learnings to another machine.
      #
      #   /learning                       show learning stats
      #   /learning export [path]         export all instincts to a JSON file
      #   /learning import <path> [--here] import instincts (--here = remap to this project)
      class Learning < Base
        def self.command_name = '/learning'
        def self.description  = 'Show, export, or import learned instincts (/learning export|import)'

        DEFAULT_FILE = 'rubyn-learnings.json'

        def execute(args, ctx)
          case args.first
          when 'export' then export(ctx, args[1])
          when 'import' then import(ctx, args[1..])
          when nil      then stats(ctx)
          else
            ctx.renderer.info('Usage: /learning [export [path] | import <path> [--here]]')
          end
          nil
        rescue RubynCode::Learning::Porter::Error => e
          ctx.renderer.error("Learning: #{e.message}")
          nil
        end

        private

        def stats(ctx)
          summary = RubynCode::Learning::Porter.stats(ctx.db)
          ctx.renderer.info("🧠 #{summary[:count]} instinct(s) learned across #{summary[:projects]} project(s).")
          ctx.renderer.info('Move them with: /learning export  →  /learning import <file> --here')
        end

        def export(ctx, path)
          dest = File.expand_path(path || DEFAULT_FILE, ctx.project_root)
          count = RubynCode::Learning::Porter.export(db: ctx.db, path: dest)
          ctx.renderer.info("📤 Exported #{count} instinct(s) to #{dest}")
        end

        def import(ctx, rest)
          args = Array(rest)
          here = args.delete('--here')
          path = args.first
          return ctx.renderer.info('Usage: /learning import <path> [--here]') unless path

          remap = here ? ctx.project_root : nil
          result = RubynCode::Learning::Porter.import(
            db: ctx.db, path: File.expand_path(path, ctx.project_root), remap_project: remap
          )
          ctx.renderer.info("📥 Imported #{result[:imported]} instinct(s) (#{result[:skipped]} skipped as duplicates).")
        end
      end
    end
  end
end
