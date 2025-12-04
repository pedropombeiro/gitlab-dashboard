import { Controller } from "@hotwired/stimulus";
import { Chart } from "chart.js";
import { getThemeColors } from "../lib/chart_config";

// Connects to data-controller="theme-selector"
export default class ThemeSelectorController extends Controller {
  static targets = ["button", "chart"];

  declare readonly hasButtonTarget: boolean;
  declare readonly hasChartTarget: boolean;
  declare readonly buttonTarget: HTMLElement;
  declare readonly chartTarget: HTMLElement;

  isDark(): boolean {
    return (
      localStorage.theme === "dark" ||
      (!("theme" in localStorage) && window.matchMedia("(prefers-color-scheme: dark)").matches)
    );
  }

  refreshTheme(): void {
    if (this.element === null) {
      return;
    }

    const isDark = this.isDark();

    if (isDark) {
      this.element.setAttribute("data-bs-theme", "dark");
      if (this.hasButtonTarget) {
        this.buttonTarget.innerHTML = '<i class="bi bi-moon-fill"></i>';
      }
    } else {
      this.element.setAttribute("data-bs-theme", "light");
      if (this.hasButtonTarget) {
        this.buttonTarget.innerHTML = '<i class="bi bi-sun-fill"></i>';
      }
    }
  }

  refreshChartsTheme(isDark: boolean): void {
    // Charts will automatically pick up theme changes via CSS variables
    // Trigger a chart update if Chart.js instances are available
    if (this.hasChartTarget && typeof window.Chart !== "undefined") {
      const canvases = this.chartTarget.getElementsByTagName("canvas");
      for (const canvas of canvases) {
        const chartInstance = Chart.getChart(canvas);
        if (chartInstance) {
          this.updateChartTheme(chartInstance, isDark);
        }
      }
    }
  }

  updateChartTheme(chartInstance: Chart, _isDark: boolean): void {
    // Update chart options to use CSS variable colors
    const colors = getThemeColors();

    if (chartInstance.options.scales) {
      Object.values(chartInstance.options.scales).forEach((scale) => {
        if (scale?.ticks) scale.ticks.color = colors.text;
        if (scale?.grid) scale.grid.color = colors.grid;
      });
    }

    if (chartInstance.options.plugins?.legend?.labels) {
      chartInstance.options.plugins.legend.labels.color = colors.text;
    }

    chartInstance.update();
  }

  toggleTheme(): void {
    if (localStorage.theme === "dark") {
      localStorage.theme = "light";
    } else {
      localStorage.theme = "dark";
    }
    this.refreshTheme();
    this.refreshChartsTheme(this.isDark());
  }

  connect(): void {
    this.refreshTheme();
  }

  chartTargetConnected(_chart: Element): void {
    // Chart theme will be applied when theme is toggled
    this.refreshChartsTheme(this.isDark());
  }

  buttonTargetConnected(_button: Element): void {
    this.refreshTheme();
  }

  switch(event: Event): void {
    event.preventDefault();

    this.toggleTheme();
  }
}
