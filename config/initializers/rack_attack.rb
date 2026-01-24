# Use Cloudflare's CF-Connecting-IP header when available, falling back to the standard IP detection
Rack::Attack.throttle("requests by ip", limit: 100, period: 1.minute) do |req|
  req.env["HTTP_CF_CONNECTING_IP"] || req.ip
end
