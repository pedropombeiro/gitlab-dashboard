import { Controller } from "@hotwired/stimulus";
import { createChartOptions, getThemeColors, shouldDisplayDataLabel } from "../lib/chart_config";

// Connects to data-controller="merged-merge-requests-chart"
export default class extends Controller {
  static values = { url: String };
  static targets = ["chart"];

  chartInstance = null;

  async fetchData() {
    const response = await fetch(this.urlValue);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const data = await response.json();
    return data;
  }

  async createChart() {
    // Show loading state
    this.chartTarget.innerHTML =
      '<div class="d-flex justify-content-center align-items-center p-5"><span class="spinner-border me-3" role="status"></span><span>Loading chart...</span></div>';

    try {
      const chartData = await this.fetchData();

      const canvas = document.createElement("canvas");
      this.chartTarget.replaceChildren(canvas);

      const ctx = canvas.getContext("2d");
      const colors = getThemeColors();

      const options = createChartOptions({
        aspectRatio: 3,
        datasets: {
          line: {
            pointStyle: "circle",
            tension: 0.5,
          },
        },
        plugins: {
          legend: {
            labels: {
              color: colors.text,
              filter: (legendItem, _data) => {
                return legendItem.text.trim() !== "MTD merged count";
              },
            },
          },
          datalabels: {
            display: shouldDisplayDataLabel,
            color: "#fff",
            font: {
              weight: "bold",
            },
            formatter: (value) => value.y,
          },
        },
      });

      this.chartInstance = new Chart(ctx, {
        type: "bar",
        data: chartData,
        plugins: [ChartDataLabels],
        options,
      });
    } catch (error) {
      console.error("Error creating chart:", error);
      // Optionally display an error message to the user:
      this.chartTarget.innerHTML = "<p class='d-flex justify-content-center'>Error loading chart data.</p>";
    }
  }

  connect() {
    // Turbolinks preview restores the DOM except for painted <canvas>
    // since it uses cloneNode(true) - https://developer.mozilla.org/en-US/docs/Web/API/Node/
    //
    // don't rerun JS on preview to prevent
    // 1. animation
    // 2. loading data from URL
    if (document.documentElement.hasAttribute("data-turbolinks-preview")) return;
    if (document.documentElement.hasAttribute("data-turbo-preview")) return;

    this.createChart();
  }

  disconnect() {
    // Properly destroy Chart.js instance to prevent memory leaks
    if (this.chartInstance) {
      this.chartInstance.destroy();
      this.chartInstance = null;
    }

    if (this.chartTarget !== null) {
      this.chartTarget.replaceChildren();
    }
  }
}
