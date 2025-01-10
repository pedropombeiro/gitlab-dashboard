class MergeRequestsFetchJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(assignee, type) { assignee }
  queue_as :background

  def perform(assignee, type)
    fetch_service = FetchMergeRequestsService.new(assignee)
    GenerateNotificationsService.new(assignee, type, fetch_service).execute
  end
end
