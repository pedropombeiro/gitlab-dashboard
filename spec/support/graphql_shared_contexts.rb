RSpec.shared_context "stub graphql client" do
  let_it_be(:gitlab_instance_url) { "https://gitlab.example.com" }
  let_it_be(:graphql_url) { "#{gitlab_instance_url}/api/graphql" }
  let_it_be(:graphql_schema_file) { file_fixture("gitlab_graphql_schema.json") }

  let(:graphql_client) { ::Graphlient::Client.new(graphql_url, schema_path: graphql_schema_file) }

  before do
    stub_env("GITLAB_URL", gitlab_instance_url)
    stub_request(:post, graphql_url)
      .with(body: hash_including("operationName" => "IntrospectionQuery"))
      .to_return_json(body: JSON.load_file(graphql_schema_file))
    stub_const("GitlabClient::Client", graphql_client)
    allow(GitlabClient).to receive(:gitlab_instance_url).and_return(gitlab_instance_url)
  end
end
