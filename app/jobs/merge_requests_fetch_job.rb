class MergeRequestsFetchJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(author, type) { author }
  queue_as :background

  def perform(author, type)
    fetch_service = FetchMergeRequestsService.new(author)
    response, dto = GenerateNotificationsService.new(author, type, fetch_service).execute

    # Broadcast real-time update to connected clients via Turbo Streams
    if response.errors.nil?
      Rails.logger.info "[MergeRequestsFetchJob] Broadcasting update for #{author}/#{type}"
      MergeRequestBroadcaster.broadcast_update(author, type, dto)
    else
      Rails.logger.warn "[MergeRequestsFetchJob] Skipping broadcast for #{author}/#{type} due to errors: #{response.errors}"
    end
  end
end
