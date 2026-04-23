# frozen_string_literal: true

# Negative fixture: add_column for a non-foreign-key column (no _id suffix)
class AddTitleToPosts < ActiveRecord::Migration[7.0]
  def change
    add_column :posts, :title, :string
    add_column :posts, :body, :text
    add_column :posts, :published, :boolean, default: false
  end
end
