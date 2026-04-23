# frozen_string_literal: true

# Positive fixture: add_column with _id column and options but no add_index
class AddOrganizationIdToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :organization_id, :bigint, null: false, default: 0
  end
end
