# frozen_string_literal: true

module RubynCode
  module Tasks
    Task = Data.define(
      :id, :session_id, :title, :description, :status,
      :priority, :owner, :result, :metadata, :created_at, :updated_at
    ) do
      def pending? = status == 'pending'
      def in_progress? = status == 'in_progress'
      def completed? = status == 'completed'
      def blocked? = status == 'blocked'
      def failed? = status == 'failed'

      def to_h
        {
          id: id,
          session_id: session_id,
          title: title,
          description: description,
          status: status,
          priority: priority,
          owner: owner,
          result: result,
          metadata: metadata,
          created_at: created_at,
          updated_at: updated_at
        }
      end
    end
  end
end
