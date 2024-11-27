// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "./controllers";
import * as bootstrap from "bootstrap";
import "@fortawesome/fontawesome-free/js/all";

import LocalTime from "local-time";
LocalTime.config.useFormat24 = true
LocalTime.start();
