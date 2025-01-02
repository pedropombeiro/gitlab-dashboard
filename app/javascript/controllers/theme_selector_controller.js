import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="theme-selector"
export default class extends Controller {
  static targets = ["button", "graph"];

  isDark() {
    return (
      localStorage.theme === "dark" ||
      (!("theme" in localStorage) && window.matchMedia("(prefers-color-scheme: dark)").matches)
    );
  }

  refreshTheme() {
    const isDark = this.isDark();

    if (isDark) {
      this.element.setAttribute("data-bs-theme", "dark");
      this.buttonTarget.innerHTML = '<i class="fa-regular fa-moon"></i>';
    } else {
      this.element.setAttribute("data-bs-theme", "light");
      this.buttonTarget.innerHTML = '<i class="fa-regular fa-sun"></i>';
    }

    this.refreshChartsTheme(isDark);
  }

  refreshChartsTheme(isDark) {
    const fn = this.refreshChartTheme;

    Chartkick.eachChart(function (chart) {
      fn(chart.element, isDark);
    });
  }

  refreshChartTheme(chart, isDark) {
    const canvases = chart.getElementsByTagName("canvas");

    if (canvases.length === 0) {
      // Workaround: if the canvas isn't yet loaded, retry in a short while. This will lead to short periods of wrong
      // styling, but its the best we can do for now.
      setTimeout(() => {
        this.refreshChartTheme(chart, isDark);
      }, 500);
      return;
    }

    for (const canvas of canvases) {
      if (isDark) {
        canvas.classList.add("dark-canvas");
      } else {
        canvas.classList.remove("dark-canvas");
      }
    }
  }

  toggleTheme() {
    if (localStorage.theme === "dark") {
      localStorage.theme = "light";
    } else {
      localStorage.theme = "dark";
    }
    this.refreshTheme();
  }

  connect() {
    console.log("Connecting theme-selector");
    this.refreshTheme();
  }

  graphTargetConnected(graph) {
    this.refreshChartTheme(graph, this.isDark());
  }

  switch(event) {
    event.preventDefault();

    this.toggleTheme();
  }
}
