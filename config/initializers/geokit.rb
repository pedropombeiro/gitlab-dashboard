# Nominatim (OpenStreetMap) rejects requests without an identifying User-Agent
# with HTTP 403, per https://operations.osmfoundation.org/policies/nominatim/.
# Geokit sends no User-Agent unless one is configured, so country flag lookups
# silently fail without this.
Geokit::Geocoders.useragent = "gitlab-dashboard (+https://github.com/pedropombeiro/gitlab-dashboard)"
