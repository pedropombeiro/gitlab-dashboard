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

    unless response&.next_scheduled_update_at
      Rails.logger.debug { "[MergeRequestsCacheService] No cache found for #{author}/#{type}, needs update" }
      return true
    end

    needs_update = response.next_scheduled_update_at.past?
    time_until_update = (response.next_scheduled_update_at - Time.current).round

    if needs_update
      Rails.logger.debug { "[MergeRequestsCacheService] Cache expired for #{author}/#{type} (#{time_until_update}s ago)" }
    else
      Rails.logger.debug { "[MergeRequestsCacheService] Cache fresh for #{author}/#{type} (next update in #{time_until_update}s)" }
    end

    needs_update
  end

  def read(author, type)
    Rails.cache.read(self.class.last_authored_mr_lists_cache_key(author, type))
  end

  def write(author, type, response)
    Rails.cache.write(self.class.last_authored_mr_lists_cache_key(author, type), response, expires_in: 1.week)
  end
end
