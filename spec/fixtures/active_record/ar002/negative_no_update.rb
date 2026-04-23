# frozen_string_literal: true

# Negative fixture: model with no update calls at all
class Order < ApplicationRecord
  belongs_to :user
  has_many :line_items

  validates :total, numericality: { greater_than: 0 }

  def completed?
    status == "completed"
  end
end
