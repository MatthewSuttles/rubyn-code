# frozen_string_literal: true

require 'open3'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class GitLog < Base
      TOOL_NAME = 'git_log'
      DESCRIPTION = 'Show recent git commit history.'
      PARAMETERS = {
        count: { type: :integer, required: false, default: 20, description: 'Number of commits to show (default: 20)' },
        branch: { type: :string, required: false, description: 'Branch name to show log for (default: current branch)' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def execute(count: 20, branch: nil)
        validate_git_repo!
        stdout = run_git_log(count.to_i.clamp(1, 200), branch)
        format_log_output(stdout, branch)
      end

      private

      def run_git_log(count, branch)
        cmd = ['git', 'log', '--oneline', "-#{count}"]
        cmd << branch unless branch.nil? || branch.strip.empty?

        stdout, stderr, status = safe_capture3(*cmd, chdir: project_root)
        raise Error, "git log failed: #{stderr.strip}" unless status.success?

        stdout
      end

      def format_log_output(stdout, branch)
        return 'No commits found.' if stdout.strip.empty?

        display_branch = branch || current_branch
        truncate("Commit history (#{display_branch}):\n\n#{stdout}", max: 50_000)
      end

      def validate_git_repo!
        _, _, status = safe_capture3('git', 'rev-parse', '--is-inside-work-tree', chdir: project_root)
        return if status.success?

        raise Error, "Not a git repository: #{project_root}"
      end

      def current_branch
        stdout, _, status = safe_capture3('git', 'branch', '--show-current', chdir: project_root)
        status.success? && !stdout.strip.empty? ? stdout.strip : 'HEAD (detached)'
      end
    end

    Registry.register(GitLog)
  end
end
