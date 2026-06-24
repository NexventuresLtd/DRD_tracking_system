import { useState } from "react";
import { NavLink, useNavigate } from "react-router-dom";
import { useAuthStore } from "../../stores/authStore";
import { authApi, mediaUrl } from "../../services/api";
import {
  MdDashboard, MdMap, MdPeople, MdAssignment, MdRoute,
  MdChat, MdSecurity, MdLogout, MdAdminPanelSettings,
  MdNotifications, MdEvStation, MdVideocam, MdLocationOn,
  MdInventory, MdQueryStats, MdWarning, MdHistory, MdDomain, MdCropFree,
  MdSettings, MdChevronLeft, MdChevronRight,
} from "react-icons/md";

// ── Role metadata ─────────────────────────────────────────────────────────
const ROLE_META: Record<string, { label: string; color: string; bg: string }> = {
  operations_coordinator: { label: "COORD",  color: "#ef4444", bg: "#2d0a0a" },
  planning_officer:       { label: "PLAN",   color: "#f59e0b", bg: "#2d1a00" },
  team_leader:            { label: "LEAD",   color: "#22c55e", bg: "#052e16" },
  field_user:             { label: "FIELD",  color: "#4ade80", bg: "#062010" },
};

// ── Nav config ────────────────────────────────────────────────────────────
const NAV_GROUPS = [
  {
    label: "MAIN",
    items: [
      { to: "/",           icon: MdDashboard,     label: "Dashboard" },
      { to: "/map",        icon: MdMap,           label: "Live Map"  },
      { to: "/teams",      icon: MdPeople,        label: "Teams"     },
      { to: "/comms",      icon: MdChat,          label: "Comms"     },
      { to: "/notifications", icon: MdNotifications, label: "Alerts" },
    ],
    roles: ["all"],
  },
  {
    label: "FIELD OPS",
    items: [
      { to: "/routes",     icon: MdRoute,         label: "Routes"    },
      { to: "/live-feed",  icon: MdVideocam,      label: "Live Feed" },
      { to: "/sos",        icon: MdWarning,       label: "SOS",      danger: true },
    ],
    roles: ["all"],
  },
  {
    label: "COMMAND",
    items: [
      { to: "/missions",   icon: MdAssignment,    label: "Missions"   },
      { to: "/operations", icon: MdEvStation,     label: "Operations" },
      { to: "/posts",      icon: MdDomain,        label: "Facilities" },
      { to: "/zones",      icon: MdCropFree,      label: "Zones"      },
      { to: "/evidence",   icon: MdSecurity,      label: "Evidence"   },
      { to: "/geofences",  icon: MdLocationOn,    label: "Geofences"  },
      { to: "/playback",   icon: MdHistory,       label: "Playback"   },
      { to: "/packages",   icon: MdInventory,     label: "Packages"   },
    ],
    roles: ["operations_coordinator", "planning_officer"],
  },
  {
    label: "INTEL",
    items: [
      { to: "/analytics",  icon: MdQueryStats,    label: "Analytics" },
    ],
    roles: ["operations_coordinator"],
  },
  {
    label: "SYSTEM",
    items: [
      { to: "/admin",      icon: MdAdminPanelSettings, label: "Admin" },
    ],
    roles: ["operations_coordinator"],
  },
];

const S_W = 240;
const S_COLLAPSED = 52;

function NavItem({ to, icon: Icon, label, danger = false, collapsed }: {
  to: string; icon: React.ElementType; label: string; danger?: boolean; collapsed: boolean;
}) {
  return (
    <NavLink
      to={to}
      end={to === "/"}
      title={collapsed ? label : undefined}
      style={({ isActive }) => ({
        display: "flex",
        alignItems: "center",
        gap: collapsed ? 0 : 9,
        padding: collapsed ? "8px 0" : "7px 10px",
        justifyContent: collapsed ? "center" : "flex-start",
        marginBottom: 1,
        textDecoration: "none",
        color: isActive
          ? (danger ? "#ef4444" : "#22c55e")
          : (danger ? "#7f1d1d" : "#4b5563"),
        background: isActive
          ? (danger ? "rgba(127,29,29,0.25)" : "#052e16")
          : "transparent",
        borderLeft: `2px solid ${isActive ? (danger ? "#ef4444" : "#16a34a") : "transparent"}`,
        transition: "all 0.1s",
        borderRadius: collapsed ? "0" : "0",
      })}
      onMouseEnter={(e) => {
        const el = e.currentTarget;
        if (!el.getAttribute("aria-current")) {
          el.style.color = danger ? "#ef4444" : "#d1fae5";
          el.style.background = danger ? "rgba(127,29,29,0.15)" : "#0a1a0a";
        }
      }}
      onMouseLeave={(e) => {
        const el = e.currentTarget;
        if (!el.getAttribute("aria-current")) {
          el.style.color = danger ? "#7f1d1d" : "#4b5563";
          el.style.background = "transparent";
        }
      }}
    >
      <Icon size={15} style={{ flexShrink: 0 }} />
      {!collapsed && (
        <span style={{
          fontFamily: "'Inter', sans-serif",
          fontSize: 11,
          letterSpacing: 0.7,
          textTransform: "uppercase",
          fontWeight: 500,
          whiteSpace: "nowrap",
        }}>
          {label}
        </span>
      )}
    </NavLink>
  );
}

