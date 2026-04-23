# frozen_string_literal: true

# Positive fixture: multiple add_column calls with _id columns, only one indexed
class AddForeignKeysToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :customer_id, :integer
    add_column :invoices, :account_id, :integer
    add_index :invoices, :customer_id
    # account_id is missing an index
  end
end
