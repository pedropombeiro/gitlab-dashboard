import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="web-push"
export default class extends Controller {
  static targets = ["subscribe"];
  static classes = ["subscribed", "unsubscribed"];

  subscribeTargetConnected(subscribeButton) {
    // Check if the browser supports notifications
    subscribeButton.classList.add(this.subscribedClass);
    if ("Notification" in window) {
      switch (Notification.permission) {
        case "granted":
          // send to server
          return;
        case "denied":
          // do nothing?
          return;
        default:
          // show button
          subscribeButton.classList.remove(this.subscribedClass);
          subscribeButton.classList.add(this.unsubscribedClass);
      }
    } else {
      console.warn("Push notifications not supported.");
    }
  }

  async subscribe(event) {
    event.preventDefault();

    // Request permission from the user to send notifications
    try {
      const permission = await Notification.requestPermission();
      if (permission === "granted") {
        setupSubscription();
      } else {
        alert("Notifications declined");
      }
    } catch (error) {
      console.error("Notifications error", error);
    } finally {
      this.subscribeTarget.classList.add(this.subscribedClass);
    }

    async function setupSubscription() {
      if (Notification.permission !== "granted") return;
      if (!navigator.serviceWorker) return;

      let vapid = new Uint8Array(JSON.parse(document.querySelector("meta[name=web_push_public_key]")?.content));

      await navigator.serviceWorker.register("/service-worker.js");
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: vapid,
      });

      try {
        const csrfToken = document.querySelector("meta[name=csrf-token]")?.content;
        const response = await fetch("/api/web_push_subscriptions", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken,
          },
          body: JSON.stringify(subscription),
        });

        if (!response.ok) {
          console.error("Error saving subscription on the server.");
        }
      } catch (error) {
        console.error("Error sending subscription to the server:", error);
      }
    }
  }
}
