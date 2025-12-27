import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="heartbeat"
// Sends periodic heartbeat pings to keep user's contacted_at timestamp fresh
// This ensures background jobs continue processing updates even when using real-time Turbo Streams
export default class HeartbeatController extends Controller {
  private intervalId: ReturnType<typeof window.setInterval> | null = null;
  private controller = new AbortController();

  // Send heartbeat every 3 minutes (180 seconds)
  // This is well within the 4-hour recently_active threshold
  private readonly HEARTBEAT_INTERVAL = 180_000;

  connect(): void {
    // Send initial heartbeat after 1 minute
    setTimeout(() => this.sendHeartbeat(), 60_000);

    // Then send every 3 minutes
    this.intervalId = window.setInterval(() => this.sendHeartbeat(), this.HEARTBEAT_INTERVAL);

    // Also send heartbeat when page becomes visible after being hidden
    document.addEventListener("visibilitychange", this.handleVisibilityChange.bind(this), {
      signal: this.controller.signal,
    });
  }

  disconnect(): void {
    if (this.intervalId !== null) {
      window.clearInterval(this.intervalId);
      this.intervalId = null;
    }

    this.controller.abort();
  }

  private handleVisibilityChange(): void {
    if (document.visibilityState === "visible") {
      // Send heartbeat when tab becomes visible again
      void this.sendHeartbeat();
    }
  }

  private async sendHeartbeat(): Promise<void> {
    try {
      const csrfToken = document.querySelector("meta[name=csrf-token]")?.getAttribute("content");

      const response = await fetch("/api/heartbeat", {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken || "",
        },
      });

      if (!response.ok && response.status !== 401) {
        // Log error but don't throw - heartbeat failures shouldn't break the app
        console.warn(`Heartbeat failed: ${response.status} ${response.statusText}`);
      }
    } catch {
      // Silently fail - network issues shouldn't break the app
    }
  }
}
