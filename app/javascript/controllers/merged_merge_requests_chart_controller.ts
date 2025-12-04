import { Controller } from "@hotwired/stimulus";
import { Chart, type ChartConfiguration } from "chart.js";
import ChartDataLabels from "chartjs-plugin-datalabels";
import { createChartOptions, getThemeColors, shouldDisplayDataLabel } from "../lib/chart_config";

// Connects to data-controller="merged-merge-requests-chart"
export default class MergedMergeRequestsChartController extends Controller {
  static values = { url: String };
  static targets = ["chart"];

  declare readonly urlValue: string;
  declare readonly chartTarget: HTMLElement;

  private chartInstance: Chart | null = null;

  async fetchData(): Promise<ChartConfiguration["data"]> {
    const response = await fetch(this.urlValue);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const data = await response.json();
    return data as ChartConfiguration["data"];
  }

  async createChart(): Promise<void> {
    // Show loading state
    this.chartTarget.innerHTML =
      '<div class="d-flex justify-content-center align-items-center p-5"><span class="spinner-border me-3" role="status"></span><span>Loading chart...</span></div>';

    try {
      const chartData = await this.fetchData();

      const canvas = document.createElement("canvas");
      this.chartTarget.replaceChildren(canvas);

      const ctx = canvas.getContext("2d");
      if (!ctx) {
        throw new Error("Could not get canvas context");
      }

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
              filter: (legendItem) => {
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
            formatter: (value: { y: number }) => value.y,
          },
        },
      });

      const config: ChartConfiguration = {
        type: "bar",
        data: chartData,
        plugins: [ChartDataLabels],
        options,
      };

      this.chartInstance = new Chart(ctx, config);
    } catch (error) {
      console.error("Error creating chart:", error);
      this.chartTarget.innerHTML = "<p class='d-flex justify-content-center'>Error loading chart data.</p>";
    }
  }

  connect(): void {
    // Turbolinks preview restores the DOM except for painted <canvas>
    // since it uses cloneNode(true) - https://developer.mozilla.org/en-US/docs/Web/API/Node/
    //
    // don't rerun JS on preview to prevent
    // 1. animation
    // 2. loading data from URL
    if (document.documentElement.hasAttribute("data-turbolinks-preview")) return;
    if (document.documentElement.hasAttribute("data-turbo-preview")) return;

    void this.createChart();
  }

  disconnect(): void {
    // Properly destroy Chart.js instance to prevent memory leaks
    this.chartInstance?.destroy();
    this.chartInstance = null;

    this.chartTarget.replaceChildren();
  }
}
