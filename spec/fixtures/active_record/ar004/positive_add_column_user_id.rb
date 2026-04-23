# frozen_string_literal: true

# Positive fixture: add_column with _id column and no add_index
class AddUserIdToOrders < ActiveRecord::Migration[7.0]
  def change
    add_column :orders, :user_id, :integer
  end
end
