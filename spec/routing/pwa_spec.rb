require "rails_helper"

RSpec.describe "routes for PWA", type: :routing do
  it "routes the manifest to the application PWA controller" do
    expect(get("/manifest")).to route_to("pwa#manifest", format: :json)
  end

  it "routes the service worker to the Rails PWA controller" do
    expect(get("/service-worker")).to route_to("rails/pwa#service_worker", format: :js)
  end
end
