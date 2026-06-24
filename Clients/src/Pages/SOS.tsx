import { useState, useEffect, useCallback, useRef } from "react";
import { MdLocationOn, MdWarning } from "react-icons/md";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";

interface SOSEvent {
  id: string;
  triggered_by: string;
  latitude?: number;
  longitude?: number;
  message?: string;
  status: "active" | "acknowledged" | "resolved";
  acknowledged_by?: string;
  acknowledged_at?: string;
  resolved_at?: string;
  created_at: string;
}

const STATUS_STYLE: Record<string, { bg: string; text: string; border: string }> = {
  active:       { bg: "#fee2e2", text: "#dc2626", border: "#fca5a5" },
  acknowledged: { bg: "#fef9c3", text: "#ca8a04", border: "#fde047" },
  resolved:     { bg: "#dcfce7", text: "#16a34a", border: "#86efac" },
};

const fmtDate = (s: string) => new Date(s).toLocaleString("en-GB", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });

export default function SOSPage() {
  const { user } = useAuthStore();
  const [events, setEvents] = useState<SOSEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [showConfirm, setShowConfirm] = useState(false);
  const [triggering, setTriggering] = useState(false);
  const [countdown, setCountdown] = useState(0);
  const [message, setMessage] = useState("");
  const countdownRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [wsAlert, setWsAlert] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const { data } = await api.get("/sos");
      setEvents(data);
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  // WebSocket for incoming SOS alerts
  useEffect(() => {
    const token = localStorage.getItem("access_token");
    const BASE_WS = (import.meta.env.VITE_API_URL || "http://localhost:1104").replace(/^http/, "ws");
    if (!token || !user) return;
    const ws = new WebSocket(`${BASE_WS}/ws/events?token=${encodeURIComponent(token)}`);
    ws.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.type === "sos_alert") {
          setWsAlert(`🆘 SOS from ${msg.user_name}`);
          setTimeout(() => setWsAlert(null), 6000);
          load();
        } else if (["sos_acknowledged", "sos_resolved"].includes(msg.type)) {
          load();
        }
      } catch { /**/ }
    };
    return () => ws.close();
  }, [user, load]);

  const startTrigger = () => {
    setShowConfirm(true);
    setCountdown(5);
    countdownRef.current = setInterval(() => {
      setCountdown((c) => {
        if (c <= 1) { clearInterval(countdownRef.current!); return 0; }
        return c - 1;
      });
    }, 1000);
  };

  const cancelTrigger = () => {
    setShowConfirm(false);
    clearInterval(countdownRef.current!);
    setCountdown(0);
    setMessage("");
  };

  const confirmTrigger = async () => {
    setTriggering(true);
    try {
      let lat: number | undefined, lng: number | undefined;
      try {
        const pos = await new Promise<GeolocationPosition>((res, rej) => navigator.geolocation.getCurrentPosition(res, rej, { timeout: 5000 }));
        lat = pos.coords.latitude; lng = pos.coords.longitude;
      } catch { /**/ }
      await api.post("/sos", { latitude: lat, longitude: lng, message: message || undefined });
      setShowConfirm(false);
      setMessage("");
      await load();
    } catch { /**/ } finally { setTriggering(false); }
  };

  const acknowledge = async (id: string) => {
    try { await api.put(`/sos/${id}/acknowledge`); await load(); } catch { /**/ }
  };

  const resolve = async (id: string) => {
    try { await api.put(`/sos/${id}/resolve`); await load(); } catch { /**/ }
  };

  const active = events.filter((e) => e.status === "active");
  const canAck = user && ["operations_coordinator", "planning_officer", "team_leader"].includes(user.role);

  return (
    <div className="p-6 max-w-5xl mx-auto">
      {/* WS Banner */}
      {wsAlert && (
        <div className="fixed top-4 left-1/2 -translate-x-1/2 z-50 px-5 py-3 rounded-xl text-sm font-bold text-white animate-bounce"
          style={{ background: "#dc2626", boxShadow: "0 0 24px rgba(220,38,38,0.6)" }}>
          {wsAlert}
        </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-white font-bold text-xl flex items-center gap-2">
            <span className={active.length > 0 ? "animate-pulse" : ""}>🆘</span> SOS Alerts
          </h1>
          {active.length > 0 && (
            <p className="text-red-400 text-sm font-semibold mt-0.5">{active.length} ACTIVE ALERT{active.length > 1 ? "S" : ""}</p>
          )}
        </div>
        <button onClick={startTrigger}
          className="px-5 py-2.5 rounded-xl text-white font-bold text-sm tracking-wide transition-all hover:scale-105 active:scale-95"
          style={{ background: "#dc2626", boxShadow: "0 0 20px rgba(220,38,38,0.4)" }}>
          SEND SOS
        </button>
      </div>

      {/* Active alerts highlighted */}
      {active.length > 0 && (
        <div className="mb-4 space-y-2">
          {active.map((e) => (
            <div key={e.id} className="rounded-xl p-4 animate-pulse"
              style={{ background: "#3b0a0a", border: "2px solid #dc2626" }}>
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-red-300 font-bold text-sm flex items-center gap-1"><MdWarning size={14} /> ACTIVE SOS — {fmtDate(e.created_at)}</p>
                  {e.message && <p className="text-red-200 text-sm mt-1">"{e.message}"</p>}
                  {e.latitude && <p className="text-red-400 text-xs mt-1 flex items-center gap-1"><MdLocationOn size={11} /> {e.latitude.toFixed(5)}, {e.longitude?.toFixed(5)}</p>}
                </div>
                {canAck && (
                  <div className="flex gap-2 shrink-0">
                    <button onClick={() => acknowledge(e.id)}
                      className="px-3 py-1.5 rounded-lg text-xs font-bold text-black"
                      style={{ background: "#fbbf24" }}>
                      ACK
                    </button>
                    <button onClick={() => resolve(e.id)}
                      className="px-3 py-1.5 rounded-lg text-xs font-bold text-white"
                      style={{ background: "#16a34a" }}>
                      RESOLVE
                    </button>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* All events */}
      <div className="rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
        <div className="px-5 py-4" style={{ borderBottom: "1px solid #0a140a" }}>
          <h2 className="text-white font-semibold text-sm">Event History</h2>
        </div>
        {loading ? (
          <div className="p-6 text-center text-gray-500 text-sm">Loading…</div>
        ) : events.length === 0 ? (
          <div className="p-6 text-center text-gray-500 text-sm">No SOS events recorded</div>
        ) : (
          <div className="divide-y" style={{ borderColor: "#040804" }}>
            {events.map((e) => {
              const s = STATUS_STYLE[e.status];
              return (
                <div key={e.id} className="px-5 py-4 flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-xs px-2 py-0.5 rounded-full font-semibold capitalize"
                        style={{ background: `${s.bg}15`, color: s.text, border: `1px solid ${s.border}30` }}>
                        {e.status}
                      </span>
                      <span className="text-gray-400 text-xs">{fmtDate(e.created_at)}</span>
                    </div>
                    {e.message && <p className="text-gray-300 text-sm mt-1">"{e.message}"</p>}
                    {e.latitude && <p className="text-gray-500 text-xs mt-1 flex items-center gap-1"><MdLocationOn size={11} /> {e.latitude.toFixed(5)}, {e.longitude?.toFixed(5)}</p>}
                    {e.acknowledged_at && (
                      <p className="text-yellow-600 text-xs mt-1">ACK {fmtDate(e.acknowledged_at)}</p>
                    )}
                    {e.resolved_at && (
                      <p className="text-green-600 text-xs mt-1">Resolved {fmtDate(e.resolved_at)}</p>
                    )}
                  </div>
                  {canAck && e.status === "active" && (
                    <div className="flex gap-2 shrink-0">
                      <button onClick={() => acknowledge(e.id)}
                        className="px-3 py-1.5 rounded-lg text-xs font-semibold"
                        style={{ background: "#92400e20", color: "#fbbf24", border: "1px solid #92400e50" }}>
                        ACK
                      </button>
                      <button onClick={() => resolve(e.id)}
                        className="px-3 py-1.5 rounded-lg text-xs font-semibold"
                        style={{ background: "#14532d20", color: "#4ade80", border: "1px solid #14532d50" }}>
                        Resolve
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Confirm modal */}
      {showConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: "rgba(0,0,0,0.85)" }}>
          <div className="w-full max-w-sm rounded-2xl p-6 text-center space-y-4"
            style={{ background: "#1a0505", border: "2px solid #dc2626" }}>
            <div className="text-6xl font-black text-red-500">SOS</div>
            <p className="text-white font-semibold text-lg">Trigger emergency alert?</p>
            <p className="text-gray-400 text-sm">This will broadcast your location to all command personnel.</p>
            <textarea value={message} onChange={(e) => setMessage(e.target.value)}
              placeholder="Optional message (e.g. 'Contact at grid 4B')"
              rows={2} className="w-full px-3 py-2 rounded-lg text-white text-sm resize-none"
              style={{ background: "#040804", border: "1px solid #dc2626" }} />
            {countdown > 0 && (
              <div className="text-red-400 text-sm font-semibold">
                Auto-send in {countdown}s…
              </div>
            )}
            <div className="flex gap-3">
              <button onClick={cancelTrigger}
                className="flex-1 py-3 rounded-xl font-bold text-gray-300"
                style={{ background: "#0a140a" }}>
                Cancel
              </button>
              <button onClick={confirmTrigger} disabled={triggering}
                className="flex-1 py-3 rounded-xl font-black text-white disabled:opacity-60"
                style={{ background: "#dc2626", boxShadow: "0 0 20px rgba(220,38,38,0.5)" }}>
                {triggering ? "Sending…" : countdown === 0 ? "SEND NOW" : `SEND (${countdown})`}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
