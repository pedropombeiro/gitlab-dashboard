class MergeRequestsFetchJob < ApplicationJob
  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(author, type) { author }
  queue_as :background

  def perform(author, type)
    Rails.logger.debug { "[MergeRequestsFetchJob] Starting job for #{author}/#{type}" }

    fetch_service = FetchMergeRequestsService.new(author)
    response, _dto = GenerateNotificationsService.new(author, type, fetch_service).execute

    Rails.logger.debug { "[MergeRequestsFetchJob] Completed fetch for #{author}/#{type}, response.errors: #{response.errors.inspect}" }
  rescue => e
    Rails.logger.error "[MergeRequestsFetchJob] Exception in job for #{author}/#{type}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
