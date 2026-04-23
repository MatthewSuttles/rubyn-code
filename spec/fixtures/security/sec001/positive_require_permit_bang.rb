# frozen_string_literal: true

# Positive fixture: permit! after require (permits all user attrs)
class AccountsController < ApplicationController
  def update
    @account = Account.find(params[:id])
    @account.update(params.require(:account).permit!)
  end
end
