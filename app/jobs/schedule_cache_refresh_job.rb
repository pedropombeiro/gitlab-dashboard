class ScheduleCacheRefreshJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(*_args) {}
  queue_as :default

  ACTIVE_USER_TIME_WINDOW = 4.hours

  def perform(*_args)
    scope
      .map { |user| Services::FetchMergeRequestsService.new(user) }
      .select(&:needs_scheduled_update?)
      .each { |service| MergeRequestsFetchJob.perform_later(service.assignee) }
  end

  private

  def scope
    GitlabUser
      .where(contacted_at: ACTIVE_USER_TIME_WINDOW.ago..)
      .order(contacted_at: :desc)
      .limit(10) # Limit to 10 users for the time being, to avoid any DoS attacks
  end
end
