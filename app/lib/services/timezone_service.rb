# frozen_string_literal: true

require "async"
require "geokit"
require "timezone"

module Services
  class TimezoneService
    include CacheConcern

    def self.cache_validity
      1.week
    end

    def fetch_from_locations(locations)
      locations.map do |l|
        Async { [ l, fetch_from_location(l) ] }
      end.map(&:wait).to_h
    end

    def fetch_from_location(location)
      return if location.blank?

      tzname =
        Rails.cache.fetch(self.class.location_timezone_name_cache_key(location), expires_in: self.class.cache_validity) do
          res = Geokit::Geocoders::OSMGeocoder.geocode(location)
          return unless res.valid?

          timezone = Timezone.lookup(res.latitude, res.longitude)
          return unless timezone.valid?

          timezone.name
        end

      Timezone[tzname] if tzname
    end
  end
end
