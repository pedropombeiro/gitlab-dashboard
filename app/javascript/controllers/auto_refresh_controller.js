import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="auto-refresh"
export default class extends Controller {
  static values = { timeout: Number, targetDomId: String };

  controller = new AbortController();
  nextRefreshTimestamp = 0;
  timeoutID = 0;

  connect() {
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

      this.refresh();
    };

    document.addEventListener("visibilitychange", onVisibilityChange, false, { signal: this.controller.signal });

    const timeoutValue = this.hasTimeoutValue ? this.timeoutValue : 60000;
    this.nextRefreshTimestamp = Date.now() + timeoutValue;
    this.timeoutID = setTimeout(this.refresh.bind(this), timeoutValue);
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

    if (this.hasTargetDomIdValue) {
      const element = document.getElementById(this.targetDomIdValue);
      if (element) {
        element.reload();
      }
    } else {
      location.reload();
    }
  }
}
