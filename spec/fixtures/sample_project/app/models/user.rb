class User < ApplicationRecord
  has_many :posts, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
end
