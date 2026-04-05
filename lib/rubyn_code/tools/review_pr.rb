# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class ReviewPr < Base
      TOOL_NAME = 'review_pr'
      DESCRIPTION = 'Review current branch changes against Ruby/Rails best practices. ' \
                    'Gets the diff of the current branch vs the base branch, analyzes ' \
                    'each changed file, and provides actionable suggestions with explanations.'
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
        error = validate_git_repo
        return error if error

        current = current_branch_name
        return current if current.start_with?('Error:')

        base_branch, error = resolve_base(base_branch, current)
        return error if error

        diff = run_git("diff #{base_branch}...HEAD")
        return "No changes found between #{current} and #{base_branch}." if diff.strip.empty?

        build_full_review(current, base_branch, diff, focus)
      end

      FILE_CATEGORIES = [
        ['Ruby',       /\.(rb|rake|gemspec|ru)$/],
        ['Templates',  /\.(erb|haml|slim)$/],
        ['Specs',      /_spec\.rb$|_test\.rb$/],
        ['Migrations', %r{db/migrate}],
        ['Config',     %r{config/|\.ya?ml$}]
      ].freeze

      private

      def validate_git_repo
        return nil if system(
          'git rev-parse --is-inside-work-tree > /dev/null 2>&1',
          chdir: project_root
        )

        'Error: Not a git repository or git is not installed.'
      end

      def current_branch_name
        current = run_git('rev-parse --abbrev-ref HEAD').strip
        return 'Error: Could not determine current branch.' if current.empty?

        current
      end

      def resolve_base(base_branch, current)
        if current == base_branch
          return [nil, "You're on #{base_branch}. Switch to a feature branch " \
                       "or specify a different base: review_pr(base_branch: 'develop')"]
        end

        return [base_branch, nil] if branch_exists?(base_branch)

        origin = "origin/#{base_branch}"
        return [origin, nil] if branch_exists?(origin)

        [nil, "Error: Base branch '#{base_branch}' not found."]
      end

      def build_full_review(current, base_branch, diff, focus)
        review = build_review_header(current, base_branch)
        review.concat(build_file_categories(base_branch))
        review.concat(build_focus_section(focus))
        review.concat(build_diff_section(diff))
        review.concat(build_review_checklist)
        truncate(review.join("\n"))
      end

      def branch_exists?(branch)
        run_git("rev-parse --verify #{branch} 2>/dev/null").strip.length.positive?
      end

      def build_review_header(current, base_branch)
        stat = run_git("diff #{base_branch}...HEAD --stat")
        commit_log = run_git("log #{base_branch}..HEAD --oneline")

        [
          "# PR Review: #{current} -> #{base_branch}",
          '',
          '## Summary',
          stat,
          '',
          '## Commits',
          commit_log,
          ''
        ]
      end

      def build_file_categories(base_branch)
        files = run_git("diff #{base_branch}...HEAD --name-only").strip.split("\n")
        review = ['## Files by Category']
        FILE_CATEGORIES.each do |label, pattern|
          review << "- #{label}: #{files.grep(pattern).length} files"
        end
        review << ''
        review
      end

      def build_focus_section(focus)
        [
          "## Review Focus: #{focus.upcase}",
          review_instructions(focus),
          ''
        ]
      end

      def build_diff_section(diff)
        if diff.length > 40_000
          [
            "## Diff (truncated — #{diff.length} chars total)",
            diff[0...40_000],
            "\n... [truncated #{diff.length - 40_000} chars]"
          ]
        else
          ['## Full Diff', diff]
        end
      end

      def build_review_checklist
        [
          '',
          '---',
          'Review this diff against Ruby/Rails best practices. For each issue found:',
          '1. Quote the specific code',
          "2. Explain what's wrong and WHY it matters",
          '3. Show the suggested fix',
          '4. Rate severity: [critical] [warning] [suggestion] [nitpick]',
          '',
          'Also check for:',
          '- Missing tests for new code',
          '- N+1 queries in ActiveRecord changes',
          '- Security issues (SQL injection, XSS, mass assignment)',
          '- Missing database indexes for new associations',
          '- Proper error handling'
        ]
      end

      def run_git(command)
        `cd #{project_root} && git #{command} 2>/dev/null`
      end

      def review_instructions(focus)
        case focus.to_s.downcase
        when 'security'
          'Focus on: SQL injection, XSS, CSRF, mass assignment, ' \
          'authentication/authorization gaps, sensitive data exposure, ' \
          'insecure dependencies, command injection, path traversal.'
        when 'performance'
          'Focus on: N+1 queries, missing indexes, eager loading, caching ' \
          'opportunities, unnecessary database calls, memory bloat, slow ' \
          'iterations, missing pagination.'
        when 'style'
          'Focus on: Ruby idioms, naming conventions, method length, class ' \
          'organization, frozen string literals, guard clauses, DRY ' \
          'violations, dead code.'
        when 'testing'
          'Focus on: Missing test coverage, test quality, factory usage, ' \
          'assertion quality, test isolation, flaky test risks, edge ' \
          'cases, integration vs unit test balance.'
        else
          'Review all aspects: code quality, security, performance, testing, ' \
          'Rails conventions, Ruby idioms, and architectural patterns.'
        end
      end
    end

    Registry.register(ReviewPr)
  end
end
