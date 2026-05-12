# frozen_string_literal: true

require 'fileutils'

module RubynCode
  # Programmatic smoke test that exercises every major subsystem.
  # Mirrors the checks in skills/rubyn_self_test.md but runs without
  # the REPL or an LLM — suitable for CI and rake tasks.
  #
  # rubocop:disable Metrics/ClassLength -- intentionally comprehensive
  class SelfTest
    Result = Data.define(:name, :passed, :detail)

    attr_reader :results, :project_root

    def initialize(project_root: Dir.pwd)
      @project_root = project_root
      @results = []
    end

    def run! # rubocop:disable Naming/PredicateMethod -- returns bool but primary purpose is side effects
      @results = []

      check_file_operations
      check_search
      check_bash
      check_git
      check_specs
      check_compressor_strategies
      check_skills
      check_config
      check_codebase_index
      check_slash_commands
      check_architecture

      print_scorecard
      results.all?(&:passed)
    end

    private

    # ── 1. File Operations ──────────────────────────────────────────

    def check_file_operations
      check_file_read
      check_file_write_edit_cleanup
    rescue StandardError => e
      record('File operations', false, e.message)
    end

    def check_file_read
      content = File.read(File.join(project_root, 'lib/rubyn_code/version.rb'))
      record('File read (version.rb)', content.include?('VERSION ='))
    end

    # -- sequential file ops
    def check_file_write_edit_cleanup
      tmp = File.join(project_root, '.rubyn-code/self_test_tmp.rb')
      FileUtils.mkdir_p(File.dirname(tmp))

      File.write(tmp, '# self-test')
      record('File write (tmp)', File.exist?(tmp))

      File.write(tmp, File.read(tmp).sub('# self-test', '# self-test passed'))
      record('File edit (tmp)', File.read(tmp).include?('# self-test passed'))

      File.delete(tmp)
      record('File cleanup (tmp)', !File.exist?(tmp))
    end

    # ── 2. Search ───────────────────────────────────────────────────

    def check_search
      rb_files = Dir.glob(File.join(project_root, 'lib/**/*.rb'))
      record('Glob lib/**/*.rb', rb_files.size >= 50, "#{rb_files.size} files")

      base_classes = rb_files.count { |f| File.read(f).match?(/class.*Base/) }
      record('Grep class.*Base', base_classes >= 3, "#{base_classes} matches")
    rescue StandardError => e
      record('Search', false, e.message)
    end

    # ── 3. Bash ─────────────────────────────────────────────────────

    def check_bash
      ruby_v = `ruby --version 2>&1`.strip
      record('Bash: ruby --version', ruby_v.include?('ruby'), ruby_v)

      rubocop_v = `bundle exec rubocop --version 2>&1`.strip
      record('Bash: rubocop --version', rubocop_v.match?(/\d+\.\d+/), rubocop_v)
    rescue StandardError => e
      record('Bash', false, e.message)
    end

    # ── 4. Git ──────────────────────────────────────────────────────

    def check_git
      run_cmd('git status --short')
      record('Git status', true)

      log = run_cmd('git log --oneline -3')
      record('Git log', log.match?(/^[0-9a-f]+/), log.lines.first&.strip)

      run_cmd('git diff --stat')
      record('Git diff', true)
    rescue StandardError => e
      record('Git', false, e.message)
    end

    # ── 5. Specs ────────────────────────────────────────────────────

    def check_specs
      %w[
        spec/rubyn_code/tools/output_compressor_spec.rb
        spec/rubyn_code/llm/model_router_spec.rb
      ].each { |spec| run_single_spec(spec) }
    rescue StandardError => e
      record('Specs', false, e.message)
    end

    def run_single_spec(spec)
      path = File.join(project_root, spec)
      unless File.exist?(path)
        record("RSpec: #{File.basename(spec)}", false, 'file not found')
        return
      end
      output = run_cmd("bundle exec rspec #{path} --format progress 2>&1")
      record("RSpec: #{File.basename(spec)}", output.include?('0 failures'))
    end

    # ── 6. Output Compressor ────────────────────────────────────────

    def check_compressor_strategies
      compressor = Tools::OutputCompressor.new
      verified = 0

      verified += verify_head_tail(compressor)
      verified += verify_spec_summary(compressor)
      verified += verify_top_matches(compressor)
      verified += verify_tree_collapse(compressor)
      verified += verify_diff_hunks(compressor)

      record('Compression strategies verified', verified >= 3, "#{verified}/5 active")
    rescue StandardError => e
      record('Output compressor', false, e.message)
    end

    def verify_head_tail(compressor)
      big = (1..5000).to_a.join("\n")
      compressed = compressor.compress('bash', big)
      pass = compressed.length < big.length
      record('Compressor: head_tail', pass)
      pass ? 1 : 0
    end

    def verify_spec_summary(compressor)
      spec_out = run_cmd(
        'bundle exec rspec spec/rubyn_code/tools/base_spec.rb --format documentation 2>&1'
      )
      compressed = compressor.compress('run_specs', spec_out)
      pass = compressed.length < spec_out.length || compressed.include?('0 failures')
      record('Compressor: spec_summary', pass)
      pass ? 1 : 0
    end

    def verify_top_matches(compressor)
      grep_out = rb_files_with_def.join("\n")
      compressed = compressor.compress('grep', grep_out)
      pass = compressed.length <= grep_out.length
      record('Compressor: top_matches', pass)
      pass ? 1 : 0
    end

    def verify_tree_collapse(compressor)
      all_rb = Dir.glob(File.join(project_root, '**/*.rb')).join("\n")
      compressed = compressor.compress('glob', all_rb)
      pass = compressed.length <= all_rb.length
      record('Compressor: tree_collapse', pass)
      pass ? 1 : 0
    end

    def verify_diff_hunks(compressor)
      diff = run_cmd('git log --oneline -1 --format=%H | xargs -I{} git diff {}~5..{} 2>/dev/null')
      if diff.strip.empty?
        record('Compressor: diff_hunks', true, 'SKIP — diff too small')
        return 0
      end
      pass = compressor.compress('git_diff', diff).length <= diff.length
      record('Compressor: diff_hunks', pass)
      pass ? 1 : 0
    end

    # ── 7. Skills ───────────────────────────────────────────────────

    def check_skills
      catalog = Skills::Catalog.new(project_root)
      skills = catalog.available
      record('Skills catalog', skills.size >= 10, "#{skills.size} skills")
    rescue StandardError => e
      record('Skills', false, e.message)
    end

    # ── 8. Config ───────────────────────────────────────────────────

    def check_config
      config_path = File.expand_path('~/.rubyn-code/config.yml')
      if File.exist?(config_path)
        record('Config (config.yml)', File.read(config_path).include?('provider'))
      else
        record('Config (config.yml)', false, 'not found')
      end

      profile = File.join(project_root, '.rubyn-code/project_profile.yml')
      record('Config (project_profile)', File.exist?(profile),
             File.exist?(profile) ? 'exists' : 'SKIP — first session')
    rescue StandardError => e
      record('Config', false, e.message)
    end

    # ── 9. Codebase Index ───────────────────────────────────────────

    def check_codebase_index
      path = File.join(project_root, '.rubyn-code/codebase_index.json')
      record('Codebase index', File.exist?(path),
             File.exist?(path) ? 'exists' : 'SKIP — first session')
    rescue StandardError => e
      record('Codebase index', false, e.message)
    end

    # ── 10. Slash Commands ──────────────────────────────────────────

    def check_slash_commands
      cmd_dir = File.join(project_root, 'lib/rubyn_code/cli/commands')
      infra = %w[base.rb context.rb registry.rb]
      cmds = Dir.glob(File.join(cmd_dir, '*.rb')).reject { |f| infra.include?(File.basename(f)) }
      record('Slash commands', cmds.size >= 15, "#{cmds.size} commands")
    rescue StandardError => e
      record('Slash commands', false, e.message)
    end

    # ── 11. Architecture ────────────────────────────────────────────

    def check_architecture
      check_autoloads
      check_layer_dirs
      check_core_modules
    rescue StandardError => e
      record('Architecture', false, e.message)
    end

    def check_autoloads
      content = File.read(File.join(project_root, 'lib/rubyn_code.rb'))
      autoloads = content.scan('autoload').size
      record('Autoload entries', autoloads >= 40, "#{autoloads} entries")
    end

    def check_layer_dirs
      dirs = Dir.glob(File.join(project_root, 'lib/rubyn_code/*/'))
      record('Layer directories', dirs.size >= 14, "#{dirs.size} dirs")
    end

    def check_core_modules
      content = File.read(File.join(project_root, 'lib/rubyn_code.rb'))
      core = %w[Agent Tools Context Skills Memory Observability Learning]
      found = core.select { |m| content.include?("module #{m}") }
      record('Core modules', found.size == core.size, "#{found.size}/#{core.size}")
    end

    # ── Helpers ─────────────────────────────────────────────────────

    def record(name, passed, detail = nil)
      @results << Result.new(name: name, passed: passed, detail: detail)
    end

    def run_cmd(cmd)
      `cd #{project_root} && #{cmd} 2>&1`.strip
    end

    def rb_files_with_def
      Dir.glob(File.join(project_root, 'lib/**/*.rb')).flat_map do |f|
        File.readlines(f).select { |l| l.include?('def ') }.map { |l| "#{f}:#{l.strip}" }
      end
    end

    def print_scorecard
      puts
      puts 'Rubyn Self-Test Results'
      puts '=' * 50
      results.each_with_index { |r, i| print_result(r, i + 1) }
      print_summary
    end

    def print_result(result, num)
      icon = result.passed ? "\e[32m✅\e[0m" : "\e[31m❌\e[0m"
      suffix = result.detail ? " — #{result.detail}" : ''
      puts format(' %2<num>d. %<icon>s %<name>s%<suffix>s',
                  num: num, icon: icon, name: result.name, suffix: suffix)
    end

    def print_summary
      passed = results.count(&:passed)
      total = results.size
      pct = total.positive? ? (passed * 100.0 / total).round : 0
      failed = total - passed

      puts '=' * 50
      if failed.zero?
        puts "\e[32mScore: #{passed}/#{total} (#{pct}%) — All systems go!\e[0m"
      else
        puts "\e[33mScore: #{passed}/#{total} (#{pct}%) — #{failed} failures\e[0m"
      end
      puts
    end
  end
  # rubocop:enable Metrics/ClassLength
end
