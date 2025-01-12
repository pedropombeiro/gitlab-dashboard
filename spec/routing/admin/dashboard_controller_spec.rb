require "rails_helper"

RSpec.describe "routes for Admin Dashboard", type: :routing do
  it "routes /mrs/:author to the admin dashboard controller" do
    expect(get("/admin/dashboard"))
      .to route_to("admin/dashboard#index")
  end
end
