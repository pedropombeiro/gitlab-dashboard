require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module GitlabDashboard
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Support _FILE Docker secrets
    ENV.select { |k, v| k.match(/.+_FILE/) }.each do |secret_env_var, file_path|
      next unless File.exist?(file_path)

      ENV[secret_env_var.delete_suffix("_FILE")] = File.read(file_path)
    end

    # Load secrets files
    config_files = %w[secrets.yml]
    config_files.each do |file_name|
      file_path = File.join(Rails.root, "config", file_name)
      next unless File.exist?(file_path)

      config_keys = HashWithIndifferentAccess.new(YAML.load(IO.read(file_path)))[Rails.env]
      config_keys.each do |k, v|
        ENV[k.upcase] ||= v
      end
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
