const BASE_WS = (() => {
  const url = import.meta.env.VITE_API_URL || 'https://drd.nexventures.net/';
  return url.replace(/^https/, 'wss').replace(/^http/, 'ws');
})();
console.log(`WebSocket Base URL: ${BASE_WS}`);
type Handler<T = unknown> = (data: T) => void;

class WSChannel {
  private ws: WebSocket | null = null;
  private handlers = new Set<Handler>();
  private timer: ReturnType<typeof setTimeout> | null = null;
  private _path = '';
  private _token = '';
  private alive = false;

  connect(path: string, token: string) {
    this._path = path;
    this._token = token;
    this.alive = true;
    this.open();
  }

  private open() {
    if (!this.alive) return;
    try {
      this.ws = new WebSocket(`${BASE_WS}${this._path}?token=${this._token}`);

      this.ws.onmessage = e => {
        try {
          const data = JSON.parse(e.data as string);
          this.handlers.forEach(h => h(data));
        } catch { /* ignore non-JSON */ }
      };

      this.ws.onclose = () => {
        if (this.alive) this.schedule();
      };

      this.ws.onerror = () => {
        this.ws?.close();
      };
    } catch {
      this.schedule();
    }
  }

  private schedule(delay = 5000) {
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => this.open(), delay);
  }

  subscribe(handler: Handler): () => void {
    this.handlers.add(handler);
    return () => { this.handlers.delete(handler); };
  }

  send(data: unknown) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  close() {
    this.alive = false;
    if (this.timer) clearTimeout(this.timer);
    this.ws?.close();
    this.ws = null;
  }

  get isOpen() {
    return this.ws?.readyState === WebSocket.OPEN;
  }
}

export const locationWS = new WSChannel();
export const eventWS = new WSChannel();
export const messageWS = new WSChannel();

export function connectAll(token: string) {
  locationWS.connect('/ws/locations', token);
  eventWS.connect('/ws/events', token);
  messageWS.connect('/ws/messages', token);
}

export function disconnectAll() {
  locationWS.close();
  eventWS.close();
  messageWS.close();
}
