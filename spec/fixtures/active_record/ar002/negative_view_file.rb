# frozen_string_literal: true

# Negative fixture: helper file (not app/ Ruby, just a lib helper)
# Even if it mentions update_column it shouldn't match applies_to?
# because this file would live outside app/
class DataExporter
  def export_users
    users = User.all.map { |u| { name: u.name, email: u.email } }
    generate_csv(users)
  end
end
