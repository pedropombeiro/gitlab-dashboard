import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="merged-merge-requests-chart"
export default class extends Controller {
  static values = { url: String };
  static targets = ["chart"];

  async fetchData() {
    const response = await fetch(this.urlValue);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const data = await response.json();
    return data;
  }

  async createChart() {
    console.log("Creating chart from url", this.urlValue);

    try {
      const chartData = await this.fetchData();

      const canvas = document.createElement("canvas");
      this.chartTarget.replaceChildren(canvas);

      const ctx = canvas.getContext("2d");
      new Chart(ctx, {
        type: "bar",
        data: chartData,
        options: {
          height: "100%",
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
                generateLabels: (chart) => {
                  const items = Chart.defaults.plugins.legend.labels.generateLabels(chart);

                  return items.filter(label => label.text && label.text.trim() !== "");
                },
              },
            },
          },
        },
      });
    } catch (error) {
      console.error("Error creating chart:", error);
      // Optionally display an error message to the user:
      this.chartTarget.innerHTML = "<p>Error loading chart data.</p>";
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
    if (this.chartTarget !== null) {
      this.chartTarget.replaceChildren();
    }
  }
}
