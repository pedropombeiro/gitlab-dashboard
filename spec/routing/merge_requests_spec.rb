require "rails_helper"

RSpec.describe "routes for Merge Requests", type: :routing do
  it "routes / to the merge requests controller" do
    expect(get("/"))
      .to route_to("merge_requests#index")
  end

  it "does not route /mrs" do
    expect(get("/mrs")).not_to be_routable
  end

  it "routes /mrs/:assignee to the merge requests controller" do
    expect(get("/mrs/:assignee"))
      .to route_to("merge_requests#index", "assignee" => ":assignee")
  end

  it "routes /mrs/:assignee/list to the merge requests controller" do
    expect(get("/mrs/:assignee/list"))
      .to route_to("merge_requests#list", "assignee" => ":assignee")
  end
end
