// DRD Operations — Web Push Service Worker
// Receives push events from the server and shows native browser notifications
// even when the browser tab is closed.

self.addEventListener('push', event => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = { title: 'DRD Operations', body: event.data ? event.data.text() : '' };
  }

  const title = payload.title || 'DRD Operations';
  const body = payload.body || 'You have a new notification';
  const type = payload.type || 'general';
  const isCall = type === 'call_incoming' || type === 'live_session_invite';

  const options = {
    body,
    icon: '/logo1.png',
    badge: '/logo1.png',
    tag: type,
    renotify: true,
    requireInteraction: isCall,
    vibrate: isCall ? [400, 150, 400, 150, 400] : [200],
    data: payload,
    actions: isCall
      ? [{ action: 'join', title: 'Join Call' }, { action: 'dismiss', title: 'Dismiss' }]
      : [{ action: 'open', title: 'Open' }],
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const data = event.notification.data || {};
  const action = event.action;

  if (action === 'dismiss') return;

  let url = '/';
  if (data.type === 'call_incoming' || data.type === 'live_session_invite') {
    url = '/live';
  } else if (data.type === 'new_message') {
    url = '/comms';
  } else if (data.ref_type === 'mission') {
    url = '/missions';
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
      // Focus existing tab if already open
      for (const client of clientList) {
        if ('focus' in client) {
          client.postMessage({ type: 'push_notification_click', data });
          return client.focus();
        }
      }
      // Otherwise open a new tab
      return clients.openWindow(url);
    })
  );
});

self.addEventListener('pushsubscriptionchange', event => {
  // Re-subscribe if the push subscription expires
  event.waitUntil(
    self.registration.pushManager.subscribe(event.oldSubscription.options)
      .then(newSub => {
        // Notify all clients to re-register the new subscription with the server
        return clients.matchAll({ type: 'window' }).then(clientList => {
          clientList.forEach(c => c.postMessage({ type: 'resubscribe', subscription: newSub.toJSON() }));
        });
      })
      .catch(() => {})
  );
});
