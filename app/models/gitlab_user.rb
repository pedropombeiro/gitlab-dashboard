class GitlabUser < ApplicationRecord
  has_many :web_push_subscriptions

  scope :recent, -> { where(contacted_at: 1.day.ago..).order(contacted_at: :desc) }

  class << self
    include Honeybadger::InstrumentationHelper

    def safe_find_or_create_by(*args, &block)
      record = find_by(*args)
      return record if record.present?

      metric_source "custom_metrics"
      metric_attributes(**args.last.slice(:username))

      increment_counter("user.create")

      # We need to use `all.create` to make this implementation follow `find_or_create_by` which delegates this in
      # https://github.com/rails/rails/blob/v6.1.3.2/activerecord/lib/active_record/querying.rb#L22
      #
      # When calling this method on an association, just calling `self.create` would call `ActiveRecord::Persistence.create`
      # and that skips some code that adds the newly created record to the association.
      transaction(requires_new: true) { all.create(*args, &block) } # rubocop:disable Performance/ActiveRecordSubtransactions
    rescue ActiveRecord::RecordNotUnique
      find_by(*args)
    end

    def safe_find_or_create_by!(*args, &block)
      safe_find_or_create_by(*args, &block).tap do |record|
        raise ActiveRecord::RecordNotFound if record.blank?

        record.validate! unless record.persisted?
      end
    end
  end
end
