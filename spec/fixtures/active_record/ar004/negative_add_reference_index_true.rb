# frozen_string_literal: true

# Negative fixture: add_reference with explicit index: true
class AddCategoryToPosts < ActiveRecord::Migration[7.0]
  def change
    add_reference :posts, :category, index: true, foreign_key: true
  end
end
