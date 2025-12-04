import { Controller } from "@hotwired/stimulus";

// Turbo Frame element with reload method
interface TurboFrameElement extends HTMLElement {
  reload: () => void;
}

// Connects to data-controller="auto-refresh"
export default class AutoRefreshController extends Controller {
  static values = { timeout: Number, targetDomId: String };
  static targets = ["liveRegion"];

  declare readonly hasTimeoutValue: boolean;
  declare readonly hasTargetDomIdValue: boolean;
  declare readonly hasLiveRegionTarget: boolean;
  declare readonly timeoutValue: number;
  declare readonly targetDomIdValue: string;
  declare readonly liveRegionTarget: HTMLElement;

  private controller = new AbortController();
  private nextRefreshTimestamp = 0;
  private timeoutID: ReturnType<typeof setTimeout> | 0 = 0;

  connect(): void {
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

    document.addEventListener("visibilitychange", onVisibilityChange, { signal: this.controller.signal });

    const timeoutValue = this.timeoutValue ?? 60000;
    this.nextRefreshTimestamp = Date.now() + timeoutValue;
    this.timeoutID = setTimeout(this.refresh.bind(this), timeoutValue);
  }

  disconnect(): void {
    this.controller.abort();
  }

  refresh(): void {
    if (this.timeoutID !== 0) {
      // Avoid re-entry caused by visibility change happening when timeout expires
      clearTimeout(this.timeoutID);
      this.timeoutID = 0;
      this.nextRefreshTimestamp = 0;
      this.controller.abort();
    }

    // Announce update to screen readers
    this.announceUpdate();

    if (this.hasTargetDomIdValue) {
      const element = document.getElementById(this.targetDomIdValue) as TurboFrameElement | null;
      if (element && "reload" in element) {
        element.reload();
      }
    } else {
      location.reload();
    }
  }

  private announceUpdate(): void {
    if (!this.hasLiveRegionTarget) {
      return;
    }

    const timestamp = new Date().toLocaleTimeString();
    this.liveRegionTarget.textContent = `Content updated at ${timestamp}`;

    // Clear the message after a short delay to allow multiple announcements
    setTimeout(() => {
      if (this.hasLiveRegionTarget) {
        this.liveRegionTarget.textContent = "";
      }
    }, 1000);
  }
}
