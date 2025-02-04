require "rails_helper"

RSpec.describe GitlabClient do
  let_it_be(:graphql_url) { "https://example.gitlab.com/api/graphql" }
  let_it_be(:graphql_client) do
    ::Graphlient::Client.new(graphql_url, schema_path: file_fixture("gitlab_graphql_schema.json"))
  end

  let(:client) { described_class.new }

  before do
    stub_const("#{described_class}::Client", graphql_client)
  end

  describe "#fetch_user" do
    let_it_be(:user_requests_response_body) { YAML.load_file(file_fixture("user_requests.yml")) }

    let(:username) { "pedropombeiro" }

    subject(:fetch_user) do
      client.fetch_user(username)
    end

    before do
      stub_request(:post, graphql_url)
        .with(body: hash_including("operationName" => "GitlabClient__UserQuery"))
        .to_return_json(body: user_requests_response_body[username])
    end

    it "returns the user data", :freeze_time do
      expect(fetch_user).to be_truthy
      expect(fetch_user).to have_attributes(
        updated_at: Time.current,
        response: an_object_having_attributes(
          data: an_object_having_attributes(
            user: an_object_having_attributes(
              "__typename" => "UserCore",
              "username" => "pedropombeiro",
              "avatarUrl" => "/uploads/-/system/user/avatar/1388762/avatar.png",
              "webUrl" => "https://gitlab.com/pedropombeiro"
            )
          )
        )
      )
    end
  end

  describe "#fetch_issues" do
    let_it_be(:issues) { YAML.load_file(file_fixture("issues.yml")) }

    let(:mr_issue_iids) do
      [
        {project_full_path: "gitlab-org/gitlab-runner", issue_iid: "32804"},
        {project_full_path: "gitlab-org/gitlab", issue_iid: "506226"},
        {project_full_path: "gitlab-org/gitlab", issue_iid: "505810"}
      ]
    end

    subject(:fetch_issues) do
      client.fetch_issues(mr_issue_iids)
    end

    before do
      stub_request(:post, graphql_url)
        .with(body: hash_including(
          "operationName" => "GitlabClient__ProjectIssuesQuery",
          "variables" => hash_including(
            "projectFullPath" => "gitlab-org/gitlab",
            "issueIids" => an_array_matching(%w[505810 506226])
          )
        ))
        .to_return_json(body: issues["project_0"])
      stub_request(:post, graphql_url)
        .with(body: hash_including(
          "operationName" => "GitlabClient__ProjectIssuesQuery",
          "variables" => {
            "projectFullPath" => "gitlab-org/gitlab-runner",
            "issueIids" => %w[32804]
          }
        ))
        .to_return_json(body: issues["project_2"])
    end

    it "returns an array with the processed issue data" do
      is_expected.to match(
        an_object_having_attributes(
          response: an_object_having_attributes(
            data: [
              an_object_having_attributes(
                "iid" => "32804",
                "webUrl" => "https://gitlab.com/gitlab-org/gitlab-runner/-/issues/32804"
              ),
              an_object_having_attributes(
                "iid" => "506226",
                "webUrl" => "https://gitlab.com/gitlab-org/gitlab/-/issues/506226"
              ),
              an_object_having_attributes(
                "iid" => "505810",
                "webUrl" => "https://gitlab.com/gitlab-org/gitlab/-/issues/505810"
              )
            ]
          )
        )
      )
    end
  end

  describe "#fetch_open_merge_requests" do
    let_it_be(:open_mrs_response_body) { YAML.load_file(file_fixture("open_merge_requests.yml")) }

    let(:author) { "pedropombeiro" }
    let(:result_as_hash) { openstruct_to_hash(fetch_open_merge_requests) }

    subject(:fetch_open_merge_requests) do
      client.fetch_open_merge_requests(author)
    end

    before do
      stub_request(:post, graphql_url)
        .with(body: hash_including("operationName" => "GitlabClient__OpenMergeRequestsQuery"))
        .to_return_json(body: open_mrs_response_body["one"])
    end

    it "returns the merge request data", :freeze_time do
      common_mr_attrs = {
        project: a_hash_including(fullPath: "gitlab-org/gitlab"),
        reviewers: {nodes: an_instance_of(Array)},
        assignees: {nodes: an_instance_of(Array)},
        labels: {nodes: an_instance_of(Array)},
        blockingMergeRequests: {visibleMergeRequests: an_instance_of(Array)}
      }

      expect(fetch_open_merge_requests).to be_truthy
      expect(result_as_hash).to match(
        updated_at: Time.current,
        request_duration: an_instance_of(Float),
        response: {
          data: {
            user: {
              openMergeRequests: {
                nodes: [
                  a_hash_including(iid: "173741", **common_mr_attrs),
                  a_hash_including(iid: "174004", **common_mr_attrs),
                  a_hash_including(iid: "173789", **common_mr_attrs),
                  a_hash_including(iid: "173874", **common_mr_attrs),
                  a_hash_including(iid: "173916", **common_mr_attrs),
                  a_hash_including(iid: "173886", **common_mr_attrs),
                  a_hash_including(iid: "173885", **common_mr_attrs,
                    blockingMergeRequests: {visibleMergeRequests: [iid: "173886", state: "opened"]}),
                  a_hash_including(iid: "173639", **common_mr_attrs),
                  a_hash_including(iid: "171848", **common_mr_attrs,
                    blockingMergeRequests: {
                      visibleMergeRequests: [{iid: "172422", state: "merged"}, {iid: "172698", state: "closed"}]
                    }),
                  a_hash_including(iid: "173007", **common_mr_attrs)
                ]
              }
            }
          }
        }
      )
    end
  end

  describe "#fetch_merged_merge_requests" do
    let(:author) { "user.1" }

    subject(:fetch_merged_merge_requests) do
      client.fetch_merged_merge_requests(author)
    end

    before do
      stub_request(:post, graphql_url)
        .with(body: hash_including("operationName" => "GitlabClient__MergedMergeRequestsQuery"))
        .to_return_json(body: {data: {user: {mergedMergeRequests: {nodes: []}}}})
    end

    it "returns merged merge requests" do
      expect(fetch_merged_merge_requests.response.data.user.mergedMergeRequests.nodes).to eq([])
    end
  end

  describe "#fetch_monthly_merged_merge_requests", :freeze_time do
    let(:author) { "user.1" }

    subject(:fetch_monthly_merged_merge_requests) do
      client.fetch_monthly_merged_merge_requests(author)
    end

    before do
      stub_request(:post, graphql_url)
        .with(body: hash_including(
          "operationName" => "GitlabClient__MonthlyMergeRequestsQuery",
          "variables" => matching(
            "author" => author,
            "mergedAfter" => an_instance_of(String),
            "mergedBefore" => an_instance_of(String)
          )
        ))
        .to_return_json(body: {data: {user: {monthlyMergedMergeRequests: []}}})
        .times(12)
    end

    it "returns monthly merged merge requests" do
      expect(fetch_monthly_merged_merge_requests.response.data.user.table).to eq(
        12.times.to_h { |index| [:"monthlyMergedMergeRequests#{index}", []] }
      )
    end
  end

  describe "#fetch_project_version" do
    let(:project_web_url) { "https://gitlab.com/gitlab-org/gitlab" }
    let(:branch) { "master" }

    subject(:fetch_project_version) do
      client.fetch_project_version(project_web_url)
    end

    context "when master branch exists" do
      before do
        stub_request(:get, "#{project_web_url}/-/raw/master/VERSION")
          .to_return(body: "17.7.0-pre")
      end

      it "returns contents from VERSION file from master branch" do
        is_expected.to eq("17.7.0")
      end
    end

    context "when master branch does not exist" do
      before do
        stub_request(:get, "#{project_web_url}/-/raw/master/VERSION")
          .to_return(status: 404)
        stub_request(:get, "#{project_web_url}/-/raw/main/VERSION")
          .to_return(body: "17.7.0-pre")
      end

      it "returns contents from VERSION file from main branch" do
        is_expected.to eq("17.7.0")
      end
    end

    context "when VERSION file does not exist" do
      before do
        stub_request(:get, %r{#{project_web_url}/-/raw/\w+/VERSION})
          .to_return(status: 404)
      end

      it { is_expected.to be_nil }
    end
  end

  private

  def openstruct_to_hash(object, hash = {})
    case object
    when OpenStruct
      object.each_pair do |key, value|
        hash[key] = openstruct_to_hash(value)
      end
      hash
    when Array
      object.map { |v| openstruct_to_hash(v) }
    else object
    end
  end
end
