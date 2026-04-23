# frozen_string_literal: true

# Positive fixture: add_reference with index: false explicitly disables the default index
class AddUserToComments < ActiveRecord::Migration[7.0]
  def change
    add_reference :comments, :user, index: false
  end
end
