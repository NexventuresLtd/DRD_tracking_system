import { NavLink, useNavigate } from "react-router-dom";
import { useAuthStore } from "../../stores/authStore";
import { authApi, mediaUrl } from "../../services/api";
import {
  MdDashboard, MdMap, MdPeople, MdAssignment, MdRoute,
  MdChat, MdSecurity, MdLogout, MdAdminPanelSettings,
  MdNotifications, MdEvStation, MdVideocam, MdLocationOn,
  MdInventory, MdQueryStats, MdWarning, MdHistory, MdDomain,
} from "react-icons/md";

// ── Role metadata ─────────────────────────────────────────────────────────
const ROLE_META: Record<string, { label: string; color: string; bg: string }> = {
  operations_coordinator: { label: "COORD",  color: "#ef4444", bg: "#2d0a0a" },
  planning_officer:       { label: "PLAN",   color: "#f59e0b", bg: "#2d1a00" },
  team_leader:            { label: "LEAD",   color: "#22c55e", bg: "#052e16" },
  field_user:             { label: "FIELD",  color: "#4ade80", bg: "#062010" },
};

// ── Nav config — grouped by section ──────────────────────────────────────
const NAV_GROUPS = [
  {
    label: "MAIN",
    items: [
      { to: "/",           icon: MdDashboard,  label: "Dashboard" },
      { to: "/map",        icon: MdMap,        label: "Live Map"  },
      { to: "/teams",      icon: MdPeople,     label: "Teams"     },
      { to: "/comms",      icon: MdChat,       label: "Comms"     },
      { to: "/notifications", icon: MdNotifications, label: "Alerts" },
    ],
    roles: ["all"],
  },
  {
    label: "FIELD OPS",
    items: [
      { to: "/routes",     icon: MdRoute,      label: "Routes"    },
      { to: "/live-feed",  icon: MdVideocam,   label: "Live Feed" },
      { to: "/sos",        icon: MdWarning,    label: "SOS",      danger: true },
    ],
    roles: ["all"],
  },
  {
    label: "COMMAND",
    items: [
      { to: "/missions",   icon: MdAssignment, label: "Missions"   },
      { to: "/operations", icon: MdEvStation,  label: "Operations" },
      { to: "/posts",      icon: MdDomain,     label: "Facilities" },
      { to: "/evidence",   icon: MdSecurity,   label: "Evidence"   },
      { to: "/geofences",  icon: MdLocationOn, label: "Geofences"  },
      { to: "/playback",   icon: MdHistory,    label: "Playback"   },
      { to: "/packages",   icon: MdInventory,  label: "Packages"   },
    ],
    roles: ["operations_coordinator", "planning_officer"],
  },
  {
    label: "INTELLIGENCE",
    items: [
      { to: "/analytics",  icon: MdQueryStats, label: "Analytics" },
    ],
    roles: ["operations_coordinator"],
  },
  {
    label: "SYSTEM",
    items: [
      { to: "/admin",      icon: MdAdminPanelSettings, label: "Admin Panel" },
    ],
    roles: ["operations_coordinator"],
  },
];

