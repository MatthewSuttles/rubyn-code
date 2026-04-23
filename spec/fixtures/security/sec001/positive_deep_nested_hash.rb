# frozen_string_literal: true

# Positive fixture: deep nested hash permits all nested keys
class TeamsController < ApplicationController
  def create
    @team = Team.new(team_params)
    @team.save
  end

  private

  def team_params
    params.require(:team).permit(:name, settings: {})
  end
end
