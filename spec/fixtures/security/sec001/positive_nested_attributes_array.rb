# frozen_string_literal: true

# Positive fixture: nested _attributes with array (may include privileged fields)
class ProfilesController < ApplicationController
  def update
    @profile = current_user.profile
    @profile.update(profile_params)
  end

  private

  def profile_params
    params.require(:profile).permit(:bio, user_attributes: [:id, :admin, :email])
  end
end
