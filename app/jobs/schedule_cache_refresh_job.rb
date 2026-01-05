class ScheduleCacheRefreshJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(*_args) {}
  queue_as :default

  def perform(*_args)
    service = MergeRequestsCacheService.new
    usernames = scope.pluck(:username)

    Rails.logger.info "[ScheduleCacheRefreshJob] Processing #{usernames.count} recently active users: #{usernames.join(", ")}"

    usernames.each do |author|
      types_needing_update = %i[open merged].select { |type| service.needs_scheduled_update?(author, type) }

      if types_needing_update.any?
        Rails.logger.debug { "[ScheduleCacheRefreshJob] Enqueuing jobs for #{author}: #{types_needing_update.join(", ")}" }
        types_needing_update.each { |type| MergeRequestsFetchJob.perform_later(author, type) }
      else
        Rails.logger.debug { "[ScheduleCacheRefreshJob] No updates needed for #{author} (cache still fresh)" }
      end
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
