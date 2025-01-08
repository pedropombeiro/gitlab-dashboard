// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
//import * as bootstrap from "bootstrap";
import "@fortawesome/fontawesome-free/js/all";
import "./controllers";

import LocalTime from "local-time";
LocalTime.config.useFormat24 = true;
LocalTime.start();

document.addEventListener("turbo:frame-missing", async function (event) {
  event.preventDefault()

  // Replace the document with whatever was returned in the response, without replacing the URL
  document.open();
  for await (const chunk of event.detail.response.body) {
    document.write(new TextDecoder().decode(chunk));
  }
  document.close();
})
