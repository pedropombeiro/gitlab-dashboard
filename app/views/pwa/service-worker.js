// Add a service worker for processing Web Push notifications:
//
self.addEventListener("push", async (event) => {
  const { type, payload } = await event.data.json();
  switch (type) {
    case "push_notification": {
      const { title, options } = payload;
      event.waitUntil(self.registration.showNotification(title, options));
      break;
    }
  }
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
  await fetch("/web_push_subscriptions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(subscription),
  });
});
