// Add a service worker for processing Web Push notifications:
//
self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("push", (event) => {
  event.waitUntil(
    (async () => {
      const { type, payload } = await event.data.json();
      switch (type) {
        case "push_notification": {
          const { title, options, appBadgeCount } = payload;
          const updates = [self.registration.showNotification(title, options)];

          if (typeof appBadgeCount === "number" && "setAppBadge" in navigator) {
            updates.push(appBadgeCount > 0 ? navigator.setAppBadge(appBadgeCount) : navigator.clearAppBadge());
          }

          await Promise.all(updates);
          break;
        }
      }
    })(),
  );
});

self.addEventListener("notificationclick", function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: "window" }).then((clientList) => {
      for (let i = 0; i < clientList.length; i++) {
        let client = clientList[i];
        let clientPath = new URL(client.url).pathname;

        if (clientPath == event.notification.data.url && "focus" in client) {
          return client.focus();
        }
      }

      if (clients.openWindow) {
        return clients.openWindow(event.notification.data.url);
      }
    }),
  );
});

self.addEventListener("pushsubscriptionchange", async (_event) => {
  const subscription = await self.registration.pushManager.getSubscription();
  await fetch("/api/web_push_subscriptions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(subscription),
  });
});
