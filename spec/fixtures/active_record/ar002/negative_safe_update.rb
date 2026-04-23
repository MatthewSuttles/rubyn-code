# frozen_string_literal: true

# Negative fixture: safe update methods (no bypass)
class User < ApplicationRecord
  def update_profile(attrs)
    update(attrs)
  end

  def update_email!(new_email)
    update!(email: new_email)
  end

  def save_changes
    self.name = "Updated"
    save
  end
end
