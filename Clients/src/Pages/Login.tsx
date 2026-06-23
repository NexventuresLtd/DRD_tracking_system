import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { authApi } from "../services/api";
import { useAuthStore } from "../stores/authStore";

const FEATURES = [
  { icon: "◈", label: "LIVE TRACKING",    desc: "Real-time GPS field awareness" },
  { icon: "◉", label: "SECURE COMMS",     desc: "End-to-end encrypted messaging" },
  { icon: "◇", label: "MISSION CONTROL",  desc: "Full operational planning suite" },
  { icon: "◈", label: "MESH NETWORK",     desc: "Offline Reticulum uplink" },
];

export default function Login() {
  const navigate = useNavigate();
  const { setAuth } = useAuthStore();
  const [form, setForm] = useState({ email: "", password: "" });
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [clock, setClock] = useState("");

  useEffect(() => {
    const tick = () => setClock(new Date().toLocaleTimeString("en-GB", { hour12: false }));
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const { data } = await authApi.login(form.email, form.password);
      setAuth(data.user, data.access_token, data.refresh_token);
      navigate("/");
    } catch (err: any) {
      setError(err.response?.data?.detail || "ACCESS DENIED — INVALID CREDENTIALS");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      minHeight: "100vh",
      background: "#000",
      display: "flex",
      fontFamily: "'JetBrains Mono', monospace",
      position: "relative",
      overflow: "hidden",
    }}>
      {/* Background grid */}
      <div style={{
        position: "fixed", inset: 0, pointerEvents: "none",
        backgroundImage:
          "linear-gradient(rgba(22,163,74,0.04) 1px, transparent 1px)," +
          "linear-gradient(90deg, rgba(22,163,74,0.04) 1px, transparent 1px)",
        backgroundSize: "60px 60px",
      }} />

      {/* Scanlines */}
      <div style={{
        position: "fixed", inset: 0, pointerEvents: "none",
        backgroundImage: "repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(0,0,0,0.08) 2px,rgba(0,0,0,0.08) 4px)",
      }} />

      {/* Radial green glow top-left */}
      <div style={{
        position: "fixed", top: -200, left: -200,
        width: 600, height: 600, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(22,163,74,0.07) 0%, transparent 70%)",
        pointerEvents: "none",
      }} />

      {/* ── LEFT PANEL ── */}
      <div style={{
        width: "52%",
        display: "none",
        flexDirection: "column",
        justifyContent: "space-between",
        padding: "48px 52px",
        borderRight: "1px solid #0f1f0f",
        position: "relative",
        zIndex: 1,
      }} className="lg-flex">

        {/* Top brand */}
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: 14, marginBottom: 60 }}>
            <div style={{
              width: 44, height: 44,
              border: "1px solid #16a34a",
              display: "flex", alignItems: "center", justifyContent: "center",
              position: "relative",
            }}>
              <span style={{ color: "#22c55e", fontSize: 12, fontWeight: 700, letterSpacing: 1 }}>DRD</span>
              <div style={{ position: "absolute", top: -1, left: -1, width: 6, height: 6, background: "#22c55e" }} />
              <div style={{ position: "absolute", bottom: -1, right: -1, width: 6, height: 6, background: "#22c55e" }} />
            </div>
            <div>
              <div style={{ color: "#22c55e", fontSize: 14, fontWeight: 700, letterSpacing: 3 }}>DRD OPERATIONS</div>
              <div style={{ color: "#1f2d1f", fontSize: 9, letterSpacing: 3, marginTop: 2 }}>FIELD COORDINATION SYSTEM</div>
            </div>
          </div>

          <div style={{ marginBottom: 48 }}>
            <div style={{ color: "#1f2d1f", fontSize: 10, letterSpacing: 4, marginBottom: 16 }}>PLATFORM OVERVIEW</div>
            <h2 style={{ color: "#d1fae5", fontSize: 28, fontWeight: 700, margin: 0, lineHeight: 1.3, letterSpacing: 1 }}>
              TACTICAL<br />
              <span style={{ color: "#16a34a" }}>COORDINATION</span><br />
              PLATFORM
            </h2>
            <div style={{ width: 48, height: 2, background: "#16a34a", marginTop: 20 }} />
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
            {FEATURES.map(({ icon, label, desc }) => (
              <div key={label} style={{
                display: "flex", alignItems: "center", gap: 16,
                padding: "14px 16px",
                borderLeft: "2px solid #0f1f0f",
                transition: "border-color 0.15s",
              }}
                onMouseEnter={(e) => (e.currentTarget.style.borderLeftColor = "#16a34a")}
                onMouseLeave={(e) => (e.currentTarget.style.borderLeftColor = "#0f1f0f")}
              >
                <span style={{ color: "#16a34a", fontSize: 18, flexShrink: 0 }}>{icon}</span>
                <div>
                  <div style={{ color: "#22c55e", fontSize: 10, letterSpacing: 2, marginBottom: 2 }}>{label}</div>
                  <div style={{ color: "#374151", fontSize: 11 }}>{desc}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Bottom status bar */}
        <div style={{
          display: "flex", justifyContent: "space-between", alignItems: "center",
          borderTop: "1px solid #0f1f0f", paddingTop: 16,
        }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: "#22c55e", boxShadow: "0 0 6px #22c55e", display: "inline-block" }} />
            <span style={{ color: "#1f2d1f", fontSize: 9, letterSpacing: 2 }}>SYSTEM ONLINE</span>
          </div>
          <span style={{ color: "#1f2d1f", fontSize: 9, letterSpacing: 2 }}>{clock}</span>
          <span style={{ color: "#0f1f0f", fontSize: 9, letterSpacing: 1 }}>NODE: OPS-01</span>
        </div>
      </div>

      {/* ── RIGHT PANEL — Form ── */}
      <div style={{
        flex: 1,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "40px 32px",
        position: "relative",
        zIndex: 1,
      }}>
        <div style={{ width: "100%", maxWidth: 380 }}>

          {/* Mobile brand */}
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 40, justifyContent: "center" }}>
            <div style={{ width: 36, height: 36, border: "1px solid #16a34a", display: "flex", alignItems: "center", justifyContent: "center", position: "relative" }}>
              <span style={{ color: "#22c55e", fontSize: 10, fontWeight: 700 }}>DRD</span>
              <div style={{ position: "absolute", top: -1, left: -1, width: 5, height: 5, background: "#22c55e" }} />
              <div style={{ position: "absolute", bottom: -1, right: -1, width: 5, height: 5, background: "#22c55e" }} />
            </div>
            <div>
              <div style={{ color: "#22c55e", fontSize: 12, fontWeight: 700, letterSpacing: 2 }}>DRD OPERATIONS</div>
              <div style={{ color: "#1f2d1f", fontSize: 8, letterSpacing: 2 }}>FIELD COORDINATION SYSTEM</div>
            </div>
          </div>

          {/* Auth card */}
          <div style={{ border: "1px solid #0f1f0f", background: "rgba(2,6,2,0.8)", padding: "36px 32px" }}>

            {/* Card header */}
            <div style={{ marginBottom: 28 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 12 }}>
                <div style={{ flex: 1, height: 1, background: "#0f1f0f" }} />
                <span style={{ color: "#16a34a", fontSize: 9, letterSpacing: 3 }}>SECURE LOGIN</span>
                <div style={{ flex: 1, height: 1, background: "#0f1f0f" }} />
              </div>
              <h1 style={{ color: "#d1fae5", fontSize: 18, fontWeight: 700, margin: 0, letterSpacing: 2 }}>
                OPERATOR AUTH
              </h1>
              <p style={{ color: "#374151", fontSize: 10, margin: "6px 0 0", letterSpacing: 1 }}>
                Enter your credentials to access the system
              </p>
            </div>

            {/* Error */}
            {error && (
              <div style={{
                background: "rgba(127,29,29,0.2)", border: "1px solid #450a0a",
                padding: "10px 14px", marginBottom: 20,
                display: "flex", gap: 8, alignItems: "flex-start",
              }}>
                <span style={{ color: "#ef4444", fontSize: 14, lineHeight: 1, flexShrink: 0 }}>▲</span>
                <span style={{ color: "#fca5a5", fontSize: 11, lineHeight: 1.5 }}>{error}</span>
              </div>
            )}

            {/* Fields */}
            <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 16 }}>

              <div>
                <label style={{ color: "#374151", fontSize: 9, letterSpacing: 2, display: "block", marginBottom: 8 }}>
                  IDENTIFIER
                </label>
                <input
                  type="text"
                  required
                  autoComplete="username"
                  value={form.email}
                  placeholder="Email or username"
                  onChange={(e) => setForm({ ...form, email: e.target.value })}
                  style={{
                    width: "100%", padding: "11px 14px",
                    background: "#040804", border: "1px solid #152015",
                    color: "#d1fae5", fontSize: 12, letterSpacing: 0.5,
                    outline: "none", boxSizing: "border-box",
                    fontFamily: "'JetBrains Mono', monospace",
                    transition: "border-color 0.15s",
                  }}
                  onFocus={(e) => {
                    e.target.style.borderColor = "#16a34a";
                    e.target.style.boxShadow = "0 0 0 1px #16a34a20";
                  }}
                  onBlur={(e) => {
                    e.target.style.borderColor = "#152015";
                    e.target.style.boxShadow = "none";
                  }}
                />
              </div>

              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                  <label style={{ color: "#374151", fontSize: 9, letterSpacing: 2 }}>
                    PASSWORD
                  </label>
                  <button
                    type="button"
                    onClick={() => setShowPass(!showPass)}
                    style={{
                      background: "none", border: "none", cursor: "pointer",
                      color: "#1f2d1f", fontSize: 9, letterSpacing: 1,
                      fontFamily: "'JetBrains Mono', monospace", padding: 0,
                    }}
                    onMouseEnter={(e) => (e.currentTarget.style.color = "#16a34a")}
                    onMouseLeave={(e) => (e.currentTarget.style.color = "#1f2d1f")}
                  >
                    {showPass ? "◉ HIDE" : "◎ SHOW"}
                  </button>
                </div>
                <input
                  type={showPass ? "text" : "password"}
                  required
                  autoComplete="current-password"
                  value={form.password}
                  placeholder="••••••••••••"
                  onChange={(e) => setForm({ ...form, password: e.target.value })}
                  style={{
                    width: "100%", padding: "11px 14px",
                    background: "#040804", border: "1px solid #152015",
                    color: "#d1fae5", fontSize: 12, letterSpacing: 2,
                    outline: "none", boxSizing: "border-box",
                    fontFamily: "'JetBrains Mono', monospace",
                    transition: "border-color 0.15s",
                  }}
                  onFocus={(e) => {
                    e.target.style.borderColor = "#16a34a";
                    e.target.style.boxShadow = "0 0 0 1px #16a34a20";
                  }}
                  onBlur={(e) => {
                    e.target.style.borderColor = "#152015";
                    e.target.style.boxShadow = "none";
                  }}
                />
              </div>

              <button
                type="submit"
                disabled={loading}
                style={{
                  width: "100%", padding: "13px",
                  background: loading ? "#052e16" : "#16a34a",
                  border: "none", cursor: loading ? "not-allowed" : "pointer",
                  color: loading ? "#22c55e" : "#000",
                  fontSize: 11, fontWeight: 700, letterSpacing: 3,
                  fontFamily: "'JetBrains Mono', monospace",
                  display: "flex", alignItems: "center", justifyContent: "center", gap: 10,
                  marginTop: 8, transition: "background 0.15s",
                }}
                onMouseEnter={(e) => { if (!loading) (e.currentTarget as HTMLButtonElement).style.background = "#22c55e"; }}
                onMouseLeave={(e) => { if (!loading) (e.currentTarget as HTMLButtonElement).style.background = "#16a34a"; }}
              >
                {loading
                  ? <><Spinner /> AUTHENTICATING...</>
                  : "ACCESS SYSTEM"
                }
              </button>
            </form>
          </div>

          {/* Status indicators */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 1, marginTop: 1 }}>
            {[
              { label: "UPLINK",  value: "ACTIVE",  green: true  },
              { label: "ENCRYPT", value: "AES-256", green: true  },
              { label: "ACCESS",  value: "RESTRICTED", green: false },
            ].map(({ label, value, green }) => (
              <div key={label} style={{
                background: "rgba(2,6,2,0.8)", border: "1px solid #0f1f0f",
                padding: "8px 10px", textAlign: "center",
              }}>
                <div style={{ color: "#1f2d1f", fontSize: 7, letterSpacing: 2, marginBottom: 3 }}>{label}</div>
                <div style={{ color: green ? "#16a34a" : "#f59e0b", fontSize: 9, letterSpacing: 1, fontWeight: 700 }}>{value}</div>
              </div>
            ))}
          </div>

          <div style={{ textAlign: "center", marginTop: 20 }}>
            <span style={{ color: "#0f1f0f", fontSize: 9, letterSpacing: 2 }}>
              UNAUTHORIZED ACCESS IS PROHIBITED
            </span>
          </div>
        </div>
      </div>

      <style>{`
        @keyframes spin { to { transform: rotate(360deg); } }
        .lg-flex { display: none !important; }
        @media (min-width: 1024px) { .lg-flex { display: flex !important; } }
      `}</style>
    </div>
  );
}

function Spinner() {
  return (
    <span style={{
      display: "inline-block", width: 10, height: 10,
      border: "2px solid #22c55e", borderTopColor: "transparent",
      borderRadius: "50%", animation: "spin 0.7s linear infinite",
    }} />
  );
}
