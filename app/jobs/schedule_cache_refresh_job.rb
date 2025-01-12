class ScheduleCacheRefreshJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(*_args) {}
  queue_as :default

  def perform(*_args)
    service = MergeRequestsCacheService.new

    scope
      .pluck(:username)
      .each do |author|
        %i[open merged]
          .select { |type| service.needs_scheduled_update?(author, type) }
          .each { |type| MergeRequestsFetchJob.perform_later(author, type) }
      end
  end

  private

  def scope
    GitlabUser
      .recently_active
      .order_by_contacted_at_desc
      .limit(10) # Limit to 10 users for the time being, to avoid any DoS attacks
  end
end