// ── Nav link item ─────────────────────────────────────────────────────────
function NavItem({ to, icon: Icon, label, danger = false }: {
  to: string; icon: React.ElementType; label: string; danger?: boolean;
}) {
  return (
    <NavLink
      to={to}
      end={to === "/"}
      style={({ isActive }) => ({
        display: "flex",
        alignItems: "center",
        gap: 9,
        padding: "7px 10px",
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
      <Icon size={14} style={{ flexShrink: 0 }} />
      <span style={{
        fontFamily: "'Inter', sans-serif",
        fontSize: 11,
        letterSpacing: 0.7,
        textTransform: "uppercase",
        fontWeight: 500,
      }}>
        {label}
      </span>
    </NavLink>
  );
}

// ── Root ──────────────────────────────────────────────────────────────────
export default function Sidebar() {
  const { user, clearAuth, refresh_token } = useAuthStore();
  const navigate = useNavigate();

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

  return (
    <aside style={{
      width: 220,
      height: "100vh",
      background: "#020602",
      borderRight: "1px solid #0f1f0f",
      display: "flex",
      flexDirection: "column",
      overflow: "hidden",
      fontFamily: "'Inter', sans-serif",
      flexShrink: 0,
    }}>

      {/* ── Logo block ── */}
      <div style={{ padding: "14px 14px 12px", borderBottom: "1px solid #0f1f0f", flexShrink: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
          <div style={{
            width: 34, height: 34,
            background: "#052e16",
            border: "1px solid #16a34a",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontFamily: "'JetBrains Mono', monospace",
            fontWeight: 700, fontSize: 10, color: "#22c55e", letterSpacing: 1,
            flexShrink: 0,
          }}>
            DRD
          </div>
          <div>
            <div style={{ color: "#22c55e", fontWeight: 700, fontSize: 13, fontFamily: "'JetBrains Mono', monospace", letterSpacing: 1 }}>
              DRD//OPS
            </div>
            <div style={{ color: "#1f2d1f", fontSize: 9, fontFamily: "'JetBrains Mono', monospace", letterSpacing: 2 }}>
              FIELD SYS v2.0
            </div>
          </div>
        </div>

        {/* Status row */}
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <span style={{
            width: 6, height: 6, borderRadius: "50%",
            background: "#22c55e",
            boxShadow: "0 0 6px #22c55e",
            display: "inline-block",
            animation: "pulse-green 2s infinite",
            flexShrink: 0,
          }} />
          <span style={{ color: "#1f2d1f", fontSize: 9, fontFamily: "'JetBrains Mono', monospace", letterSpacing: 2 }}>
            SYSTEM ONLINE
          </span>
        </div>
      </div>

      {/* ── User identity block ── */}
      {user && (
        <div style={{
          display: "flex", alignItems: "center", gap: 10,
          padding: "10px 12px",
          borderBottom: "1px solid #0f1f0f",
          background: "#010401",
          flexShrink: 0,
        }}>
          <div style={{
            width: 32, height: 32,
            background: roleMeta.bg,
            border: `1px solid ${roleMeta.color}30`,
            display: "flex", alignItems: "center", justifyContent: "center",
            color: roleMeta.color, fontSize: 12, fontWeight: 700,
            overflow: "hidden", flexShrink: 0,
            fontFamily: "'JetBrains Mono', monospace",
          }}>
            {user.avatar_url
              ? <img src={mediaUrl(user.avatar_url)} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              : user.full_name?.charAt(0).toUpperCase() ?? "?"}
          </div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div style={{
              color: "#d1fae5", fontSize: 12, fontWeight: 600,
              whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
            }}>
              {user.full_name}
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 5, marginTop: 2 }}>
              <span style={{
                background: roleMeta.bg, color: roleMeta.color,
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: 9, fontWeight: 700, letterSpacing: 1.5,
                padding: "1px 5px",
              }}>
                {roleMeta.label}
              </span>
              <span style={{ color: "#1f2d1f", fontSize: 9, fontFamily: "'JetBrains Mono', monospace" }}>
                @{user.username}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* ── Nav ── */}
      <nav style={{ flex: 1, overflowY: "auto", padding: "8px 6px" }}>
        {visibleGroups.map((group, gi) => (
          <div key={group.label} style={{ marginBottom: gi < visibleGroups.length - 1 ? 12 : 0 }}>
            {/* Section header */}
            <div style={{
              color: "#1f2d1f",
              fontFamily: "'JetBrains Mono', monospace",
              fontSize: 9, letterSpacing: 2,
              padding: "4px 10px 6px",
              display: "flex", alignItems: "center", gap: 6,
            }}>
              <span style={{ flex: 1, height: 1, background: "#0f1f0f" }} />
              {group.label}
              <span style={{ flex: 1, height: 1, background: "#0f1f0f" }} />
            </div>

            {group.items.map((item) => (
              <NavItem key={item.to} {...item} />
            ))}
          </div>
        ))}
      </nav>

      {/* ── Footer actions ── */}
      <div style={{ borderTop: "1px solid #0f1f0f", flexShrink: 0 }}>
        <NavLink
          to="/profile"
          style={({ isActive }) => ({
            display: "flex", alignItems: "center", gap: 9,
            padding: "9px 12px", textDecoration: "none",
            color: isActive ? "#22c55e" : "#374151",
            background: isActive ? "#052e16" : "transparent",
            borderLeft: `2px solid ${isActive ? "#16a34a" : "transparent"}`,
            transition: "all 0.1s",
          })}
          onMouseEnter={(e) => { if (!e.currentTarget.getAttribute("aria-current")) { e.currentTarget.style.color = "#d1fae5"; e.currentTarget.style.background = "#0a1a0a"; } }}
          onMouseLeave={(e) => { if (!e.currentTarget.getAttribute("aria-current")) { e.currentTarget.style.color = "#374151"; e.currentTarget.style.background = "transparent"; } }}
        >
          <span style={{ width: 20, height: 20, borderRadius: "50%", background: "#0a140a", border: "1px solid #152015", display: "flex", alignItems: "center", justifyContent: "center", color: "#374151", fontSize: 10, flexShrink: 0 }}>⚙</span>
          <span style={{ fontFamily: "'Inter', sans-serif", fontSize: 11, letterSpacing: 0.7, textTransform: "uppercase" }}>Settings</span>
        </NavLink>

        <button
          onClick={handleLogout}
          style={{
            display: "flex", alignItems: "center", gap: 9,
            width: "100%", padding: "9px 12px",
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
          <MdLogout size={14} style={{ flexShrink: 0 }} />
          <span>Disconnect</span>
        </button>
      </div>
    </aside>
  );
}
