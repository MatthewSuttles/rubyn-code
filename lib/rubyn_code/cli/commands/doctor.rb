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
