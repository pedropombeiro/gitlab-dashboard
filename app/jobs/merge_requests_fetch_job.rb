class MergeRequestsFetchJob < ApplicationJob
  include WebPushConcern

  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(assignee) { assignee }
  queue_as :background

  attr_reader :service

  def initialize
    @service = Services::FetchMergeRequestsService.new(assignee)
  end

  def perform(assignee)
    return unless service.needs_scheduled_update?

    response = service.execute

    # Update badge value
    user = GitlabUser.find_by_username(assignee)
    publish(user, {type: "badge", payload: {value: response.user.openMergeRequests.count}})
  end
end
