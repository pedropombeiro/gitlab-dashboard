# frozen_string_literal: true

module Services
  class ComputeMergeRequestChangesService
    def initialize(previous_dto, dto)
      @previous_dto = previous_dto
      @dto = dto
    end

    def execute
      return [] unless previous_dto

      previous_open_mrs = previous_dto.open_merge_requests.items
      previous_merged_mrs = previous_dto.merged_merge_requests.items
      open_mrs = dto.open_merge_requests.items
      merged_mrs = dto.merged_merge_requests.items

      [].tap do |mr_changes|
        # Open MR merged
        merged_mrs.each do |mr|
          previous_mr_version = previous_open_mrs.find { |prev_mr| prev_mr.iid == mr.iid }
          next if previous_mr_version.nil?

          mr_changes << merge_request_change(
            mr,
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
      end
    end

    private

    attr_reader :previous_dto, :dto

    def merge_request_change(mr, title:, body:)
      {
        title: title,
        body: body,
        url: mr.webUrl,
        tag: mr.iid,
        timestamp: mr.updatedAt
      }
    end

    def merge_request_labels_change(title, changes)
      mr = changes[:mr]

      merge_request_change(
        mr,
        title: title,
        body: "changed to #{changes[:labels].join(", ")}\n\n#{mr.reference}: #{mr.titleHtml}"
      )
    end

    def changed_labels(previous_mrs, mrs)
      return [] if previous_mrs.blank?

      mrs.filter_map do |mr|
        previous_mr_version = previous_mrs.find { |prev_mr| prev_mr.iid == mr.iid }
        next if previous_mr_version.nil?

        previous_labels = previous_mr_version.contextualLabels.map(&:webTitle)
        labels = mr.contextualLabels.map(&:webTitle)
        next if labels.blank? || labels == previous_labels

        {
          mr: mr,
          labels: labels,
          previous_labels: previous_labels
        }
      end
    end
  end
end
