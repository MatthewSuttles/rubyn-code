# frozen_string_literal: true

# Positive fixture: update_column bypasses validations
class User < ApplicationRecord
  def mark_verified!
    update_column(:verified, true)
  end
end
