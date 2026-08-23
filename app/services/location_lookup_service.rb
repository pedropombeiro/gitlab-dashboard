# frozen_string_literal: true

require "async"
require "geokit"
require "timezone"

class LocationLookupService
  include CacheConcern

  # Sentinel stored in the timezone name cache so that locations without a
  # known timezone are negatively cached instead of re-queried on every call.
  NO_TIMEZONE = ""

  def self.cache_validity
    1.week
  end

  def self.failure_cache_validity
    15.minutes
  end

  # Nominatim answering "no such place" is a permanent answer, so it is cached
  # as long as a successful lookup. Only transport failures get the short TTL.
  def self.validity_for(outcome)
    (outcome == :failed) ? failure_cache_validity : cache_validity
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

    cache_key = self.class.location_timezone_name_cache_key(location)
    cached_tzname = Rails.cache.read(cache_key)
    return if cached_tzname == NO_TIMEZONE
    return Timezone[cached_tzname] if cached_tzname

    result = fetch_location_info(location)
    tzname = timezone_name(result.geolocation, location)

    Rails.cache.write(
      cache_key,
      tzname || NO_TIMEZONE,
      expires_in: self.class.validity_for(result.outcome)
    )

    Timezone[tzname] if tzname
  end

  def fetch_country_code(location)
    return if location.blank?

    fetch_location_info(location)&.geolocation&.country_code
  end

  private

  def fetch_location_info(location)
    return if location.blank?

    cache_key = self.class.location_info_cache_key(location)
    cached = LocationLookupResult.from_cache(Rails.cache.read(cache_key))
    return cached if cached

    result = geocode(location)
    Rails.cache.write(
      cache_key,
      result.to_cache,
      expires_in: self.class.validity_for(result.outcome)
    )

    result
  end

  def geocode(location)
    recorded = GeocodingResponseRecorder.record { Geokit::Geocoders::OSMGeocoder.geocode(location) }
    geolocation = recorded.value

    if geolocation.success?
      LocationLookupResult.new(geolocation, :resolved)
    elsif recorded.http_success?
      # Nominatim replied normally but knows no such place: never going to
      # resolve, so report it without raising an error notification.
      Honeybadger.event("Geocoding lookup returned no results", location: location)

      LocationLookupResult.new(geolocation, :unresolvable)
    else
      Honeybadger.notify(
        "Geocoding lookup failed",
        tags: "warning, geocode",
        context: {location: location}
      )

      LocationLookupResult.new(geolocation, :failed)
    end
  end

  def timezone_name(geolocation, location)
    return unless geolocation.valid?

    timezone = Timezone.lookup(geolocation.latitude, geolocation.longitude)
    timezone.name if timezone.valid?
  rescue Timezone::Error::Base => exception
    Honeybadger.notify(exception, tags: "warning, timezone", context: {location: location})

    nil
  end

  def timezone_configured?
    Timezone::Lookup.lookup

    true
  rescue ::Timezone::Error::InvalidConfig
    false
  end
end
