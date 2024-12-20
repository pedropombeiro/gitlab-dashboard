class ScheduleCacheRefreshJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(*_args) {}
  queue_as :default

  def perform(*_args)
    service = Services::MergeRequestsCacheService.new

    scope
      .pluck(:username)
      .select { |assignee| service.needs_scheduled_update?(assignee) }
      .each { |assignee| MergeRequestsFetchJob.perform_later(assignee) }
  end

  private

  def scope
    GitlabUser
      .recently_active
      .order_by_contacted_at_desc
      .limit(10) # Limit to 10 users for the time being, to avoid any DoS attacks
  end
end
