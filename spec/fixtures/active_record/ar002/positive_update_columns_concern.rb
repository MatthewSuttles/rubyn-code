# frozen_string_literal: true

# Positive fixture: update_columns inside a concern
module Trackable
  extend ActiveSupport::Concern

  def record_last_activity
    update_columns(last_active_at: Time.current, activity_count: activity_count + 1)
  end
end
