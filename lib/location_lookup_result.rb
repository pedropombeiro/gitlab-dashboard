# frozen_string_literal: true

# Outcome of a geocoding lookup: the GeoLoc plus why it looks the way it does.
#
# - +:resolved+     the geocoder found the location
# - +:unresolvable+ the geocoder answered normally but knows no such place
# - +:failed+       the geocoder could not be reached (HTTP error or timeout)
#
# Only the outcome is cached, never a TTL: callers derive the TTL when they
# write, so a cache hit cannot resurrect a stale expiry.
class LocationLookupResult
  OUTCOMES = %i[resolved unresolvable failed].freeze

  attr_reader :geolocation, :outcome

  def initialize(geolocation, outcome)
    raise ArgumentError, "unknown outcome #{outcome.inspect}" unless OUTCOMES.include?(outcome)

    @geolocation = geolocation
    @outcome = outcome
  end

  # Cached as a plain Hash of primitives and a Geokit value object, so that
  # reloading this class in development cannot invalidate existing entries.
  def to_cache
    {geolocation: geolocation, outcome: outcome.to_s}
  end

  def self.from_cache(cached)
    case cached
    when Hash
      outcome = cached[:outcome].to_sym
      new(cached[:geolocation], OUTCOMES.include?(outcome) ? outcome : :failed)
    when Geokit::GeoLoc
      # Entries written before outcomes were tracked. The cached TTL still
      # applies; treat unsuccessful ones conservatively as transient failures.
      new(cached, cached.success? ? :resolved : :failed)
    end
  end
end
