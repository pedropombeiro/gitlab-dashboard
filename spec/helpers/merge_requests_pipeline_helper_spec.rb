# frozen_string_literal: true

require "rails_helper"

RSpec.describe MergeRequestsPipelineHelper do
  # Define make_full_url helper method (normally delegated from ApplicationController)
  def make_full_url(path)
    return path if path.nil? || path.start_with?("http")

    "https://gitlab.com#{path}"
  end

  describe "#pipeline_web_url" do
    let(:pipeline) { double }
    let(:failed_jobs) { double(count: 0, nodes: []) }
    let(:running_jobs) { double(count: 1) }
    let(:running_job) { double }

    before do
      allow(pipeline).to receive(:path).and_return("/gitlab-org/gitlab/-/pipelines/123")
      allow(pipeline).to receive(:failedJobs).and_return(failed_jobs)
      allow(pipeline).to receive(:status).and_return("RUNNING")
      allow(pipeline).to receive(:runningJobs).and_return(running_jobs)
      allow(running_jobs).to receive(:nodes).and_return([running_job])
    end

    context "when pipeline has one running job with no downstream pipeline" do
      before do
        allow(running_job).to receive(:webPath).and_return("/gitlab-org/gitlab/-/jobs/456")
        allow(running_job).to receive(:downstreamPipeline).and_return(nil)
      end

      it "returns the running job web path" do
        expect(pipeline_web_url(pipeline)).to eq("https://gitlab.com/gitlab-org/gitlab/-/jobs/456")
      end
    end

    context "when pipeline has one running job without webPath and nil downstream pipeline" do
      before do
        allow(running_job).to receive(:webPath).and_return(nil)
        allow(running_job).to receive(:downstreamPipeline).and_return(nil)
      end

      it "falls back to pipeline path without raising an error" do
        expect(pipeline_web_url(pipeline)).to eq("https://gitlab.com/gitlab-org/gitlab/-/pipelines/123")
      end
    end

    context "when pipeline has one running job with downstream pipeline" do
      let(:downstream_pipeline) { double }
      let(:downstream_jobs) { double }
      let(:downstream_job) { double }

      before do
        allow(running_job).to receive(:webPath).and_return(nil)
        allow(running_job).to receive(:downstreamPipeline).and_return(downstream_pipeline)
        allow(downstream_pipeline).to receive(:jobs).and_return(downstream_jobs)
        allow(downstream_jobs).to receive(:nodes).and_return([downstream_job])
        allow(downstream_job).to receive(:webPath).and_return("/gitlab-org/gitlab/-/jobs/789")
      end

      it "returns the downstream job web path" do
        expect(pipeline_web_url(pipeline)).to eq("https://gitlab.com/gitlab-org/gitlab/-/jobs/789")
      end
    end

    context "when pipeline is FAILED with multiple failed jobs but only one is not allowed to fail" do
      let(:failed_jobs) { double(count: 3, nodes: [allowed_job_1, allowed_job_2, blocking_job]) }
      let(:allowed_job_1) { double(allowFailure: true) }
      let(:allowed_job_2) { double(allowFailure: true) }
      let(:downstream_pipeline) { double }
      let(:downstream_jobs) { double }
      let(:downstream_job) { double(webPath: "/gitlab-org/gitlab/-/jobs/999") }
      let(:blocking_job) do
        double(
          allowFailure: false,
          trace: double(present?: true),
          webPath: "/gitlab-org/gitlab/-/jobs/blocking",
          downstreamPipeline: downstream_pipeline
        )
      end

      before do
        allow(pipeline).to receive(:status).and_return("FAILED")
        allow(downstream_pipeline).to receive(:jobs).and_return(downstream_jobs)
        allow(downstream_jobs).to receive(:nodes).and_return([downstream_job])
      end

      it "links to the single blocking job in the downstream pipeline, not the failures page" do
        expect(pipeline_web_url(pipeline)).to eq("https://gitlab.com/gitlab-org/gitlab/-/jobs/999")
      end
    end

    context "when pipeline is FAILED with multiple non-allowed failures" do
      let(:failed_jobs) { double(count: 2, nodes: [blocking_job_1, blocking_job_2]) }
      let(:blocking_job_1) { double(allowFailure: false, trace: double(present?: true)) }
      let(:blocking_job_2) { double(allowFailure: false, trace: double(present?: true)) }

      before do
        allow(pipeline).to receive(:status).and_return("FAILED")
      end

      it "links to the failures page" do
        expect(pipeline_web_url(pipeline)).to eq("https://gitlab.com/gitlab-org/gitlab/-/pipelines/123/failures")
      end
    end

    context "when pipeline is FAILED but all failed jobs are allowed to fail" do
      let(:failed_jobs) { double(count: 2, nodes: [allowed_job_1, allowed_job_2]) }
      let(:allowed_job_1) { double(allowFailure: true) }
      let(:allowed_job_2) { double(allowFailure: true) }

      before do
        allow(pipeline).to receive(:status).and_return("FAILED")
      end

      it "falls back to the pipeline path" do
        expect(pipeline_web_url(pipeline)).to eq("https://gitlab.com/gitlab-org/gitlab/-/pipelines/123")
      end
    end
  end
end
