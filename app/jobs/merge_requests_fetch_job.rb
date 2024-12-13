class MergeRequestsFetchJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(assignee) { assignee }
  queue_as :background

  def perform(assignee)
    fetch_service = Services::FetchMergeRequestsService.new(assignee)
    Services::GenerateNotificationsService.new(assignee, fetch_service).execute
  end
end
