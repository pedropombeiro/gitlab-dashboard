require "rails_helper"

RSpec.describe GitlabRateLimitCooldown, :with_cache, :freeze_time do
  it "honors Retry-After as an HTTP date before considering RateLimit-Reset" do
    described_class.record({"retry-after" => 90.seconds.from_now.httpdate, "RateLimit-Reset" => 5.minutes.from_now.to_i.to_s})

    travel 89.seconds
    expect(described_class).to be_active
    travel 1.second
    expect(described_class).not_to be_active
  end

  it "uses a future RateLimit-Reset epoch when Retry-After is unusable" do
    described_class.record({"Retry-After" => "invalid", "ratelimit-reset" => 75.seconds.from_now.to_i.to_s})

    travel 74.seconds
    expect(described_class).to be_active
    travel 1.second
    expect(described_class).not_to be_active
  end

  it "falls back to a minute when neither header provides a future deadline" do
    described_class.record({"Retry-After" => "0", "RateLimit-Reset" => 1.second.ago.to_i.to_s})

    travel 59.seconds
    expect(described_class).to be_active
    travel 1.second
    expect(described_class).not_to be_active
  end

  it "does not shorten an existing cooldown when another response lacks headers" do
    described_class.record({"Retry-After" => "120"})
    described_class.record(nil)

    travel 119.seconds
    expect(described_class).to be_active
    travel 1.second
    expect(described_class).not_to be_active
  end
end
