# frozen_string_literal: true

class ComputeMergeRequestChangesService
  def initialize(type, previous_dto, dto)
    @type = type
    @previous_dto = previous_dto
    @dto = dto
  end

  def execute
    return [] unless previous_dto

    previous_open_mrs = (type == :open) ? previous_dto.open_merge_requests.items : nil
    open_mrs = (type == :open) ? dto.open_merge_requests.items : nil

    previous_merged_mrs = (type == :merged) ? previous_dto.merged_merge_requests.items : nil
    merged_mrs = (type == :merged) ? dto.merged_merge_requests.items : nil

    mr_changes = []

    # New MR merged
    merged_mrs&.each do |mr|
      previous_mr_version = previous_merged_mrs.find { |prev_mr| prev_mr.iid == mr.iid }
      next unless previous_merged_mrs.any? && previous_mr_version.nil?

      mr_changes << merge_request_change(
        mr,
        type: :merge_request_merged,
        title: "A merge request was merged",
        body: "#{mr.reference}: #{mr.titleHtml}"
      )
    end

    # Open MR changes
    changed_labels(previous_open_mrs, open_mrs).each do |change|
      mr_changes << merge_request_labels_change("An open merge request", change)
    end

    # Merged MR changes
    changed_labels(previous_merged_mrs, merged_mrs).each do |change|
      mr_changes << merge_request_labels_change("A merged merge request", change)
    end

    mr_changes
  end

  private

  attr_reader :type, :previous_dto, :dto

  def merge_request_change(mr, type:, title:, body:)
    {
      title: title,
      type: type,
      body: body,
      url: mr.webUrl,
      tag: mr.iid,
      timestamp: mr.updatedAt
    }
  end

  def merge_request_labels_change(title, changes)
    mr = changes[:mr]
    mr_data = "#{mr.reference}: #{mr.titleHtml}"

    hash = {
      type: :label_change,
      title: title,
      body: "changed to #{changes[:labels].join(", ")}\n\n#{mr_data}"
    }

    if changes[:previous_labels].any? && changes[:labels].empty?
      hash[:body] = "is no longer labeled #{changes[:previous_labels].join(", ")}\n\n#{mr_data}"
    end

    merge_request_change(mr, **hash)
  end

  def changed_labels(previous_mrs, mrs)
    return [] if previous_mrs.blank?

    mrs.filter_map do |mr|
      # Don't send notifications if the issue is closed
      next if mr.issue&.state == "closed"

      previous_mr_version = previous_mrs.find { |prev_mr| prev_mr.iid == mr.iid }
      next if previous_mr_version.nil?

      mr_versions = [previous_mr_version, mr]
      previous_ctx_labels, ctx_labels = mr_versions.map(&:contextualLabels)
      next if ctx_labels.map(&:title) == previous_ctx_labels.map(&:title)

      # Check workflow notification rules
      if notification_rules.present? && rules_label_titles.intersect?(mr.labels.nodes.map(&:title))
        previous_ctx_labels, ctx_labels = changed_labels_matching_rules(previous_mr_version, mr)
        next if ctx_labels.nil?
      end

      {
        mr: mr,
        previous_labels: previous_ctx_labels.map(&:webTitle),
        labels: ctx_labels.map(&:webTitle)
      }
    end
  end

  def matching_notification_rules(mr, notification_rules)
    label_titles = mr.labels.nodes.map(&:title)

    notification_rules
      .filter { |rule| rule.key?(:required_state) ? mr.state == rule[:required_state].to_sym : true }
      .filter { |rule| rule.key?(:required_label) ? rule[:required_label].in?(label_titles) : true }
  end

  def changed_labels_matching_rules(previous_mr_version, mr)
    # Find relevant label titles
    previous_label_titles = previous_mr_version.labels.nodes.map(&:title) & rules_label_titles
    label_titles = mr.labels.nodes.map(&:title) & rules_label_titles
    return if label_titles == previous_label_titles

    matching_rules = matching_notification_rules(mr, notification_rules)
    return if matching_rules.blank?

    matching_rules_label_titles = matching_rules.pluck(:watched_labels).flatten.uniq
    previous_label_titles &= matching_rules_label_titles
    label_titles &= matching_rules_label_titles
    return unless label_titles.any?

    previous_rule_labels = labels_matching_rules(previous_mr_version, previous_label_titles)
    rule_labels = labels_matching_rules(mr, label_titles)
    return if rule_labels.map(&:title) == previous_rule_labels.map(&:title)

    [previous_rule_labels, rule_labels]
  end

  def labels_matching_rules(mr, rules_label_titles)
    mr.labels.nodes.filter { |label| rules_label_titles.include? label.title }
  end

  def config
    @merge_requests_config ||= Rails.application.config.merge_requests
  end

  def notification_rules
    @notification_rules ||= config.dig(:labels, :notification_rules)
  end

  def rules_label_titles
    @rules_label_titles ||= notification_rules.pluck(:watched_labels).flatten.uniq
  end
end
