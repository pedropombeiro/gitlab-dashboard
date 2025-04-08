# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "local-time" # @3.0.3
pin "bootstrap" # @5.3.5
pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8
