class MergeRequestsFetchJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(author, type) { author }
  queue_as :background

  def perform(author, type)
    fetch_service = FetchMergeRequestsService.new(author)
    response, dto = GenerateNotificationsService.new(author, type, fetch_service).execute

    # Broadcast real-time update to connected clients via Turbo Streams
    MergeRequestBroadcaster.broadcast_update(author, type, dto) if response.errors.nil?
  end
end
