# frozen_string_literal: true

# Geokit collapses "the geocoder answered, but knows no such place" and "the
# geocoder could not be reached" into the same blank GeoLoc, discarding the HTTP
# response that tells them apart. This Geokit net adapter delegates to the stock
# one and remembers the response for the duration of a `record` block.
#
#   recorded = GeocodingResponseRecorder.record { Geokit::Geocoders::OSMGeocoder.geocode(query) }
#   recorded.value           # => Geokit::GeoLoc
#   recorded.http_success?   # => false for 4xx/5xx, timeouts and connection errors
class GeocodingResponseRecorder
  RESPONSE_KEY = :geocoding_response_recorder_response
  private_constant :RESPONSE_KEY

  Recorded = Data.define(:value, :response) do
    # Geokit rescues connection errors and swallows timeouts before the adapter
    # returns, leaving no response behind. Absence therefore means failure.
    def http_success?
      !response.nil? && Geokit::NetAdapter::NetHttp.success?(response)
    end
  end

  class << self
    # Runs the block with response recording enabled, returning the block's
    # value alongside the last HTTP response Geokit received.
    def record
      previous = Thread.current[RESPONSE_KEY]
      Thread.current[RESPONSE_KEY] = nil

      Recorded.new(yield, Thread.current[RESPONSE_KEY])
    ensure
      Thread.current[RESPONSE_KEY] = previous
    end

    # Geokit net adapter interface.
    def do_get(url)
      Geokit::NetAdapter::NetHttp.do_get(url).tap do |response|
        Thread.current[RESPONSE_KEY] = response
      end
    end

    # Geokit net adapter interface.
    def success?(response)
      Geokit::NetAdapter::NetHttp.success?(response)
    end
  end
end
