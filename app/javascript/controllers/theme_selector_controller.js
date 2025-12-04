import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="theme-selector"
export default class extends Controller {
  static targets = ["button", "chart"];

  isDark() {
    return (
      localStorage.theme === "dark" ||
      (!("theme" in localStorage) && window.matchMedia("(prefers-color-scheme: dark)").matches)
    );
  }

  refreshTheme() {
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

  refreshChartsTheme(isDark) {
    // Charts will automatically pick up theme changes via CSS variables
    // Trigger a chart update if Chart.js instances are available
    if (this.hasChartTarget && window.Chart) {
      const canvases = this.chartTarget.getElementsByTagName("canvas");
      for (const canvas of canvases) {
        const chartInstance = window.Chart.getChart(canvas);
        if (chartInstance) {
          this.updateChartTheme(chartInstance, isDark);
        }
      }
    }
  }

  updateChartTheme(chartInstance, _isDark) {
    // Update chart options to use CSS variable colors
    const styles = getComputedStyle(document.documentElement);
    const textColor = styles.getPropertyValue("--chart-text-color").trim();
    const gridColor = styles.getPropertyValue("--chart-grid-color").trim();

    if (chartInstance.options.scales) {
      Object.values(chartInstance.options.scales).forEach((scale) => {
        if (scale.ticks) scale.ticks.color = textColor;
        if (scale.grid) scale.grid.color = gridColor;
      });
    }

    if (chartInstance.options.plugins?.legend?.labels) {
      chartInstance.options.plugins.legend.labels.color = textColor;
    }

    chartInstance.update();
  }

  toggleTheme() {
    if (localStorage.theme === "dark") {
      localStorage.theme = "light";
    } else {
      localStorage.theme = "dark";
    }
    this.refreshTheme();
    this.refreshChartsTheme(this.isDark());
  }

  connect() {
    this.refreshTheme();
  }

  chartTargetConnected(_chart) {
    // Chart theme will be applied when theme is toggled
    this.refreshChartsTheme(this.isDark());
  }

  buttonTargetConnected(_button) {
    this.refreshTheme();
  }

  switch(event) {
    event.preventDefault();

    this.toggleTheme();
  }
}
