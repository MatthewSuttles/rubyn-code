# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Doctor < Base
        def self.command_name = '/doctor'
        def self.description = 'Environment health check'

        CHECKS = %i[
          check_ruby
          check_bundler
          check_database
          check_auth
          check_skills
          check_project
          check_mcp
          check_codebase_index
          check_skill_catalog
        ].freeze

        def execute(_args, ctx)
          ctx.renderer.info('Rubyn Code Doctor 🩺')
          puts

          results = CHECKS.map { |check| send(check, ctx) }
          results.each { |label, ok, detail| render_check(label, ok, detail) }

          puts
          render_summary(results, ctx.renderer)
        end

        private

        def render_check(label, passed, detail)
          icon = passed ? green('✓') : red('✗')
          suffix = detail ? " — #{detail}" : ''
          puts "  #{icon} #{label}#{suffix}"
        end

        def render_summary(results, renderer)
          passed = results.count { |_, success, _| success }
          failed = results.size - passed
          summary = "#{passed} passed, #{failed} failed"

          if failed.zero?
            renderer.success("All checks passed! #{summary}")
          else
            renderer.warning("#{summary}. Fix the issues above.")
          end
        end

        def check_ruby(_ctx)
          version = RUBY_VERSION
          ok = Gem::Version.new(version) >= Gem::Version.new('3.2')
          ['Ruby version', ok, "#{version} (#{RUBY_PLATFORM})"]
        end

        def check_bundler(_ctx)
          version = Gem.loaded_specs['bundler']&.version&.to_s || Bundler::VERSION
          ['Bundler', true, "v#{version}"]
        rescue StandardError
          ['Bundler', false, 'not found']
        end

        def check_database(ctx)
          db = ctx.db
          count = db.query('SELECT COUNT(*) AS c FROM schema_migrations').first
          migrations = count['c'] || count[:c]
          ['Database', true, "#{migrations} migrations applied"]
        rescue StandardError => e
          ['Database', false, e.message]
        end

        def check_auth(_ctx)
          if Auth::TokenStore.valid?
            tokens = Auth::TokenStore.load
            source = tokens&.fetch(:source, :unknown)
            ['Authentication', true, source.to_s]
          else
            ['Authentication', false, 'no valid token found']
          end
        rescue StandardError => e
          ['Authentication', false, e.message]
        end

        def check_skills(ctx)
          catalog = ctx.skill_loader.catalog
          count = catalog.list.size
          ['Skills', count.positive?, "#{count} skills available"]
        rescue StandardError => e
          ['Skills', false, e.message]
        end

        def check_project(ctx)
          gemfile = File.join(ctx.project_root, 'Gemfile')
          return ['Project detected', false, 'no Gemfile found'] unless File.exist?(gemfile)

          type = detect_project_type(ctx.project_root)
          ['Project detected', true, "#{type} at #{ctx.project_root}"]
        end

        def check_mcp(ctx)
          config_path = File.join(ctx.project_root, MCP::Config::CONFIG_FILENAME)
          return ['MCP connectivity', false, 'mcp.json not found'] unless File.exist?(config_path)

          servers = MCP::Config.load(ctx.project_root)
          return ['MCP connectivity', false, 'no servers configured'] if servers.empty?

          reachable = servers.count { |s| mcp_server_reachable?(s) }
          detail = "#{reachable}/#{servers.size} servers reachable"
          ['MCP connectivity', reachable == servers.size, detail]
        rescue StandardError => e
          ['MCP connectivity', false, e.message]
        end

        def mcp_server_reachable?(server)
          command = server[:command]
          return false if command.nil? || command.empty?

          # Check if the command binary exists on PATH
          system("command -v #{command} > /dev/null 2>&1")
        end

        def check_codebase_index(ctx)
          index_path = File.join(ctx.project_root, Index::CodebaseIndex::INDEX_DIR,
                                 Index::CodebaseIndex::INDEX_FILE)
          return ['Codebase index', false, 'index not found'] unless File.exist?(index_path)

          mtime = File.mtime(index_path)
          age_hours = ((Time.now - mtime) / 3600).round(1)
          stale = age_hours > 24
          detail = "#{age_hours}h old#{' (stale — consider reindexing)' if stale}"
          ['Codebase index', !stale, detail]
        rescue StandardError => e
          ['Codebase index', false, e.message]
        end

        def check_skill_catalog(ctx)
          catalog = ctx.skill_loader.catalog
          entries = catalog.available
          return ['Skill catalog', false, 'no skills found'] if entries.empty?

          malformed = count_malformed_skills(catalog.skills_dirs)
          detail = "#{entries.size} skills loaded"
          detail += ", #{malformed} malformed" if malformed.positive?
          ['Skill catalog', malformed.zero?, detail]
        rescue StandardError => e
          ['Skill catalog', false, e.message]
        end

        def count_malformed_skills(skills_dirs)
          count = 0
          skills_dirs.each do |dir|
            next unless File.directory?(dir)

            Dir.glob(File.join(dir, '**/*.md')).each do |path|
              count += 1 unless valid_skill_file?(path)
            end
          end
          count
        end

        def valid_skill_file?(path)
          content = File.read(path, 1024, encoding: 'UTF-8')
                        .encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
          doc = Skills::Document.parse(content, filename: path)
          !doc.name.nil? && !doc.name.empty?
        rescue StandardError
          false
        end

        def detect_project_type(root)
          return 'Rails' if File.exist?(File.join(root, 'config', 'application.rb'))
          return 'Ruby' if File.exist?(File.join(root, 'Rakefile'))

          'Ruby (Gemfile)'
        end

        def green(text)  = "\e[32m#{text}\e[0m"
        def red(text)    = "\e[31m#{text}\e[0m"
      end
    end
  end
end
