require "yaml"
require "active_support/core_ext/hash/deep_merge" # For deep merging

# Load the primary merge_requests config
base_config = Rails.application.config_for(:merge_requests)

# Load additional YAML files (e.g., merge_requests.links.yml)
additional_files = Rails.root.glob("config/merge_requests/*.yml") # Find all YAML files in the subdirectory. You can also specify a specific file.
additional_configs = additional_files.map do |file|
  YAML.load_file(file).deep_symbolize_keys
end

# Deep merge all configurations
merged_config = [base_config, *additional_configs].reduce do |config, additional_config|
  config.deep_merge(additional_config)
end

Rails.application.config.merge_requests = merged_config
