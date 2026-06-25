import { Outlet, useLocation, useNavigate } from "react-router-dom";
import Sidebar from "./Sidebar";
import TopNav from "./TopNav";
import { useEffect, useState } from "react";
import { useAuthStore } from "../../stores/authStore";
import { MdWarning, MdClose } from "react-icons/md";

const PAGE_TITLES: Record<string, string> = {
  "/": "Dashboard",
  "/map": "Live Map",
  "/teams": "Team Management",
  "/missions": "Missions",
  "/routes": "Routes",
  "/operations": "Operations Board",
  "/comms": "Communications",
  "/evidence": "Evidence",
  "/notifications": "Notifications",
  "/admin": "Administration",
  "/admin/users": "User Management",
  "/admin/invites": "Invites & QR Codes",
  "/admin/audit": "Audit Logs",
  "/profile": "Profile & Settings",
  "/playback": "Mission Playback",
  "/analytics": "Analytics",
  "/zones": "Zones & Geofences",
  "/packages": "Mission Packages",
};

interface SOSAlert { id: string; user_name?: string; triggered_by?: string; latitude?: number; longitude?: number; }

function requestNotifPermission() {
  if ("Notification" in window && Notification.permission === "default") {
    Notification.requestPermission();
  }
}

function fireBrowserNotif(title: string, body: string, onClick?: () => void) {
  if (!("Notification" in window) || Notification.permission !== "granted") return;
  const n = new Notification(title, {
    body,
    icon: "/favicon.ico",
    badge: "/favicon.ico",
    tag: "sos-alert",
    requireInteraction: true,
  });
  if (onClick) n.onclick = () => { window.focus(); n.close(); onClick(); };
}

function SOSBanner() {
  const { user } = useAuthStore();
  const navigate = useNavigate();
  const [alerts, setAlerts] = useState<SOSAlert[]>([]);

  // Request browser notification permission once on mount
  useEffect(() => { requestNotifPermission(); }, []);

  useEffect(() => {
    if (!user) return;
    const token = localStorage.getItem("access_token");
    if (!token) return;
    const BASE_WS = (import.meta.env.VITE_API_URL || "http://localhost:1104").replace(/^http/, "ws");
    const ws = new WebSocket(`${BASE_WS}/ws/events?token=${encodeURIComponent(token)}`);
    ws.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.type === "sos_alert") {
          const alert: SOSAlert = { id: msg.sos_id ?? String(Date.now()), user_name: msg.user_name, triggered_by: msg.triggered_by, latitude: msg.latitude, longitude: msg.longitude };
          setAlerts((prev) => [alert, ...prev].slice(0, 3));
          // Fire browser push notification
          const body = msg.message
            ? `${msg.user_name ?? "Unknown"}: ${msg.message}`
            : `${msg.user_name ?? "Unknown"} sent an emergency signal`;
          fireBrowserNotif("🚨 SOS ALERT", body, () => navigate("/sos"));
        } else if (msg.type === "sos_resolved") {
          setAlerts((prev) => prev.filter((a) => a.id !== msg.sos_id));
        }
      } catch { /**/ }
    };
    return () => ws.close();
  }, [user, navigate]);

  if (alerts.length === 0) return null;

  return (
    <div style={{ position: "fixed", top: 12, right: 16, zIndex: 9999, display: "flex", flexDirection: "column", gap: 6 }}>
      {alerts.map((a) => (
        <div key={a.id} style={{ display: "flex", alignItems: "center", gap: 10, padding: "10px 14px", background: "#1a0505", border: "2px solid #dc2626", boxShadow: "0 0 20px rgba(220,38,38,0.4)", minWidth: 280 }}>
          <MdWarning size={18} color="#dc2626" style={{ flexShrink: 0 }} className="animate-pulse" />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ color: "#fca5a5", fontSize: 11, fontWeight: 700, letterSpacing: 1 }}>SOS ALERT</div>
            <div style={{ color: "#fecaca", fontSize: 12, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
              {a.user_name ?? "Unknown"} sent emergency signal
            </div>
          </div>
          <div style={{ display: "flex", gap: 6 }}>
            <button onClick={() => navigate("/sos")}
              style={{ padding: "3px 8px", background: "#dc2626", border: "none", color: "#fff", fontSize: 10, fontWeight: 700, cursor: "pointer", letterSpacing: 1 }}>
              VIEW
            </button>
            <button onClick={() => setAlerts((prev) => prev.filter((x) => x.id !== a.id))}
              style={{ background: "none", border: "none", color: "#7f1d1d", cursor: "pointer" }}>
              <MdClose size={14} />
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

// Per-user notification WebSocket — handles urgent in-app + browser pushes
function UserNotifListener() {
  const { user } = useAuthStore();
  const navigate = useNavigate();

  useEffect(() => {
    if (!user) return;
    const token = localStorage.getItem("access_token");
    if (!token) return;
    const BASE_WS = (import.meta.env.VITE_API_URL || "http://localhost:1104").replace(/^http/, "ws");
    const ws = new WebSocket(`${BASE_WS}/ws/notifications/${user.id}?token=${encodeURIComponent(token)}`);
    ws.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.type === "notification" && msg.notif_type === "sos_alert") {
          fireBrowserNotif(msg.title ?? "🚨 SOS ALERT", msg.body ?? "Emergency signal received", () => navigate("/sos"));
        }
      } catch { /**/ }
    };
    return () => ws.close();
  }, [user, navigate]);

  return null;
}

export default function AppLayout() {
  const location = useLocation();
  const title = PAGE_TITLES[location.pathname] || "DRD System";

  return (
    <div className="flex h-screen bg-gray-950 text-white overflow-hidden">
      <SOSBanner />
      <UserNotifListener />
      <Sidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <TopNav title={title} />
        <main className="flex-1 overflow-auto">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
