# frozen_string_literal: true

# Positive fixture: update_columns bypasses validations
class User < ApplicationRecord
  def promote_to_admin!
    update_columns(role: "admin", promoted_at: Time.current)
  end
end
