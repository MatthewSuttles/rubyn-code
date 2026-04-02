class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]

  def index
    @users = User.active.order(created_at: :desc)
  end

  def show; end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to @user, notice: "User created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email)
  end
end
