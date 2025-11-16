Rack::Attack.throttle("requests by ip", limit: 10, period: 1.minute) { |req| req.ip }
