# frozen_string_literal: true

# Positive fixture: update_all on a scoped query
class UserCleanupService
  def deactivate_stale_users
    User.where("last_sign_in_at < ?", 1.year.ago).update_all(active: false)
  end
end
