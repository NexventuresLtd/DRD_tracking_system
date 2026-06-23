import { BrowserRouter, Route, Routes, Navigate } from "react-router-dom";
import { useState, useEffect, Suspense, lazy } from "react";
import { useAuthStore } from "./stores/authStore";
import AppLayout from "./components/layout/AppLayout";

const Login = lazy(() => import("./Pages/Login"));
const Dashboard = lazy(() => import("./Pages/Dashboard"));
const Teams = lazy(() => import("./Pages/Teams"));
const Admin = lazy(() => import("./Pages/Admin"));
const Profile = lazy(() => import("./Pages/Profile"));
const LiveMap = lazy(() => import("./Pages/LiveMap"));
const Missions = lazy(() => import("./Pages/Missions"));
const Comms = lazy(() => import("./Pages/Comms"));
const NotificationsPage = lazy(() => import("./Pages/NotificationsPage"));
const Operations = lazy(() => import("./Pages/Operations"));
const RoutesPage = lazy(() => import("./Pages/Routes"));
const Evidence = lazy(() => import("./Pages/Evidence"));
const TeamDetail = lazy(() => import("./Pages/TeamDetail"));
const SOSPage = lazy(() => import("./Pages/SOS"));
const Geofences = lazy(() => import("./Pages/Geofences"));
const LiveFeed = lazy(() => import("./Pages/LiveFeed"));
const PlaybackPage = lazy(() => import("./Pages/Playback"));
const AnalyticsPage = lazy(() => import("./Pages/Analytics"));
const PackagesPage = lazy(() => import("./Pages/Packages"));

function ProtectedRoute({ children, roles }: { children: React.ReactNode; roles?: string[] }) {
  const { isAuthenticated, user } = useAuthStore();
  if (!isAuthenticated) return <Navigate to="/login" replace />;
  if (roles && user && !roles.includes(user.role)) return <Navigate to="/" replace />;
  return <>{children}</>;
}

function ComingSoon({ title }: { title: string }) {
  return (
    <div className="p-6">
      <div className="text-center py-24">
        <p className="text-gray-500 text-sm uppercase tracking-widest mb-2">Coming Soon</p>
        <h2 className="text-white text-2xl font-bold">{title}</h2>
        <p className="text-gray-400 text-sm mt-2">This feature is being built — check back soon.</p>
      </div>
    </div>
  );
}

function OfflineOverlay() {
  const [offline, setOffline] = useState(!navigator.onLine);

  useEffect(() => {
    const on = () => setOffline(false);
    const off = () => setOffline(true);
    window.addEventListener("online", on);
    window.addEventListener("offline", off);
    return () => {
      window.removeEventListener("online", on);
      window.removeEventListener("offline", off);
    };
  }, []);

  if (!offline) return null;

  return (
    <div
      className="fixed inset-0 z-99999 flex flex-col items-center justify-center"
      style={{ background: "#050C1A", fontFamily: "'Poppins', sans-serif" }}
    >
      <div className="absolute inset-0 pointer-events-none" style={{
        backgroundImage: "linear-gradient(rgba(34,197,94,0.05) 1px, transparent 1px), linear-gradient(90deg, rgba(34,197,94,0.05) 1px, transparent 1px)",
        backgroundSize: "48px 48px",
      }} />

      <div className="relative z-10 flex flex-col items-center gap-6 p-8 text-center max-w-sm">
        <div className="relative">
          <div className="w-20 h-20 rounded-full flex items-center justify-center animate-pulse"
            style={{ background: "rgba(239,68,68,0.12)", border: "2px solid rgba(239,68,68,0.4)" }}>
            <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="#ef4444" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="1" y1="1" x2="23" y2="23" />
              <path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55" />
              <path d="M5 12.55a10.94 10.94 0 0 1 5.17-2.39" />
              <path d="M10.71 5.05A16 16 0 0 1 22.56 9" />
              <path d="M1.42 9a15.91 15.91 0 0 1 4.7-2.88" />
              <path d="M8.53 16.11a6 6 0 0 1 6.95 0" />
              <line x1="12" y1="20" x2="12.01" y2="20" />
            </svg>
          </div>
          <span className="absolute top-0 right-0 w-4 h-4 rounded-full bg-red-500 border-2 border-slate-950 animate-ping" />
        </div>

        <div>
          <h1 className="text-white font-black text-2xl tracking-wide mb-2">NO CONNECTION</h1>
          <p className="text-slate-400 text-sm leading-relaxed">
            You are offline. DRD Tracking requires an active network connection to receive live field data.
          </p>
        </div>

        <div className="flex flex-col gap-2 w-full">
          <div className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs" style={{ background: "rgba(239,68,68,0.08)", border: "1px solid rgba(239,68,68,0.2)" }}>
            <span className="w-2 h-2 rounded-full bg-red-500 shrink-0" />
            <span className="text-red-400 font-semibold">Command link severed</span>
          </div>
          <div className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs" style={{ background: "rgba(245,158,11,0.08)", border: "1px solid rgba(245,158,11,0.2)" }}>
            <span className="w-2 h-2 rounded-full bg-amber-500 shrink-0 animate-pulse" />
            <span className="text-amber-400">Waiting for network…</span>
          </div>
        </div>

        <button
          onClick={() => window.location.reload()}
          className="w-full py-3 rounded-xl font-bold text-white text-sm tracking-wide transition-all hover:opacity-90 active:scale-[0.98]"
          style={{ background: "#16a34a", border: "none", cursor: "pointer" }}
        >
          Retry Connection
        </button>

        <p className="text-slate-700 text-[10px] tracking-widest">AUTHORIZED PERSONNEL ONLY · DRD OPS</p>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <OfflineOverlay />
      <Suspense fallback={<div style={{ minHeight:"100vh", background:"#000", display:"flex", alignItems:"center", justifyContent:"center" }}><div style={{ width:28, height:28, border:"2px solid #16a34a", borderTopColor:"transparent", borderRadius:"50%", animation:"spin 0.7s linear infinite" }} /></div>}>
        <Routes>
          <Route path="/login" element={<Login />} />

          <Route
            path="/"
            element={
              <ProtectedRoute>
                <AppLayout />
              </ProtectedRoute>
            }
          >
            <Route index element={<Dashboard />} />
            <Route path="map" element={<LiveMap />} />
            <Route path="teams" element={<Teams />} />
            <Route path="teams/:id" element={<TeamDetail />} />
            <Route path="missions" element={<Missions />} />
            <Route path="missions/:id" element={<ComingSoon title="Mission Detail" />} />
            <Route path="routes" element={<RoutesPage />} />
            <Route path="operations" element={<Operations />} />
            <Route path="comms" element={<Comms />} />
            <Route path="evidence" element={<Evidence />} />
            <Route path="notifications" element={<NotificationsPage />} />
            <Route path="sos" element={<SOSPage />} />
            <Route path="geofences" element={<Geofences />} />
            <Route path="live-feed" element={<LiveFeed />} />
            <Route path="playback" element={<PlaybackPage />} />
            <Route path="analytics" element={<AnalyticsPage />} />
            <Route path="packages" element={<PackagesPage />} />
            <Route
              path="admin"
              element={
                <ProtectedRoute roles={["operations_coordinator"]}>
                  <Admin />
                </ProtectedRoute>
              }
            />
            <Route path="profile" element={<Profile />} />
          </Route>

          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}
