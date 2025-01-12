class MergeRequestsFetchJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(author, type) { author }
  queue_as :background

  def perform(author, type)
    fetch_service = FetchMergeRequestsService.new(author)
    GenerateNotificationsService.new(author, type, fetch_service).execute
  end
end
