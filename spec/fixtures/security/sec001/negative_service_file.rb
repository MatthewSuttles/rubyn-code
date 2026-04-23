# frozen_string_literal: true

# Negative fixture: service object (not a controller, should not apply)
class Users::RegistrationService
  def initialize(params)
    @params = params
  end

  def call
    User.create!(@params.slice(:name, :email, :password))
  end
end
