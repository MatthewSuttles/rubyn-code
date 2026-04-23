# frozen_string_literal: true

# Negative fixture: model file, not a migration
class Order < ApplicationRecord
  belongs_to :user
  belongs_to :product

  validates :quantity, presence: true
end
