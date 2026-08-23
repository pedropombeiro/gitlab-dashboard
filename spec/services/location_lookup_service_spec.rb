require "rails_helper"

RSpec.describe LocationLookupService, :with_cache do
  include ActiveSupport::Testing::TimeHelpers

  let(:service) { described_class.new }
  let(:location) { "Lisbon, Portugal" }
  let(:nominatim_url) { %r{\Ahttps://nominatim\.openstreetmap\.org/search} }

  # Timezone::Lookup keeps its configuration in a module-level variable, so
  # restore whatever the suite was configured with.
  around do |example|
    original_lookup = Timezone::Lookup.instance_variable_get(:@lookup)
    example.run
    Timezone::Lookup.instance_variable_set(:@lookup, original_lookup)
  end

  let(:success_body) do
    [
      {
        "lat" => "38.7077507",
        "lon" => "-9.1365919",
        "address" => {
          "country" => "Portugal",
          "country_code" => "pt"
        },
        "boundingbox" => %w[38 39 -10 -9]
      }
    ]
  end

  describe "#fetch_country_code" do
    subject(:fetch_country_code) { service.fetch_country_code(location) }

    context "when the geocoder succeeds" do
      before do
        stub_request(:get, nominatim_url).to_return_json(body: success_body)
      end

      it "returns the country code" do
        expect(fetch_country_code).to eq("PT")
      end

      it "sends an identifying User-Agent header" do
        fetch_country_code

        expect(a_request(:get, nominatim_url).with(
          headers: {"User-Agent" => Geokit::Geocoders.useragent}
        )).to have_been_made
      end

      it "caches the result for a week" do
        fetch_country_code

        travel(6.days) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.once
      end

      it "re-queries after the cache expires" do
        fetch_country_code

        travel(8.days) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.twice
      end
    end

    context "when the geocoder fails" do
      before do
        stub_request(:get, nominatim_url).to_return(status: 403)
      end

      it "returns nil" do
        expect(fetch_country_code).to be_nil
      end

      it "notifies Honeybadger" do
        expect(Honeybadger).to receive(:notify).with(
          "Geocoding lookup failed",
          tags: "warning, geocode",
          context: {location: location}
        )

        fetch_country_code
      end

      it "only caches the failure for a short time" do
        fetch_country_code

        travel(10.minutes) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.once
      end

      it "re-queries once the short cache expires" do
        fetch_country_code

        travel(20.minutes) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.twice
      end

      it "does not stick to the failure once a later lookup succeeds" do
        fetch_country_code

        travel(20.minutes) do
          stub_request(:get, nominatim_url).to_return_json(body: success_body)

          expect(service.fetch_country_code(location)).to eq("PT")
        end
      end
    end

    context "when the location cannot be resolved" do
      let(:location) { "Unresolvable country code location" }

      before do
        stub_request(:get, nominatim_url).to_return_json(body: [])
      end

      it "returns nil" do
        expect(fetch_country_code).to be_nil
      end

      it "records the unsuccessful lookup without notifying Honeybadger" do
        expect(Honeybadger).not_to receive(:notify)
        expect(Honeybadger).to receive(:event).with(
          "Geocoding lookup returned no results",
          location: location
        )

        fetch_country_code
      end

      it "caches the unresolved location for a week" do
        fetch_country_code
        travel(20.minutes) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.once
      end

      it "re-queries after the cache expires" do
        fetch_country_code
        travel(8.days) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.twice
      end
    end

    context "with a cache entry written before outcomes were tracked" do
      let(:cache_key) { described_class.location_info_cache_key(location) }

      it "reuses a legacy successful GeoLoc" do
        geolocation = Geokit::Geocoders::OSMGeocoder.send(:new_loc).tap do |loc|
          loc.country_code = "PT"
          loc.success = true
        end
        Rails.cache.write(cache_key, geolocation, expires_in: described_class.cache_validity)

        expect(fetch_country_code).to eq("PT")
        expect(a_request(:get, nominatim_url)).not_to have_been_made
      end

      it "treats a legacy failed GeoLoc as a transient failure" do
        stub_request(:get, nominatim_url).to_return_json(body: success_body)
        Rails.cache.write(cache_key, Geokit::GeoLoc.new, expires_in: described_class.failure_cache_validity)

        expect(fetch_country_code).to be_nil
        expect(a_request(:get, nominatim_url)).not_to have_been_made
      end
    end

    context "when the geocoder is unreachable" do
      let(:location) { "Unreachable geocoder location" }

      before do
        stub_request(:get, nominatim_url).to_timeout
      end

      it "returns nil and notifies Honeybadger" do
        expect(Honeybadger).to receive(:notify).with(
          "Geocoding lookup failed",
          tags: "warning, geocode",
          context: {location: location}
        )

        expect(fetch_country_code).to be_nil
      end

      it "only caches the failure for a short time" do
        fetch_country_code
        travel(10.minutes) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.once
      end

      it "re-queries once the short cache expires" do
        fetch_country_code
        travel(20.minutes) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.twice
      end
    end

    context "when the connection is reset" do
      let(:location) { "Connection reset location" }

      before do
        stub_request(:get, nominatim_url).to_raise(Errno::ECONNRESET)
      end

      it "notifies Honeybadger" do
        expect(Honeybadger).to receive(:notify).with(
          "Geocoding lookup failed",
          tags: "warning, geocode",
          context: {location: location}
        )

        expect(fetch_country_code).to be_nil
      end

      it "only caches the failure for a short time" do
        fetch_country_code
        travel(20.minutes) { service.fetch_country_code(location) }

        expect(a_request(:get, nominatim_url)).to have_been_made.twice
      end
    end
  end

  describe "#fetch_timezone" do
    subject(:fetch_timezone) { service.fetch_timezone(location) }

    context "when no timezone lookup is configured" do
      before do
        Timezone::Lookup.instance_variable_set(:@lookup, nil)
        stub_request(:get, nominatim_url).to_return_json(body: success_body)
      end

      it "returns nil without geocoding" do
        expect(fetch_timezone).to be_nil
        expect(a_request(:get, nominatim_url)).not_to have_been_made
      end
    end

    context "with a timezone lookup configured" do
      before do
        Timezone::Lookup.config(:test)
      end

      context "when the location resolves" do
        before do
          Timezone::Lookup.lookup.stub(38.7077507, -9.1365919, "Europe/Lisbon")
          stub_request(:get, nominatim_url).to_return_json(body: success_body)
        end

        it "returns the timezone and caches it" do
          expect(fetch_timezone.name).to eq("Europe/Lisbon")
          expect(service.fetch_timezone(location).name).to eq("Europe/Lisbon")

          expect(a_request(:get, nominatim_url)).to have_been_made.once
        end
      end

      context "when the location cannot be resolved" do
        let(:location) { "Unresolvable timezone location" }

        before do
          stub_request(:get, nominatim_url).to_return_json(body: [])
        end

        it "caches the missing timezone for a week" do
          expect(fetch_timezone).to be_nil
          travel(20.minutes) { expect(service.fetch_timezone(location)).to be_nil }

          expect(a_request(:get, nominatim_url)).to have_been_made.once
        end

        it "re-queries after the long cache expires" do
          fetch_timezone
          travel(8.days) { service.fetch_timezone(location) }

          expect(a_request(:get, nominatim_url)).to have_been_made.twice
        end
      end

      context "when the geocoder fails" do
        let(:location) { "Timezone failure location" }

        before do
          stub_request(:get, nominatim_url).to_return(status: 403)
        end

        it "caches the missing timezone for the failure duration only" do
          expect(fetch_timezone).to be_nil
          travel(10.minutes) { expect(service.fetch_timezone(location)).to be_nil }

          expect(a_request(:get, nominatim_url)).to have_been_made.once
        end

        it "re-queries once the short cache expires" do
          fetch_timezone
          travel(20.minutes) { service.fetch_timezone(location) }

          expect(a_request(:get, nominatim_url)).to have_been_made.twice
        end
      end

      context "when the timezone lookup itself fails" do
        before do
          stub_request(:get, nominatim_url).to_return_json(body: success_body)
        end

        it "notifies Honeybadger and negatively caches the result" do
          expect(Honeybadger).to receive(:notify).with(
            instance_of(Timezone::Error::Test),
            tags: "warning, timezone",
            context: {location: location}
          )

          expect(fetch_timezone).to be_nil

          travel(6.days) { expect(service.fetch_timezone(location)).to be_nil }

          expect(a_request(:get, nominatim_url)).to have_been_made.once
        end
      end
    end
  end
end
