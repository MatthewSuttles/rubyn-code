# frozen_string_literal: true

# Positive fixture: add_column with bigint _id column and no add_index
class AddCategoryIdToPosts < ActiveRecord::Migration[7.0]
  def change
    add_column :posts, :category_id, :bigint, null: false
  end
end
