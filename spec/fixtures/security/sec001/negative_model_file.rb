# frozen_string_literal: true

# Negative fixture: model file (not a controller, should not apply)
class User < ApplicationRecord
  has_many :orders
  has_many :roles

  validates :email, presence: true, uniqueness: true

  def admin?
    roles.exists?(name: "admin")
  end
end
