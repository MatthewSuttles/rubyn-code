# frozen_string_literal: true

require 'open3'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class GitCommit < Base
      TOOL_NAME = 'git_commit'
      DESCRIPTION = "Stage files and create a git commit. Specify files to stage or use 'all' to stage everything."
      PARAMETERS = {
        message: { type: :string, required: true, description: 'The commit message' },
        files: { type: :string, required: false, default: 'all',
                 description: "Space-separated file paths to stage, or 'all' to stage everything (git add -A)" }
      }.freeze
      RISK_LEVEL = :write
      REQUIRES_CONFIRMATION = true

      def execute(message:, files: 'all')
        validate_git_repo!
        validate_message!(message)

        stage_files(files)
        create_commit(message)
      end

      private

      def validate_git_repo!
        _, _, status = safe_capture3('git', 'rev-parse', '--is-inside-work-tree', chdir: project_root)
        return if status.success?

        raise Error, "Not a git repository: #{project_root}"
      end

      def validate_message!(message)
        return unless message.nil? || message.strip.empty?

        raise Error, 'Commit message cannot be empty'
      end

      def stage_files(files)
        if files.strip.downcase == 'all'
          _, stderr, status = safe_capture3('git', 'add', '-A', chdir: project_root)
        else
          file_list = files.split(/\s+/).reject(&:empty?)
          raise Error, 'No files specified to stage' if file_list.empty?

          _, stderr, status = safe_capture3('git', 'add', '--', *file_list, chdir: project_root)
        end

        return if status.success?

        raise Error, "Failed to stage files: #{stderr.strip}"
      end

      def create_commit(message)
        stdout, stderr, status = safe_capture3('git', 'commit', '-m', message, chdir: project_root)

        unless status.success?
          output = "#{stdout}\n#{stderr}"
          return 'Nothing to commit — working tree is clean.' if output.include?('nothing to commit')

          raise Error, "Commit failed: #{stderr.strip.empty? ? stdout.strip : stderr.strip}"
        end

        # Extract the commit hash from the output
        commit_hash = extract_commit_hash
        branch = current_branch

        lines = ["Committed on branch: #{branch}"]
        lines << "Commit: #{commit_hash}" if commit_hash
        lines << ''
        lines << stdout.strip

        lines.join("\n")
      end

      def extract_commit_hash
        stdout, _, status = safe_capture3('git', 'rev-parse', '--short', 'HEAD', chdir: project_root)
        status.success? ? stdout.strip : nil
      end

      def current_branch
        stdout, _, status = safe_capture3('git', 'branch', '--show-current', chdir: project_root)
        status.success? && !stdout.strip.empty? ? stdout.strip : 'HEAD (detached)'
      end
    end

    Registry.register(GitCommit)
  end
end
