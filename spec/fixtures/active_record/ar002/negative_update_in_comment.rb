# frozen_string_literal: true

# Negative fixture: mentions bypass methods in comments but uses safe update
class User < ApplicationRecord
  # WARNING: Do not use column-bypass methods here.
  # Always use the safe update method instead.
  def grant_admin_access
    update(admin: true)
  end
end
