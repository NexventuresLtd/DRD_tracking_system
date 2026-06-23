import { Outlet, useLocation } from "react-router-dom";
import Sidebar from "./Sidebar";
import TopNav from "./TopNav";

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
  "/geofences": "Geofences",
  "/packages": "Mission Packages",
};

export default function AppLayout() {
  const location = useLocation();
  const title = PAGE_TITLES[location.pathname] || "DRD System";

  return (
    <div className="flex h-screen bg-gray-950 text-white overflow-hidden">
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
