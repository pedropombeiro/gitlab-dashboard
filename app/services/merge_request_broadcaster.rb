# frozen_string_literal: true

class MergeRequestBroadcaster
  # Broadcasts real-time Turbo Stream updates to connected clients
  # Called after every successful MR data fetch to push updates to browsers
  #
  # Note: Broadcasts on every fetch, not just on changes. This ensures all updates
  # (pipeline status, reviewers, approvals, etc.) are pushed immediately.
  #
  # @param author [String] GitLab username
  # @param type [Symbol] :open or :merged
  # @param dto [UserDto] The parsed DTO containing MR data
  def self.broadcast_update(author, type, dto)
    return if dto.errors.present?

    stream_name = stream_name_for(author, type)
    target_id = ActionView::RecordIdentifier.dom_id(dto, "#{type}_merge_requests")

    # Render the template manually, then broadcast as a Turbo Stream
    # Create a controller instance with proper params and request context
    controller = MergeRequestsController.new
    controller.request = ActionDispatch::Request.new("rack.input" => StringIO.new)
    controller.response = ActionDispatch::Response.new
    controller.params = ActionController::Parameters.new(author: author)
    controller.instance_variable_set(:@dto, dto)

    html = controller.render_to_string(
      template: "merge_requests/#{type}_list",
      layout: false
    )

    # Broadcast the rendered HTML directly as a Turbo Stream message
    # This uses the internal Turbo mechanism that matches turbo_stream_from
    Turbo::StreamsChannel.broadcast_replace_to(
      stream_name,
      target: target_id,
      html: html
    )
  rescue => e
    Rails.logger.error("Failed to broadcast MR update for #{author} (#{type}): #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
  end

  # Generates the Turbo Stream name for broadcasting
  # Matches the helper method in MergeRequestsHelper
  def self.stream_name_for(user, type)
    username = user.is_a?(String) ? user : user.username
    "user_#{username}_#{type}"
  end
  private_class_method :stream_name_for
end
