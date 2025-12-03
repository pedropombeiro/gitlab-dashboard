Rack::Attack.throttle("requests by ip", limit: 100, period: 1.minute) { |req| req.ip }
