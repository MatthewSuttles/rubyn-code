# frozen_string_literal: true

require 'open3'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class GitStatus < Base
      TOOL_NAME = 'git_status'
      DESCRIPTION = 'Show the current git status — modified, staged, and untracked files.'
      PARAMETERS = {}.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def execute(**_params)
        validate_git_repo!

        branch = current_branch
        status_output = git_status

        lines = ["Branch: #{branch}\n"]

        lines << if status_output.strip.empty?
                   'Working tree is clean — nothing to commit.'
                 else
                   status_output
                 end

        lines.join("\n")
      end

      private

      def validate_git_repo!
        _, _, status = safe_capture3('git', 'rev-parse', '--is-inside-work-tree', chdir: project_root)
        return if status.success?

        raise Error, "Not a git repository: #{project_root}"
      end

      def current_branch
        stdout, _, status = safe_capture3('git', 'branch', '--show-current', chdir: project_root)
        status.success? && !stdout.strip.empty? ? stdout.strip : 'HEAD (detached)'
      end

      def git_status
        stdout, stderr, status = safe_capture3('git', 'status', '--short', chdir: project_root)
        raise Error, "git status failed: #{stderr.strip}" unless status.success?

        stdout
      end
    end

    Registry.register(GitStatus)
  end
end
