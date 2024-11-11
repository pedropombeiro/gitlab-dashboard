import { Application } from "@hotwired/stimulus";

const application = Application.start();

// Configure Stimulus development experience
application.debug = false;
window.Stimulus = application;

export { application };

// Register the serviceWorker script at /service-worker.js from your server if supported
if (navigator.serviceWorker) {
  navigator.serviceWorker.register("/service-worker.js").then(function (_reg) {
    console.log("Service worker change, registered the service worker");
  });
}
// Otherwise, no push notifications :(
else {
  console.error("Service worker is not supported in this browser");
}

navigator.serviceWorker.ready.then((serviceWorkerRegistration) => {
  serviceWorkerRegistration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: window.vapidPublicKey,
  });
});


// Let's check if the browser supports notifications
if (!("Notification" in window)) {
  console.error("This browser does not support desktop notification");
}

// Let's check whether notification permissions have already been granted
else if (Notification.permission === "granted") {
  console.log("Permission to receive notifications has been granted");
}

// Otherwise, we need to ask the user for permission
else if (Notification.permission !== 'denied') {
  Notification.requestPermission(function (permission) {
    // If the user accepts, let's create a notification
    if (permission === "granted") {
      console.log("Permission to receive notifications has been granted");
    }
  });
}
