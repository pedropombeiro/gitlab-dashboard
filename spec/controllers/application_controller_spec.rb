require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render plain: real_ip
    end
  end

  describe "#real_ip" do
    subject(:make_request) { get :index }

    let(:remote_addr) { "172.29.8.1" }
    let(:client_ip) { "203.0.113.50" }

    before do
      request.headers["REMOTE_ADDR"] = remote_addr
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

    context "when X-Forwarded-For header is present" do
      let(:proxy_ip) { "172.70.100.1" }

      before do
        request.headers["X-Forwarded-For"] = "#{client_ip}, #{proxy_ip}"
      end

      it "returns the first IP from X-Forwarded-For" do
        make_request

        expect(response.body).to eq client_ip
      end

      context "when CF-Connecting-IP is also present" do
        let(:cf_client_ip) { "198.51.100.25" }

        before do
          request.headers["CF-Connecting-IP"] = cf_client_ip
        end

        it "prefers CF-Connecting-IP" do
          make_request

          expect(response.body).to eq cf_client_ip
        end
      end
    end

    context "when no proxy headers are present" do
      it "falls back to remote_ip" do
        make_request

        expect(response.body).to eq remote_addr
      end
    end
  end
end
