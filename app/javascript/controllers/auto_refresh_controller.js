import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="auto-refresh"
export default class extends Controller {
  static values = { timeout: Number, targetDomId: String };

  controller = new AbortController();

  connect() {
    console.log("Auto refresh controller connected to", this.targetDomIdValue);

    const onVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        console.log("Auto refreshing after page made visible");
        this.refresh();
      }
    };

    document.addEventListener("visibilitychange", onVisibilityChange, false, { signal: this.controller.signal });

    setTimeout(this.refresh.bind(this), this.timeoutValue);
  }

  disconnect() {
    this.controller.abort();
  }

  refresh() {
    const element = document.getElementById(this.targetDomIdValue);
    if (element) {
      element.reload();
    }
  }
}
