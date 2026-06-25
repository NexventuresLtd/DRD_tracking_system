function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

let _registered = false;

export async function initWebPush(token: string): Promise<void> {
  if (_registered) return;
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return;

  try {
    const reg = await navigator.serviceWorker.register('/push-sw.js');

    // Get VAPID public key from server
    const keyRes = await fetch('/api/v1/notifications/vapid-public-key', {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!keyRes.ok) return;
    const { public_key } = await keyRes.json();
    if (!public_key) return;

    const existing = await reg.pushManager.getSubscription();
    const subscription = existing ?? await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(public_key),
    });

    // Register subscription with server
    await fetch('/api/v1/notifications/web-subscribe', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(subscription.toJSON()),
    });

    _registered = true;

    // Handle re-subscription requests from the service worker
    navigator.serviceWorker.addEventListener('message', async (event) => {
      if (event.data?.type === 'resubscribe' && event.data.subscription) {
        await fetch('/api/v1/notifications/web-subscribe', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify(event.data.subscription),
        });
      }
    });
  } catch (_) {
    // Push not supported or user denied permission — fail silently
  }
}

export async function unregisterWebPush(token: string): Promise<void> {
  if (!('serviceWorker' in navigator)) return;
  try {
    const reg = await navigator.serviceWorker.ready;
    const sub = await reg.pushManager.getSubscription();
    if (!sub) return;
    const endpoint = sub.endpoint;
    await sub.unsubscribe();
    await fetch(`/api/v1/notifications/web-unsubscribe?endpoint=${encodeURIComponent(endpoint)}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    _registered = false;
  } catch (_) {}
}
