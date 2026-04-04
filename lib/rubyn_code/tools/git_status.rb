# frozen_string_literal: true

require "open3"
require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class GitStatus < Base
      TOOL_NAME = "git_status"
      DESCRIPTION = "Show the current git status — modified, staged, and untracked files."
      PARAMETERS = {}.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def execute(**_params)
        validate_git_repo!

        branch = current_branch
        status_output = git_status

        lines = ["Branch: #{branch}\n"]

        if status_output.strip.empty?
          lines << "Working tree is clean — nothing to commit."
        else
          lines << status_output
        end

        lines.join("\n")
      end

      private

      def validate_git_repo!
        _, _, status = safe_capture3("git", "rev-parse", "--is-inside-work-tree", chdir: project_root)
        unless status.success?
          raise Error, "Not a git repository: #{project_root}"
        end
      end

      def current_branch
        stdout, _, status = safe_capture3("git", "branch", "--show-current", chdir: project_root)
        status.success? && !stdout.strip.empty? ? stdout.strip : "HEAD (detached)"
      end

      def git_status
        stdout, stderr, status = safe_capture3("git", "status", "--short", chdir: project_root)
        unless status.success?
          raise Error, "git status failed: #{stderr.strip}"
        end

        stdout
      end
    end

    Registry.register(GitStatus)
  end
end
