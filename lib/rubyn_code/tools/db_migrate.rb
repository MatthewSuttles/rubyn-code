# frozen_string_literal: true

require "open3"
require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class DbMigrate < Base
      TOOL_NAME = "db_migrate"
      DESCRIPTION = "Runs Rails database migrations (up) or rollback (down)."
      PARAMETERS = {
        direction: { type: :string, required: false, default: "up", enum: %w[up down], description: "Migration direction: 'up' to migrate, 'down' to rollback (default: 'up')" },
        steps: { type: :integer, required: false, description: "Number of steps to rollback (only used with direction 'down')" }
      }.freeze
      RISK_LEVEL = :execute
      REQUIRES_CONFIRMATION = false

      def execute(direction: "up", steps: nil)
        command = build_command(direction, steps)
        stdout, stderr, status = Open3.capture3(command, chdir: project_root)

        build_output(stdout, stderr, status)
      end

      private

      def build_command(direction, steps)
        case direction
        when "up"
          "bundle exec rails db:migrate"
        when "down"
          cmd = "bundle exec rails db:rollback"
          cmd += " STEP=#{steps.to_i}" if steps && steps.to_i > 0
          cmd
        else
          raise Error, "Invalid direction: #{direction}. Must be 'up' or 'down'."
        end
      end

      def build_output(stdout, stderr, status)
        parts = []
        parts << stdout unless stdout.empty?
        parts << "STDERR:\n#{stderr}" unless stderr.empty?
        parts << "Exit code: #{status.exitstatus}" unless status.success?
        parts.empty? ? "(no output)" : parts.join("\n")
      end
    end

    Registry.register(DbMigrate)
  end
end
