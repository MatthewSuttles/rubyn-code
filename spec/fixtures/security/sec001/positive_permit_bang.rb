# frozen_string_literal: true

# Positive fixture: permit! on params (permits everything)
class UsersController < ApplicationController
  def create
    @user = User.new(params.permit!)
    @user.save
  end
end
