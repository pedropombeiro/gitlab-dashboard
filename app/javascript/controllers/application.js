import { Application } from "@hotwired/stimulus";

const application = Application.start();

// Configure Stimulus development experience
application.debug = false;
window.Stimulus = application;

export { application };

document.addEventListener("turbo:load", () => {
  switch (Notification.permission) {
    case "granted":
      // send to server
      return;
    case "denied":
      // do nothing?
      return;
    default:
      promptForNotifications();
  }
});

function promptForNotifications() {
  const notificationsButton = document.getElementById("enable_notifications_button");
  if (!notificationsButton) return;

  // Check if the browser supports notifications
  if ("Notification" in window) {
    notificationsButton.classList.remove("d-none");
    notificationsButton.addEventListener("click", async (event) => {
      event.preventDefault();

      // Request permission from the user to send notifications
      try {
        permission = await Notification.requestPermission()
        if (permission === "granted") {
          setupSubscription();
        } else {
          alert("Notifications declined");
        }
      } catch (error) {
        console.log("Notifications error", error)
      }
      finally {
        notificationsButton.classList.add("d-none");
      }
    });
  }
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
    const response = await fetch("/web_push_subscriptions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(subscription),
    });

    if (response.ok) {
      console.log("Subscription successfully saved on the server.");
    } else {
      console.error("Error saving subscription on the server.");
    }
  } catch (error) {
    console.error("Error sending subscription to the server:", error);
  }
}
