# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class ReviewPr < Base
      TOOL_NAME = 'review_pr'
      DESCRIPTION = 'Review current branch changes against Ruby/Rails best practices. ' \
                    'Gets the diff of the current branch vs the base branch, analyzes each changed file, ' \
                    'and provides actionable suggestions with explanations.'
      PARAMETERS = {
        base_branch: {
          type: :string,
          description: 'Base branch to diff against (default: main)',
          required: false
        },
        focus: {
          type: :string,
          description: "Focus area: 'all', 'security', 'performance', 'style', 'testing' (default: all)",
          required: false
        }
      }.freeze
      RISK_LEVEL = :read

      def execute(base_branch: 'main', focus: 'all')
        # Check git is available
        unless system('git rev-parse --is-inside-work-tree > /dev/null 2>&1', chdir: project_root)
          return 'Error: Not a git repository or git is not installed.'
        end

        # Get current branch
        current = run_git('rev-parse --abbrev-ref HEAD').strip
        return 'Error: Could not determine current branch.' if current.empty?

        if current == base_branch
          return "You're on #{base_branch}. Switch to a feature branch first, or specify a different base: review_pr(base_branch: 'develop')"
        end

        # Check base branch exists
        unless run_git("rev-parse --verify #{base_branch} 2>/dev/null").strip.length.positive?
          # Try origin/main
          base_branch = "origin/#{base_branch}"
          unless run_git("rev-parse --verify #{base_branch} 2>/dev/null").strip.length.positive?
            return "Error: Base branch '#{base_branch}' not found."
          end
        end

        # Get the diff
        diff = run_git("diff #{base_branch}...HEAD")
        return "No changes found between #{current} and #{base_branch}." if diff.strip.empty?

        # Get changed files with stats
        stat = run_git("diff #{base_branch}...HEAD --stat")
        files_changed = run_git("diff #{base_branch}...HEAD --name-only").strip.split("\n")
        commit_log = run_git("log #{base_branch}..HEAD --oneline")

        # Build the review context
        ruby_files = files_changed.grep(/\.(rb|rake|gemspec|ru)$/)
        erb_files = files_changed.grep(/\.(erb|haml|slim)$/)
        spec_files = files_changed.grep(/_spec\.rb$|_test\.rb$/)
        migration_files = files_changed.select { |f| f.include?('db/migrate') }
        config_files = files_changed.grep(%r{config/|\.yml$|\.yaml$})

        review = []
        review << "# PR Review: #{current} → #{base_branch}"
        review << ''
        review << '## Summary'
        review << stat
        review << ''
        review << '## Commits'
        review << commit_log
        review << ''
        review << '## Files by Category'
        review << "- Ruby: #{ruby_files.length} files" unless ruby_files.empty?
        review << "- Templates: #{erb_files.length} files" unless erb_files.empty?
        review << "- Specs: #{spec_files.length} files" unless spec_files.empty?
        review << "- Migrations: #{migration_files.length} files" unless migration_files.empty?
        review << "- Config: #{config_files.length} files" unless config_files.empty?
        review << ''

        # Add focus-specific review instructions
        review << "## Review Focus: #{focus.upcase}"
        review << review_instructions(focus)
        review << ''

        # Add the diff (truncated if too large)
        if diff.length > 40_000
          review << "## Diff (truncated — #{diff.length} chars total)"
          review << diff[0...40_000]
          review << "\n... [truncated #{diff.length - 40_000} chars]"
        else
          review << '## Full Diff'
          review << diff
        end

        review << ''
        review << '---'
        review << 'Review this diff against Ruby/Rails best practices. For each issue found:'
        review << '1. Quote the specific code'
        review << "2. Explain what's wrong and WHY it matters"
        review << '3. Show the suggested fix'
        review << '4. Rate severity: [critical] [warning] [suggestion] [nitpick]'
        review << ''
        review << 'Also check for:'
        review << '- Missing tests for new code'
        review << '- N+1 queries in ActiveRecord changes'
        review << '- Security issues (SQL injection, XSS, mass assignment)'
        review << '- Missing database indexes for new associations'
        review << '- Proper error handling'

        truncate(review.join("\n"))
      end

      private

      def run_git(command)
        `cd #{project_root} && git #{command} 2>/dev/null`
      end

      def review_instructions(focus)
        case focus.to_s.downcase
        when 'security'
          'Focus on: SQL injection, XSS, CSRF, mass assignment, authentication/authorization gaps, ' \
          'sensitive data exposure, insecure dependencies, command injection, path traversal.'
        when 'performance'
          'Focus on: N+1 queries, missing indexes, eager loading, caching opportunities, ' \
          'unnecessary database calls, memory bloat, slow iterations, missing pagination.'
        when 'style'
          'Focus on: Ruby idioms, naming conventions, method length, class organization, ' \
          'frozen string literals, guard clauses, DRY violations, dead code.'
        when 'testing'
          'Focus on: Missing test coverage, test quality, factory usage, assertion quality, ' \
          'test isolation, flaky test risks, edge cases, integration vs unit test balance.'
        else
          'Review all aspects: code quality, security, performance, testing, Rails conventions, ' \
          'Ruby idioms, and architectural patterns.'
        end
      end
    end

    Registry.register(ReviewPr)
  end
end
