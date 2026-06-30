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
    end
  end
end
