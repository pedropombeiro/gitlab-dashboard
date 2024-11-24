class MergeRequestsFetchJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(assignee) { assignee }
  queue_as :background

  def perform(assignee)
    service = Services::FetchMergeRequestsService.new(assignee)
    service.execute if service.needs_scheduled_update?
  end
end
