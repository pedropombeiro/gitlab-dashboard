# frozen_string_literal: true

require "async"

class MergeRequestsCacheService
  include CacheConcern

  def self.cache_validity
    if Rails.application.config.action_controller.perform_caching
      MR_CACHE_VALIDITY
    else
      1.minute
    end
  end

  def needs_scheduled_update?(assignee)
    response = read(assignee)

    return true unless response&.next_scheduled_update_at

    response.next_scheduled_update_at.past?
  end

  def read(assignee)
    Rails.cache.read(self.class.last_authored_mr_lists_cache_key(assignee))
  end

  def write(assignee, response)
    Rails.cache.write(self.class.last_authored_mr_lists_cache_key(assignee), response, expires_in: 1.week)
  end
end
