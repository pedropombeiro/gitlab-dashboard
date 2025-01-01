import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="theme-selector"
export default class extends Controller {
  static targets = ["button"];

  isDark() {
    return (
      localStorage.theme === "dark" ||
      (!("theme" in localStorage) && window.matchMedia("(prefers-color-scheme: dark)").matches)
    );
  }

  refreshTheme() {
    if (this.isDark()) {
      this.element.setAttribute("data-bs-theme", "dark");
      this.buttonTarget.innerHTML = '<i class="fa-regular fa-moon"></i>';
    } else {
      this.element.setAttribute("data-bs-theme", "light");
      this.buttonTarget.innerHTML = '<i class="fa-regular fa-sun"></i>';
    }

    Chartkick.eachChart(function (chart) {
      chart.element.firstChild.classList.toggle("dark-canvas");
    });
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

  switch(event) {
    event.preventDefault();

    this.toggleTheme();
  }
}
