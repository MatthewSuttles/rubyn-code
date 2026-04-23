# frozen_string_literal: true

# Negative fixture: add_column with _id column paired with add_index
class AddTeamIdToProjects < ActiveRecord::Migration[7.0]
  def change
    add_column :projects, :team_id, :integer
    add_index :projects, :team_id
  end
end
