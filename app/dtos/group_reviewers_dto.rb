# frozen_string_literal: true

class GroupReviewersDto
  extend ActiveModel::Naming

  include ActiveModel::Conversion

  attr_reader :errors, :updated_at, :next_update_at, :request_duration
  attr_reader :group_path, :reviewers

  INACTIVE_OPACITY_FACTOR = 2
  SCORE_OPACITY_FACTOR = 2
  MIN_OPACITY = 0.3
  OOO_EMOJIS = %w[nauseated_face palm_tree thermometer].freeze
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

    @next_update_at = CacheConcern::GROUP_REVIEWERS_CACHE_VALIDITY.after(response.updated_at)

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

    # NOTE: This is required because we can't filter on `active: true` reviews until
    # the `mr_approved_filter` FF is removed or enabled
    reviewer.activeReviews[:count] =
      reviewer.activeReviews.delete_field!(:nodes).count { |review| !review.approved }

    reviewer.lastActivityOn = parse_graphql_time(reviewer.lastActivityOn)
    reviewer[:reviewLimit] = review_limit(reviewer)
    reviewer[:bootstrapClass] = bs_classes(reviewer)
    reviewer[:timezone] = LocationLookupService.new.fetch_timezone(reviewer.location)
    local_time = reviewer[:timezone]&.time_with_offset(Time.now.utc)
    reviewer[:inWorkingHours] =
      local_time ? (local_time.change(hour: 8)..local_time.change(hour: 17)).cover?(local_time) : true

    reviewer[:opacity] = reviewer_opacity(reviewer)

    reviewer
  end

  def location_lookup_service
    @location_lookup_service ||= LocationLookupService.new
  end

  def is_ooo?(reviewer)
    message = reviewer.status.message

    return true if message&.include?("OOO") || message&.include?("Out of office")
    return true if reviewer.status.emoji.in?(OOO_EMOJIS)
    return true if message&.match?(/\wsick\w/)

    false
  end

  def review_limit(reviewer)
    message = reviewer.status.message

    review_limit = WORD_NUMERALS_TO_NUMBERS.fetch(reviewer.status.emoji&.to_sym, 5)
    review_limit = 0 if message&.downcase&.include?("at capacity")

    review_limit
  end

  def bs_classes(reviewer)
    {}.tap do |bs_classes|
      bs_classes[:requested_reviews_text] =
        if reviewer.activeReviews.count < reviewer.reviewLimit
          "text-success"
        elsif reviewer.activeReviews.count == reviewer.reviewLimit
          "text-warning"
        else
          "text-danger"
        end
    end
  end

  def inactive?(reviewer)
    reviewer.lastActivityOn.before?(3.days.ago)
  end

  def reviewer_score(reviewer)
    message = reviewer.status.message
    has_message =
      message.present? &&
      message.exclude?("Verify reviews") &&
      message.exclude?("Please @") &&
      message.exclude?("@-mention")
    ooo = is_ooo?(reviewer)
    busy = reviewer.status.availability == "BUSY" && (message.blank? || message.exclude?("Verify reviews"))
    active_reviews = reviewer.activeReviews.count.to_i
    assigned_mrs = reviewer.assignedMergeRequests.count.to_i
    review_limit = reviewer.reviewLimit

    [
      (ooo ? 20 : 0) +
        ((!ooo && inactive?(reviewer)) ? 10 : 0) +
        (busy ? 10 : 0) +
        (has_message ? 5 : 0) +
        ([0, (active_reviews + 1) - review_limit].max * 3) +
        (active_reviews + assigned_mrs / 2),
      assigned_mrs
    ]
  end

  def reviewer_opacity(reviewer)
    score = reviewer_score(reviewer).first.to_f
    score *= INACTIVE_OPACITY_FACTOR if inactive?(reviewer)

    [1.0 - score * SCORE_OPACITY_FACTOR / 100, MIN_OPACITY].max
  end
end
