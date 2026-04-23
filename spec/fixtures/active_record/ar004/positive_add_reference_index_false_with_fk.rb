# frozen_string_literal: true

# Positive fixture: add_reference with both foreign_key: true and index: false
class AddAuthorToArticles < ActiveRecord::Migration[7.0]
  def change
    add_reference :articles, :author, foreign_key: true, index: false
  end
end
