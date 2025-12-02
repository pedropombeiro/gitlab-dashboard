import "@hotwired/turbo-rails";
import * as bootstrap from "bootstrap";
import "@fortawesome/fontawesome-free/js/all";
import "./controllers";

import LocalTime from "local-time";
LocalTime.config.useFormat24 = true;
LocalTime.start();

import { Chart, registerables } from "chart.js";
import ChartDataLabels from "chartjs-plugin-datalabels";
import "chartjs-plugin-trendline";

Chart.register(...registerables, ChartDataLabels);

// Make Chart.js available globally for inline scripts
window.Chart = Chart;

document.addEventListener("turbo:frame-missing", async function (event) {
  event.preventDefault();

  // Replace the document with whatever was returned in the response, without replacing the URL
  document.open();
  for await (const chunk of event.detail.response.body) {
    document.write(new TextDecoder().decode(chunk));
  }
  document.close();
});

// Allow table elements in Bootstrap tooltips
const defaultAllowList = bootstrap.Tooltip.Default.allowList;

defaultAllowList.a = ["target", "href", "title", "rel", "data-action", "data-bs-toggle", "data-bs-title"];
defaultAllowList.code = ["data-clipboard-target"];
defaultAllowList.i = [];
defaultAllowList.li = ["data-controller"];
defaultAllowList.span = ["data-controller", "data-clipboard-target"];
defaultAllowList.table = [];
defaultAllowList.tbody = [];
defaultAllowList.tr = [];
defaultAllowList.td = [];
defaultAllowList.nobr = [];
