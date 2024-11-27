require "rails_helper"

RSpec.describe Services::ComputeMergeRequestChangesService, "#execute" do
  let_it_be(:fixtures_path) { Rails.root.join("spec/support/fixtures") }

  subject(:execute) { described_class.new(previous_dto, dto).execute }

  let(:response) { YAML.load_file(fixtures_path.join("open_merge_requests.yml")) }
  let(:previous_dto) {}
  let(:dto) {}

  pending "add some examples to (or delete) #{__FILE__}"
end
