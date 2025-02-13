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

// Allow table elements in Bootstrap tooltips
const defaultAllowList = bootstrap.Tooltip.Default.allowList

defaultAllowList.a = ['target', 'href', 'title', 'rel', 'data-action', 'data-bs-toggle', 'data-bs-title']
defaultAllowList.code = ['data-clipboard-target']
defaultAllowList.i = []
defaultAllowList.li = ['data-controller']
defaultAllowList.span = ['data-controller', 'data-clipboard-target']
defaultAllowList.table = []
defaultAllowList.tbody = []
defaultAllowList.tr = []
defaultAllowList.td = []
defaultAllowList.nobr = []

