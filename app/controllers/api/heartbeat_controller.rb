# frozen_string_literal: true

class Api::HeartbeatController < ApplicationController
  before_action :require_user

  # Lightweight endpoint to keep user's contacted_at timestamp fresh
  # Called periodically by browser to ensure background jobs continue processing for active users
  def create
    current_user.update_columns(contacted_at: Time.current)

    head :no_content
  end

  private

  def require_user
    head :unauthorized unless current_user
  end
end
