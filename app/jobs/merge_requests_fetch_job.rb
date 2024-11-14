class MergeRequestsFetchJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(assignee) { assignee }
  queue_as :background

  def perform(assignee)
    Services::FetchMergeRequestsService.new(assignee).execute
  end
end
