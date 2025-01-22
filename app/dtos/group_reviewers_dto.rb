# frozen_string_literal: true

class GroupReviewersDto
  extend ActiveModel::Naming

  include ActiveModel::Conversion

  attr_reader :errors, :updated_at, :next_update_at, :request_duration
  attr_reader :group_path, :reviewers

  WORD_NUMERALS_TO_NUMBERS = {
    zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9
  }.freeze

  def initialize(response, group_path)
    @has_content = response.present?
    @group_path = group_path

    unless response
      @reviewers = []
      return
    end

    @errors = response.errors
    @request_duration = response.request_duration
    @updated_at = response.updated_at
    return if @errors

    @next_update_at = response.next_update_at

    reviewers = response.response.data.group.groupMembers.nodes
    warmup_timezone_cache(reviewers)

    @reviewers =
      reviewers.filter_map { |reviewer| convert_reviewer(reviewer) }
        .sort_by { |reviewer| reviewer_score(reviewer) }
  end

  def has_content?
    @has_content
  end

  # https://apidock.com/rails/ActiveModel/Conversion
  def id
    @group_path
  end

  def persisted?
    true
  end

  private

  def parse_graphql_time(timestamp)
    Time.zone.parse(timestamp) if timestamp
  end

  def warmup_timezone_cache(reviewers)
    locations = reviewers.map(&:location).compact_blank.uniq

    location_lookup_service.fetch_timezones(locations)
  end

  def convert_reviewer(reviewer)
    reviewer = reviewer.user

    return if reviewer.bot || reviewer.status.nil? || reviewer.username.ends_with?("-bot")

    reviewer.activeReviews[:count] = reviewer.activeReviews.nodes.count(&:approved)
    reviewer.lastActivityOn = parse_graphql_time(reviewer.lastActivityOn)
    reviewer[:reviewLimit] = WORD_NUMERALS_TO_NUMBERS.fetch(reviewer.status.emoji&.to_sym, 5)
    reviewer[:timezone] = LocationLookupService.new.fetch_timezone(reviewer.location)
    local_time = reviewer[:timezone]&.time_with_offset(Time.now.utc)
    reviewer[:inWorkingHours] =
      local_time ? (local_time.change(hour: 8)..local_time.change(hour: 17)).cover?(local_time) : true

    reviewer
  end

  def location_lookup_service
    @location_lookup_service ||= LocationLookupService.new
  end

  def reviewer_score(reviewer)
    message = reviewer.status.message
    has_message = message && !message.include?("Verify reviews") && !message.include?("Please @")
    ooo = has_message && message.include?("OOO")
    busy = reviewer.status.availability == "BUSY" && (!message || !message.include?("Verify reviews"))
    active_reviews = reviewer.activeReviews.count.to_i

    (ooo ? 20 : 0) +
      (busy ? 10 : 0) +
      (has_message ? 5 : 0) +
      ([0, (active_reviews + 1) - reviewer.reviewLimit].max * 3) +
      (active_reviews + reviewer.assignedMergeRequests.count.to_i / 2)
  end
end
