# frozen_string_literal: true

require "async"
require "geokit"
require "timezone"

class LocationLookupService
  include CacheConcern

  def self.cache_validity
    1.week
  end

  def self.failure_cache_validity
    15.minutes
  end

  def fetch_timezones(locations)
    return unless timezone_configured?

    Sync do |task|
      locations.map do |l|
        task.async { [l, fetch_timezone(l)] }
      end.to_h(&:wait)
    end
  end

  def fetch_timezone(location)
    return if location.blank?
    return unless timezone_configured?

    tzname =
      Rails.cache.fetch(self.class.location_timezone_name_cache_key(location), expires_in: self.class.cache_validity) do
        res = fetch_location_info(location)
        return unless res.valid?

        timezone = Timezone.lookup(res.latitude, res.longitude)
        return unless timezone.valid?

        timezone.name
      rescue Timezone::Error::Base => exception
        Honeybadger.notify(exception, tags: "warning, timezone", context: {location: location})

        nil
      end

    Timezone[tzname] if tzname
  end

  def fetch_country_code(location)
    return if location.blank?

    fetch_location_info(location)&.country_code
  end

  private

  def fetch_location_info(location)
    return if location.blank?

    cache_key = self.class.location_info_cache_key(location)
    cached = Rails.cache.read(cache_key)
    return cached if cached

    res = Geokit::Geocoders::OSMGeocoder.geocode(location)

    if res.success?
      Rails.cache.write(cache_key, res, expires_in: self.class.cache_validity)
    else
      Honeybadger.notify(
        "Geocoding lookup failed",
        tags: "warning, geocode",
        context: {location: location}
      )

      Rails.cache.write(cache_key, res, expires_in: self.class.failure_cache_validity)
    end

    res
  end

  def timezone_configured?
    Timezone::Lookup.lookup

    true
  rescue ::Timezone::Error::InvalidConfig
    false
  end
end
