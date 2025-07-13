require "httplog"

HttpLog.configure do |config|
  # Enable or disable all logging
  config.enabled = true

  # Tweak which parts of the HTTP cycle to log...
  config.log_connect = true
  config.log_request = true
  config.log_headers = false
  config.log_data = true
  config.log_status = true
  config.log_response = false
  config.log_benchmark = true

  # ...or log all request as a single line by setting this to `true`
  config.compact_log = true
end
