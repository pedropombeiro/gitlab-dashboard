require "rails_helper"

RSpec.describe "routes for Merge Requests", type: :routing do
  it "routes / to the merge requests controller" do
    expect(get("/")).to route_to("merge_requests#index")
  end

  it "routes /mrs to the merge requests controller" do
    expect(get("/mrs")).to route_to("merge_requests#index")
  end

  it "routes /mrs/list to the merge requests controller" do
    expect(get("/mrs/list")).to route_to("merge_requests#list")
  end
end
