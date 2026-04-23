# frozen_string_literal: true

# Positive fixture: add_reference with foreign_key but no explicit index option
class AddProjectToTasks < ActiveRecord::Migration[7.0]
  def change
    add_reference :tasks, :project, foreign_key: true
  end
end
