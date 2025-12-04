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
    try {
      const chartData = await this.fetchData();

      const canvas = document.createElement("canvas");
      this.chartTarget.replaceChildren(canvas);

      // Get theme colors from CSS variables
      const styles = getComputedStyle(document.documentElement);
      const textColor = styles.getPropertyValue("--chart-text-color").trim();
      const gridColor = styles.getPropertyValue("--chart-grid-color").trim();

      const ctx = canvas.getContext("2d");
      new Chart(ctx, {
        type: "bar",
        data: chartData,
        plugins: [ChartDataLabels],
        options: {
          height: "100%",
          aspectRatio: 3,
          datasets: {
            line: {
              pointStyle: "circle",
              tension: 0.5,
            },
          },
          scales: {
            x: {
              ticks: { color: textColor },
              grid: { color: gridColor },
            },
            y: {
              ticks: { color: textColor },
              grid: { color: gridColor },
            },
          },
          plugins: {
            legend: {
              labels: {
                color: textColor,
                filter: (legendItem, _data) => {
                  return legendItem.text.trim() !== "MTD merged count";
                },
              },
            },
            datalabels: {
              display: function (context) {
                if (context === undefined || context.dataset.stack !== "merged-count") {
                  return false;
                }

                function sortByY(data) {
                  if (!Array.isArray(data)) {
                    throw new Error("Input must be an array.");
                  }

                  if (data.length === 0) {
                    return []; // Return empty array if input is empty
                  }

                  // Sort the array in descending order based on the y-value
                  return [...data].sort((a, b) => b.y - a.y);
                }

                const dataPoints = context.dataset.data;
                if (dataPoints.length >= 3) {
                  const value = dataPoints[context.dataIndex].y;
                  const sortedDataPoints = sortByY(dataPoints);
                  if (sortedDataPoints !== undefined && value >= sortedDataPoints[2].y) {
                    return true;
                  }
                }

                return false;
              },
              color: "#fff",
              font: {
                weight: "bold",
              },
              formatter: function (value) {
                return value.y;
              },
            },
          },
        },
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
    if (this.chartTarget !== null) {
      this.chartTarget.replaceChildren();
    }
  }
}
