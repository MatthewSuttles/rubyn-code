# frozen_string_literal: true

# Negative fixture: bare add_reference defaults to index: true in Rails 5+
class AddUserToOrders < ActiveRecord::Migration[7.0]
  def change
    add_reference :orders, :user
  end
end
