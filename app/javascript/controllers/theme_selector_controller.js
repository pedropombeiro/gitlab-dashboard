import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="theme-selector"
export default class extends Controller {
  refreshTheme() {
    let headElement = document.documentElement;

    if (
      localStorage.theme === "dark" ||
      (!("theme" in localStorage) && window.matchMedia("(prefers-color-scheme: dark)").matches)
    ) {
      headElement.setAttribute("data-bs-theme", "dark");
    } else if (headElement.hasAttribute("data-bs-theme")) {
      headElement.removeAttribute("data-bs-theme");
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
    this.refreshTheme();
  }

  switch(event) {
    event.preventDefault();

    this.toggleTheme();
  }
}
