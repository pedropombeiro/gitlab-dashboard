class ScheduleSubscribedUsersCacheRefreshJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(*_args) {}
  queue_as :default

  def perform(*_args)
    service = MergeRequestsCacheService.new
    usernames = GitlabUser
      .joins(:web_push_subscriptions)
      .where.not(id: GitlabUser.recently_active.select(:id))
      .distinct
      .order_by_contacted_at_desc
      .limit(10)
      .pluck(:username)

    Rails.logger.info "[ScheduleSubscribedUsersCacheRefreshJob] Processing #{usernames.count} subscribed users: #{usernames.join(", ")}"

    usernames.each do |author|
      %i[open merged].each do |type|
        MergeRequestsFetchJob.perform_later(author, type) if service.needs_scheduled_update?(author, type)
      end
    end
  end
end
