require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render plain: real_ip
    end
  end

  describe "#real_ip" do
    subject(:make_request) { get :index }

    let(:cloudflare_ip) { "172.70.100.1" }
    let(:client_ip) { "203.0.113.50" }

    before do
      request.headers["REMOTE_ADDR"] = cloudflare_ip
    end

    context "when CF-Connecting-IP header is present" do
      before do
        request.headers["CF-Connecting-IP"] = client_ip
      end

      it "returns the Cloudflare client IP" do
        make_request

        expect(response.body).to eq client_ip
      end
    end

    context "when CF-Connecting-IP header is absent" do
      it "falls back to remote_ip" do
        make_request

        expect(response.body).to eq cloudflare_ip
      end
    end
  end
end
