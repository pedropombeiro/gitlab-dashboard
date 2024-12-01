require "rails_helper"

RSpec.describe "routes for Mission Control", type: :routing do
  it { expect(get("/jobs")).to be_routable }
end