// ── Root ──────────────────────────────────────────────────────────────────
export default function Sidebar() {
  const { user, clearAuth, refresh_token } = useAuthStore();
  const navigate = useNavigate();
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem("sidebar_collapsed") === "true");

  const toggleCollapse = () => {
    const next = !collapsed;
    setCollapsed(next);
    localStorage.setItem("sidebar_collapsed", String(next));
  };

  const handleLogout = async () => {
    if (refresh_token) await authApi.logout(refresh_token).catch(() => {});
    clearAuth();
    navigate("/login");
  };

  const roleMeta = user ? (ROLE_META[user.role] ?? ROLE_META.field_user) : ROLE_META.field_user;

  const visibleGroups = NAV_GROUPS.filter((g) => {
    if (g.roles.includes("all")) return true;
    return user && g.roles.includes(user.role);
  });

  const w = collapsed ? S_COLLAPSED : S_W;

  return (
    <aside style={{
      width: w,
      minWidth: w,
      height: "100vh",
      background: "#020602",
      borderRight: "1px solid #0f1f0f",
      display: "flex",
      flexDirection: "column",
      overflow: "hidden",
      fontFamily: "'Inter', sans-serif",
      flexShrink: 0,
      transition: "width 0.2s ease, min-width 0.2s ease",
      position: "relative",
    }}>

      {/* ── Logo block ── */}
      <div style={{
        padding: collapsed ? "12px 6px" : "12px 12px",
        borderBottom: "1px solid #0f1f0f",
        flexShrink: 0,
        display: "flex",
        alignItems: "center",
        justifyContent: collapsed ? "center" : "space-between",
        gap: 8,
      }}>
        {collapsed ? (
          <img
            src="/logo1.png"
            alt="DRD"
            style={{ width: 32, height: 32, objectFit: "contain" }}
            onError={(e) => {
              (e.target as HTMLImageElement).style.display = "none";
            }}
          />
        ) : (
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <img
              src="/logo1.png"
              alt="DRD"
              style={{ width: 36, height: 36, objectFit: "contain", flexShrink: 0 }}
              onError={(e) => {
                (e.target as HTMLImageElement).style.display = "none";
              }}
            />
            <div>
              <div style={{
                color: "#22c55e", fontWeight: 700, fontSize: 13,
                fontFamily: "'JetBrains Mono', monospace", letterSpacing: 1,
              }}>
                DRD//OPS
              </div>
              <div style={{
                color: "#1f3d1f", fontSize: 8,
                fontFamily: "'JetBrains Mono', monospace", letterSpacing: 2,
              }}>
                FIELD SYSTEM v2
              </div>
            </div>
          </div>
        )}

        {/* Collapse toggle */}
        <button
          onClick={toggleCollapse}
          title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          style={{
            background: "none", border: "none", cursor: "pointer",
            color: "#374151", padding: 2, display: "flex",
            position: collapsed ? "absolute" : "relative",
            right: collapsed ? 0 : "auto",
            bottom: collapsed ? -28 : "auto",
            zIndex: 10,
          }}
        >
          {collapsed ? <MdChevronRight size={16} /> : <MdChevronLeft size={16} />}
        </button>
      </div>

      {/* ── Online pulse ── */}
      {!collapsed && (
        <div style={{
          display: "flex", alignItems: "center", gap: 6,
          padding: "5px 14px",
          borderBottom: "1px solid #0f1f0f",
          background: "#010401",
        }}>
          <span style={{
            width: 5, height: 5, borderRadius: "50%",
            background: "#22c55e", boxShadow: "0 0 5px #22c55e",
            display: "inline-block", flexShrink: 0,
          }} />
          <span style={{ color: "#1f3d1f", fontSize: 8, fontFamily: "'JetBrains Mono', monospace", letterSpacing: 2 }}>
            SYSTEM ONLINE
          </span>
        </div>
      )}

      {/* ── User identity block ── */}
      {user && (
        <div style={{
          display: "flex", alignItems: "center",
          gap: collapsed ? 0 : 8,
          padding: collapsed ? "10px 0" : "8px 10px",
          justifyContent: collapsed ? "center" : "flex-start",
          borderBottom: "1px solid #0f1f0f",
          background: "#010401",
          flexShrink: 0,
        }}>
          <div style={{
            width: 30, height: 30,
            background: roleMeta.bg,
            border: `1px solid ${roleMeta.color}40`,
            display: "flex", alignItems: "center", justifyContent: "center",
            color: roleMeta.color, fontSize: 11, fontWeight: 700,
            overflow: "hidden", flexShrink: 0,
            fontFamily: "'JetBrains Mono', monospace",
            borderRadius: "50%",
          }}>
            {user.avatar_url
              ? <img src={mediaUrl(user.avatar_url)} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              : (user.full_name?.charAt(0) ?? "?").toUpperCase()}
          </div>
          {!collapsed && (
            <div style={{ minWidth: 0, flex: 1 }}>
              <div style={{
                color: "#d1fae5", fontSize: 11, fontWeight: 600,
                whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
              }}>
                {user.full_name}
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 4, marginTop: 2 }}>
                <span style={{
                  background: roleMeta.bg, color: roleMeta.color,
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: 8, fontWeight: 700, letterSpacing: 1.5,
                  padding: "1px 4px",
                }}>
                  {roleMeta.label}
                </span>
                <span style={{ color: "#1f2d1f", fontSize: 9, fontFamily: "'JetBrains Mono', monospace", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  @{user.username}
                </span>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ── Nav ── */}
      <nav style={{ flex: 1, overflowY: "auto", padding: collapsed ? "6px 2px" : "8px 6px" }}>
        {visibleGroups.map((group, gi) => (
          <div key={group.label} style={{ marginBottom: gi < visibleGroups.length - 1 ? 10 : 0 }}>
            {!collapsed && (
              <div style={{
                color: "#1a2d1a",
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: 8, letterSpacing: 2,
                padding: "4px 10px 5px",
                display: "flex", alignItems: "center", gap: 5,
              }}>
                <span style={{ flex: 1, height: 1, background: "#0d1d0d" }} />
                {group.label}
                <span style={{ flex: 1, height: 1, background: "#0d1d0d" }} />
              </div>
            )}
            {collapsed && gi > 0 && (
              <div style={{ height: 1, background: "#0d1d0d", margin: "6px 4px" }} />
            )}

            {group.items.map((item) => (
              <NavItem key={item.to} {...item} collapsed={collapsed} />
            ))}
          </div>
        ))}
      </nav>

      {/* ── Footer ── */}
      <div style={{ borderTop: "1px solid #0f1f0f", flexShrink: 0 }}>
        <NavLink
          to="/profile"
          title={collapsed ? "Settings" : undefined}
          style={({ isActive }) => ({
            display: "flex", alignItems: "center",
            gap: collapsed ? 0 : 8,
            padding: collapsed ? "9px 0" : "8px 12px",
            justifyContent: collapsed ? "center" : "flex-start",
            textDecoration: "none",
            color: isActive ? "#22c55e" : "#374151",
            background: isActive ? "#052e16" : "transparent",
            borderLeft: `2px solid ${isActive ? "#16a34a" : "transparent"}`,
            transition: "all 0.1s",
          })}
          onMouseEnter={(e) => { if (!e.currentTarget.getAttribute("aria-current")) { e.currentTarget.style.color = "#d1fae5"; e.currentTarget.style.background = "#0a1a0a"; } }}
          onMouseLeave={(e) => { if (!e.currentTarget.getAttribute("aria-current")) { e.currentTarget.style.color = "#374151"; e.currentTarget.style.background = "transparent"; } }}
        >
          <MdSettings size={15} style={{ flexShrink: 0 }} />
          {!collapsed && <span style={{ fontFamily: "'Inter', sans-serif", fontSize: 11, letterSpacing: 0.7, textTransform: "uppercase" }}>Settings</span>}
        </NavLink>

        <button
          onClick={handleLogout}
          title={collapsed ? "Logout" : undefined}
          style={{
            display: "flex", alignItems: "center",
            gap: collapsed ? 0 : 8,
            width: "100%",
            padding: collapsed ? "9px 0" : "8px 12px",
            justifyContent: collapsed ? "center" : "flex-start",
            background: "transparent", border: "none",
            borderTop: "1px solid #0f1f0f",
            cursor: "pointer", color: "#374151",
            fontFamily: "'Inter', sans-serif", fontSize: 11,
            letterSpacing: 0.7, textTransform: "uppercase",
            transition: "all 0.1s",
          }}
          onMouseEnter={(e) => { e.currentTarget.style.color = "#ef4444"; e.currentTarget.style.background = "#1a0505"; }}
          onMouseLeave={(e) => { e.currentTarget.style.color = "#374151"; e.currentTarget.style.background = "transparent"; }}
        >
          <MdLogout size={15} style={{ flexShrink: 0 }} />
          {!collapsed && <span>Disconnect</span>}
        </button>
      </div>
    </aside>
  );
}
