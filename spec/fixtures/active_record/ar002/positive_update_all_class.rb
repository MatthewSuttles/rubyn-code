# frozen_string_literal: true

# Positive fixture: update_all on a model class directly
class AdminService
  def reset_all_tokens
    User.update_all(auth_token: nil)
  end
end
