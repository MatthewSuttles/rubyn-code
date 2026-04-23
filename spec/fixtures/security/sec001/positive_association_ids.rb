# frozen_string_literal: true

# Positive fixture: association _ids array (can manipulate associations)
class MembershipsController < ApplicationController
  def update
    @user = User.find(params[:id])
    @user.update(user_params)
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, role_ids: [])
  end
end
