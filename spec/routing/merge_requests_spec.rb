require "rails_helper"

RSpec.describe "routes for Merge Requests", type: :routing do
  it "routes / to the merge requests controller" do
    expect(get("/")).to route_to("merge_requests#index")
  end

  it "routes /mrs to the merge requests controller" do
    expect(get("/mrs")).to route_to("merge_requests#index")
  end

  it "routes /mrs/open_list to the merge requests controller" do
    expect(get("/mrs/open_list")).to route_to("merge_requests#open_list")
  end

  it "routes /mrs/merged_list to the merge requests controller" do
    expect(get("/mrs/merged_list")).to route_to("merge_requests#merged_list")
  end
end
