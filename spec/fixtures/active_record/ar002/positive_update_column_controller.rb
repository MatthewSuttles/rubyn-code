# frozen_string_literal: true

# Positive fixture: update_column in a controller action
class UsersController < ApplicationController
  def verify
    @user = User.find(params[:id])
    @user.update_column(:email_verified, true)
    redirect_to @user, notice: "Email verified"
  end
end
