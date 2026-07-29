require "rails_helper"

RSpec.describe LocationLookupService, :with_cache do
  include ActiveSupport::Testing::TimeHelpers

  let(:service) { described_class.new }
  let(:location) { "Lisbon, Portugal" }
  let(:nominatim_url) { %r{\Ahttps://nominatim\.openstreetmap\.org/search} }

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
  end
end
