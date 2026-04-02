# frozen_string_literal: true

module RubynCode
  module Background
    Job = Data.define(:id, :command, :status, :result, :started_at, :completed_at) do
      def running?   = status == :running
      def completed? = status == :completed
      def error?     = status == :error
      def timeout?   = status == :timeout

      def duration
        return nil unless started_at
        return nil if running?

        (completed_at || Time.now) - started_at
      end
    end
  end
end
