import { MdNotifications, MdSearch } from "react-icons/md";
import { useAuthStore } from "../../stores/authStore";
import { mediaUrl } from "../../services/api";
import { useState } from "react";
import { useNavigate } from "react-router-dom";

interface Props { title: string; }

export default function TopNav({ title }: Props) {
  const { user } = useAuthStore();
  const [search, setSearch] = useState("");
  const navigate = useNavigate();

  return (
    <header style={{
      height: 52,
      background: "#020602",
      borderBottom: "1px solid #0f1f0f",
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      padding: "0 20px",
      flexShrink: 0,
    }}>
      {/* Page title — terminal style */}
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <span style={{ color: "#16a34a", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, letterSpacing: 1 }}>
          ~/
        </span>
        <h1 style={{
          color: "#d1fae5",
          fontSize: 12,
          fontWeight: 700,
          margin: 0,
          fontFamily: "'JetBrains Mono', monospace",
          letterSpacing: 2,
          textTransform: "uppercase",
        }}>
          {title}
        </h1>
        <span style={{
          display: "inline-block",
          width: 8, height: 14,
          background: "#16a34a",
          marginLeft: 2,
          animation: "blink 1.2s step-end infinite",
        }} className="cursor-blink" />
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        {/* Search */}
        <div style={{ position: "relative" }}>
          <MdSearch style={{ position: "absolute", left: 8, top: "50%", transform: "translateY(-50%)", color: "#374151" }} size={14} />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="SEARCH..."
            style={{
              background: "#040804",
              color: "#22c55e",
              fontSize: 11,
              fontFamily: "'JetBrains Mono', monospace",
              letterSpacing: 1,
              paddingLeft: 28, paddingRight: 12,
              paddingTop: 6, paddingBottom: 6,
              border: "1px solid #0f1f0f",
              outline: "none",
              width: 180,
            }}
            onFocus={(e) => { e.target.style.borderColor = "#16a34a"; }}
            onBlur={(e) => { e.target.style.borderColor = "#0f1f0f"; }}
          />
        </div>

        {/* Alerts */}
        <button
          onClick={() => navigate("/notifications")}
          style={{
            position: "relative",
            padding: "6px",
            background: "transparent",
            border: "1px solid #0f1f0f",
            cursor: "pointer",
            color: "#4b5563",
            display: "flex", alignItems: "center", justifyContent: "center",
            transition: "all 0.1s",
          }}
          onMouseEnter={(e) => { e.currentTarget.style.borderColor = "#16a34a"; e.currentTarget.style.color = "#22c55e"; }}
          onMouseLeave={(e) => { e.currentTarget.style.borderColor = "#0f1f0f"; e.currentTarget.style.color = "#4b5563"; }}
        >
          <MdNotifications size={16} />
          <span style={{
            position: "absolute", top: 3, right: 3,
            width: 5, height: 5,
            background: "#ef4444",
            borderRadius: "50%",
            boxShadow: "0 0 4px #ef4444",
          }} />
        </button>

        {/* User avatar */}
        {user && (
          <div
            onClick={() => navigate("/profile")}
            style={{
              width: 28, height: 28,
              background: "#0a140a",
              border: "1px solid #16a34a",
              display: "flex", alignItems: "center", justifyContent: "center",
              color: "#22c55e", fontSize: 11, fontWeight: 700,
              cursor: "pointer", overflow: "hidden",
              fontFamily: "'JetBrains Mono', monospace",
            }}
          >
            {user.avatar_url
              ? <img src={mediaUrl(user.avatar_url)} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              : user.full_name?.charAt(0).toUpperCase()}
          </div>
        )}

        {/* Uptime / clock */}
        <span style={{
          color: "#1f2d1f",
          fontSize: 9,
          fontFamily: "'JetBrains Mono', monospace",
          letterSpacing: 1,
          textTransform: "uppercase",
        }}>
          {new Date().toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
        </span>
      </div>
    </header>
  );
}
