require "rails_helper"

RSpec.describe "PWA", type: :request do
  describe "GET /service-worker" do
    it "renders the service worker without an explicit format" do
      get "/service-worker"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      expect(response.body).to include("pushsubscriptionchange")
    end

    it "renders the service worker with the JavaScript extension" do
      get "/service-worker.js"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
    end

    it "does not route unsupported formats" do
      get "/service-worker.html"
      expect(response).to have_http_status(:not_found)

      get "/service-worker.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /manifest" do
    it "renders the manifest without an explicit format" do
      get "/manifest"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to include("id" => "gitlab-mr-dashboard")
    end

    it "renders the manifest with the JSON extension" do
      get "/manifest.json"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "does not route unsupported formats" do
      get "/manifest.html"
      expect(response).to have_http_status(:not_found)

      get "/manifest.js"
      expect(response).to have_http_status(:not_found)
    end
  end
end
