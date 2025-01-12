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

  def needs_scheduled_update?(author, type)
    response = read(author, type)

    return true unless response&.next_scheduled_update_at

    response.next_scheduled_update_at.past?
  end

  def read(author, type)
    Rails.cache.read(self.class.last_authored_mr_lists_cache_key(author, type))
  end

  def write(author, type, response)
    Rails.cache.write(self.class.last_authored_mr_lists_cache_key(author, type), response, expires_in: 1.week)
  end
end
