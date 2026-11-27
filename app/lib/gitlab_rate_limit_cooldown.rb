# frozen_string_literal: true

require "time"

class GitlabRateLimitCooldown
  FALLBACK_DELAY = 1.minute

  def self.active?
    Rails.cache.exist?(cache_key)
  end

  def self.record(headers)
    now = Time.current
    headers = Faraday::Utils::Headers.new(headers)
    retry_at = retry_after_time(headers["Retry-After"], now)
    reset_at = integer_header(headers["RateLimit-Reset"])
    deadline = [retry_at, reset_at && Time.zone.at(reset_at)].compact.find { |time| time > now } || now + FALLBACK_DELAY

    # A later response with missing headers should not shorten an existing cooldown.
    current_deadline = Rails.cache.read(cache_key)
    return if current_deadline && current_deadline >= deadline

    Rails.cache.write(cache_key, deadline, expires_at: deadline)
  end

  private_class_method def self.retry_after_time(value, now)
    return if value.blank?

    seconds = integer_header(value)
    seconds ? now + seconds : Time.httpdate(value)
  rescue ArgumentError
    nil
  end

  private_class_method def self.integer_header(value)
    digits = value.to_s.strip
    digits.to_i if digits.match?(/\A[0-9]+\z/)
  end

  private_class_method def self.cache_key
    "#{ENV.fetch("REDIS_NAMESPACE", "gitlab_dashboard")}/gitlab_rate_limit/#{GitlabClient.gitlab_instance_url}"
  end
end
