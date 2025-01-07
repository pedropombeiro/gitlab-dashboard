import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="auto-refresh"
export default class extends Controller {
  static values = { timeout: Number, targetDomId: String };

  controller = new AbortController();
  nextRefreshTimestamp = 0;
  timeoutID = 0;

  connect() {
    console.log("Auto refresh controller connected to", this.targetDomIdValue);

    const onVisibilityChange = () => {
      if (document.visibilityState !== "visible") {
        return;
      }
      if (this.nextRefreshTimestamp === 0) {
        return;
      }
      if (Date.now() < this.nextRefreshTimestamp) {
        return;
      }

      console.log("Auto refreshing after page made visible");
      this.refresh();
    };

    document.addEventListener("visibilitychange", onVisibilityChange, false, { signal: this.controller.signal });

    this.nextRefreshTimestamp = Date.now() + this.timeoutValue;
    this.timeoutID = setTimeout(this.refresh.bind(this), this.timeoutValue);
  }

  disconnect() {
    this.controller.abort();
  }

  refresh() {
    if (this.timeoutID !== 0) {
      // Avoid re-entry caused by visibility change happening when timeout expires
      clearTimeout(this.timeoutID);
      this.timeoutID = 0;
      this.nextRefreshTimestamp = 0;
      this.controller.abort();
    }

    const element = document.getElementById(this.targetDomIdValue);
    if (element) {
      element.reload();
    }
  }
}
