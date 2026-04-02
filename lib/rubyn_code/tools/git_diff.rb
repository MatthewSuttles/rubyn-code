# frozen_string_literal: true

require "open3"
require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class GitDiff < Base
      TOOL_NAME = "git_diff"
      DESCRIPTION = "Show git diff for staged, unstaged, or between branches/commits."
      PARAMETERS = {
        target: { type: :string, required: false, default: "unstaged", description: 'What to diff: "staged", "unstaged", or a branch/commit ref (default: "unstaged")' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      MAX_DIFF_LENGTH = 80_000

      def execute(target: "unstaged")
        validate_git_repo!

        cmd = build_diff_command(target.to_s.strip)
        stdout, stderr, status = Open3.capture3(*cmd, chdir: project_root)

        unless status.success?
          raise Error, "git diff failed: #{stderr.strip}"
        end

        if stdout.strip.empty?
          "No differences found for target: #{target}"
        else
          header = "git diff (#{target}):\n\n"
          truncate("#{header}#{stdout}", max: MAX_DIFF_LENGTH)
        end
      end

      private

      def validate_git_repo!
        _, _, status = Open3.capture3("git", "rev-parse", "--is-inside-work-tree", chdir: project_root)
        unless status.success?
          raise Error, "Not a git repository: #{project_root}"
        end
      end

      def build_diff_command(target)
        case target.downcase
        when "staged", "cached"
          %w[git diff --cached]
        when "unstaged", ""
          %w[git diff]
        else
          ["git", "diff", target]
        end
      end
    end

    Registry.register(GitDiff)
  end
end
