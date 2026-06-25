import { useState, useEffect, useRef, useCallback } from "react";
import { locationApi } from "../services/api";
import { useAuthStore } from "../stores/authStore";
import type { LiveLocation } from "../types";

// ── Helpers ───────────────────────────────────────────────────────────────────

const ROLE_COLOR: Record<string, string> = {
  operations_coordinator: "#ef4444",
  planning_officer: "#f59e0b",
  team_leader: "#22c55e",
  field_user: "#4ade80",
};
const ROLE_LABEL: Record<string, string> = {
  operations_coordinator: "COORD",
  planning_officer: "PLAN",
  team_leader: "LEAD",
  field_user: "FIELD",
};

function ageMs(ts: string): number {
  return Date.now() - new Date(ts).getTime();
}

function relAge(ts: string): string {
  const ms = ageMs(ts);
  if (ms < 60_000)   return `${Math.floor(ms / 1000)}s ago`;
  if (ms < 3_600_000) return `${Math.floor(ms / 60_000)}m ago`;
  return `${Math.floor(ms / 3_600_000)}h ago`;
}

type ConnStatus = "active" | "stale" | "lost";

function connStatus(ts: string): ConnStatus {
  const ms = ageMs(ts);
  if (ms < 2 * 60_000)  return "active";
  if (ms < 10 * 60_000) return "stale";
  return "lost";
}

const STATUS_COLOR: Record<ConnStatus, string> = {
  active: "#22c55e",
  stale:  "#f59e0b",
  lost:   "#ef4444",
};
const STATUS_LABEL: Record<ConnStatus, string> = {
  active: "ACTIVE",
  stale:  "STALE",
  lost:   "LOST",
};

// Signal bars: 0–4 based on data freshness
function signalBars(ts: string): number {
  const ms = ageMs(ts);
  if (ms < 10_000)   return 4;
  if (ms < 30_000)   return 3;
  if (ms < 120_000)  return 2;
  if (ms < 600_000)  return 1;
  return 0;
}

// ── Per-node live stats (updated by WS) ──────────────────────────────────────

interface NodeStat {
  msgCount: number;
  lastMsgAt: number; // epoch ms
  bytesIn: number;
}

// ── Log entry ─────────────────────────────────────────────────────────────────

interface LogEntry {
  id: number;
  ts: string;
  userId: string;
  name: string;
  type: string;
  detail: string;
}

let _logId = 0;

// ── Sub-components ────────────────────────────────────────────────────────────

function SignalBars({ bars, color }: { bars: number; color: string }) {
  return (
    <div style={{ display: "flex", alignItems: "flex-end", gap: 2, height: 14 }}>
      {[1, 2, 3, 4].map((b) => (
        <div
          key={b}
          style={{
            width: 4,
            height: 3 + b * 2.5,
            borderRadius: 1,
            background: bars >= b ? color : "#1f2937",
            transition: "background 0.3s",
          }}
        />
      ))}
    </div>
  );
}

function StatBox({ label, value, color }: { label: string; value: number | string; color: string }) {
  return (
    <div style={{
      padding: "8px 16px",
      border: `1px solid ${color}33`,
      borderRadius: 6,
      background: `${color}0a`,
      minWidth: 72,
      textAlign: "center",
    }}>
      <div style={{ color, fontSize: 22, fontWeight: 800, fontFamily: "monospace", lineHeight: 1 }}>
        {value}
      </div>
      <div style={{ color: `${color}88`, fontSize: 9, letterSpacing: 1.5, marginTop: 3, textTransform: "uppercase" }}>
        {label}
      </div>
    </div>
  );
}

function NodeCard({
  loc,
  stat,
  wsLive,
}: {
  loc: LiveLocation;
  stat: NodeStat | undefined;
  wsLive: boolean;
}) {
  const name = loc.user?.full_name || loc.user?.username || loc.user_id.slice(0, 8);
  const role = loc.user?.role ?? "field_user";
  const roleColor = ROLE_COLOR[role] ?? "#6b7280";
  const roleLabel = ROLE_LABEL[role] ?? role.toUpperCase();
  const status = connStatus(loc.last_updated);
  const statusColor = STATUS_COLOR[status];
  const bars = wsLive && stat ? signalBars(new Date(stat.lastMsgAt).toISOString()) : signalBars(loc.last_updated);
  const lastTs = stat?.lastMsgAt
    ? relAge(new Date(stat.lastMsgAt).toISOString())
    : relAge(loc.last_updated);

  return (
    <div style={{
      background: "#050e05",
      border: `1px solid ${statusColor}33`,
      borderRadius: 8,
      padding: "14px 16px",
      display: "flex",
      flexDirection: "column",
      gap: 10,
      position: "relative",
      overflow: "hidden",
      transition: "border-color 0.4s",
    }}>
      {/* Subtle glow corner */}
      <div style={{
        position: "absolute", top: 0, right: 0,
        width: 60, height: 60,
        background: `radial-gradient(circle at top right, ${statusColor}18, transparent 70%)`,
        pointerEvents: "none",
      }} />

      {/* Header row */}
      <div style={{ display: "flex", alignItems: "flex-start", gap: 10 }}>
        {/* Avatar */}
        <div style={{
          width: 36, height: 36, borderRadius: "50%", flexShrink: 0,
          background: `${roleColor}18`,
          border: `1.5px solid ${roleColor}55`,
          display: "flex", alignItems: "center", justifyContent: "center",
          color: roleColor, fontSize: 13, fontWeight: 700,
          fontFamily: "monospace",
        }}>
          {name.charAt(0).toUpperCase()}
        </div>

        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            color: "#e5e7eb", fontSize: 12, fontWeight: 600,
            whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
          }}>
            {name}
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 5, marginTop: 3 }}>
            <span style={{
              background: `${roleColor}1a`, color: roleColor,
              fontSize: 8, fontWeight: 700, letterSpacing: 1.2,
              padding: "1px 5px", borderRadius: 3,
              fontFamily: "monospace",
            }}>
              {roleLabel}
            </span>
            {loc.user?.team && (
              <span style={{ color: "#4b5563", fontSize: 9 }}>
                {loc.user.team}
              </span>
            )}
          </div>
        </div>

        {/* Status badge */}
        <div style={{
          display: "flex", alignItems: "center", gap: 4,
          padding: "3px 7px", borderRadius: 12,
          background: `${statusColor}12`,
          border: `1px solid ${statusColor}33`,
          flexShrink: 0,
        }}>
          <div style={{
            width: 5, height: 5, borderRadius: "50%",
            background: statusColor,
            boxShadow: status === "active" ? `0 0 6px ${statusColor}` : "none",
            animation: status === "active" ? "pulse-dot 2s ease-in-out infinite" : "none",
          }} />
          <span style={{ color: statusColor, fontSize: 8, letterSpacing: 1, fontFamily: "monospace" }}>
            {STATUS_LABEL[status]}
          </span>
        </div>
      </div>

      {/* Data row */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, borderTop: "1px solid #0f1f0f", paddingTop: 8 }}>
        <SignalBars bars={bars} color={statusColor} />

        <div style={{ flex: 1 }}>
          <div style={{ color: "#6b7280", fontSize: 9, marginBottom: 1 }}>LAST DATA</div>
          <div style={{ color: "#9ca3af", fontSize: 10, fontFamily: "monospace" }}>{lastTs}</div>
        </div>

        {stat && (
          <div style={{ textAlign: "right" }}>
            <div style={{ color: "#6b7280", fontSize: 9, marginBottom: 1 }}>PACKETS</div>
            <div style={{ color: "#38bdf8", fontSize: 11, fontWeight: 700, fontFamily: "monospace" }}>
              {stat.msgCount}
            </div>
          </div>
        )}
      </div>

      {/* Location strip */}
      <div style={{
        background: "#020a02", borderRadius: 4, padding: "4px 8px",
        display: "flex", justifyContent: "space-between", alignItems: "center",
      }}>
        <span style={{ color: "#1f3d1f", fontSize: 9, fontFamily: "monospace" }}>
          {loc.latitude.toFixed(4)}, {loc.longitude.toFixed(4)}
        </span>
        {loc.speed != null && (
          <span style={{ color: "#1f3d1f", fontSize: 9, fontFamily: "monospace" }}>
            {(loc.speed * 3.6).toFixed(1)} km/h
          </span>
        )}
      </div>
    </div>
  );
}

// ── Pulsing WS status dot ─────────────────────────────────────────────────────

function WsDot({ connected }: { connected: boolean }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
      <div style={{
        width: 7, height: 7, borderRadius: "50%",
        background: connected ? "#22c55e" : "#ef4444",
        boxShadow: connected ? "0 0 6px #22c55e" : "none",
      }} />
      <span style={{
        color: connected ? "#22c55e" : "#ef4444",
        fontSize: 9, fontFamily: "monospace", letterSpacing: 1.5,
      }}>
        {connected ? "WS LIVE" : "WS OFF"}
      </span>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function Network() {
  const { user, access_token } = useAuthStore();

  const [nodes, setNodes] = useState<LiveLocation[]>([]);
  const [stats, setStats] = useState<Record<string, NodeStat>>({});
  const [log, setLog] = useState<LogEntry[]>([]);
  const [wsConn, setWsConn] = useState(false);
  const [filter, setFilter] = useState<"all" | "active" | "stale" | "lost">("all");
  const [lastPoll, setLastPoll] = useState<Date | null>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const tickRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const addLog = useCallback((entry: Omit<LogEntry, "id" | "ts">) => {
    const ts = new Date().toLocaleTimeString("en-GB", { hour12: false });
    setLog((prev) => [{ ...entry, id: ++_logId, ts }, ...prev].slice(0, 80));
  }, []);

  const bumpStat = useCallback((userId: string, bytes: number) => {
    setStats((prev) => {
      const cur = prev[userId] ?? { msgCount: 0, lastMsgAt: 0, bytesIn: 0 };
      return {
        ...prev,
        [userId]: {
          msgCount: cur.msgCount + 1,
          lastMsgAt: Date.now(),
          bytesIn: cur.bytesIn + bytes,
        },
      };
    });
  }, []);

  // Poll /locations/live every 5 s
  const poll = useCallback(async () => {
    try {
      const { data } = await locationApi.getLive();
      const list: LiveLocation[] = Array.isArray(data) ? data : (data.locations ?? []);
      setNodes(list);
      setLastPoll(new Date());
    } catch { /* swallow — WS keeps things fresh */ }
  }, []);

  useEffect(() => {
    poll();
    tickRef.current = setInterval(poll, 5_000);
    return () => { if (tickRef.current) clearInterval(tickRef.current); };
  }, [poll]);

  // Force re-render every 15 s so relative timestamps stay fresh
  useEffect(() => {
    const t = setInterval(() => setNodes((n) => [...n]), 15_000);
    return () => clearInterval(t);
  }, []);

  // WebSocket for real-time location events
  useEffect(() => {
    if (!user?.id || !access_token) return;

    const apiBase = import.meta.env.VITE_API_URL || "http://localhost:1104";
    const wsBase  = apiBase.replace(/^http/, "ws");
    const url     = `${wsBase}/ws/location/${user.id}?token=${encodeURIComponent(access_token)}`;

    let alive = true;
    let retryTimer: ReturnType<typeof setTimeout> | null = null;

    function connect() {
      if (!alive) return;
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        if (!alive) { ws.close(); return; }
        setWsConn(true);
        addLog({ userId: "system", name: "SYSTEM", type: "WS", detail: "Connection established" });
      };

      ws.onmessage = (e) => {
        if (!alive) return;
        const raw = e.data as string;
        try {
          const msg = JSON.parse(raw);
          if (msg.type === "location_update") {
            const uid   = msg.user_id as string;
            const bytes = raw.length;
            bumpStat(uid, bytes);

            // Update or insert the node
            setNodes((prev) => {
              const idx = prev.findIndex((n) => n.user_id === uid);
              const updated: LiveLocation = {
                ...((idx >= 0 ? prev[idx] : {}) as LiveLocation),
                user_id: uid,
                latitude:  msg.lat ?? msg.latitude ?? 0,
                longitude: msg.lng ?? msg.longitude ?? 0,
                altitude:  msg.altitude,
                heading:   msg.heading,
                speed:     msg.speed,
                status:    "active",
                last_updated: new Date().toISOString(),
                user: msg.user ?? (idx >= 0 ? prev[idx].user : undefined),
              };
              if (idx >= 0) {
                const next = [...prev];
                next[idx] = updated;
                return next;
              }
              return [updated, ...prev];
            });

            const name = msg.user?.full_name || msg.user?.username || uid.slice(0, 8);
            addLog({ userId: uid, name, type: "LOC", detail: `${(msg.lat ?? msg.latitude ?? 0).toFixed(4)}, ${(msg.lng ?? msg.longitude ?? 0).toFixed(4)}` });
          }

          // Also catch event-type messages for the log
          if (msg.type && msg.type !== "location_update") {
            const uid  = msg.user_id ?? "unknown";
            const name = msg.user?.full_name ?? msg.user?.username ?? uid.slice(0, 8);
            addLog({ userId: uid, name, type: msg.type.replace(/_/g, " ").toUpperCase(), detail: JSON.stringify(msg).slice(0, 80) });
          }
        } catch { /* malformed frame */ }
      };

      ws.onclose = () => {
        setWsConn(false);
        if (alive) retryTimer = setTimeout(connect, 4_000);
      };

      ws.onerror = () => ws.close();
    }

    connect();

    return () => {
      alive = false;
      if (retryTimer) clearTimeout(retryTimer);
      wsRef.current?.close();
      wsRef.current = null;
      setWsConn(false);
    };
  }, [user?.id, access_token, addLog, bumpStat]);

  // Derived counts
  const active = nodes.filter((n) => connStatus(n.last_updated) === "active").length;
  const stale  = nodes.filter((n) => connStatus(n.last_updated) === "stale").length;
  const lost   = nodes.filter((n) => connStatus(n.last_updated) === "lost").length;

  const visible = nodes.filter((n) => filter === "all" || connStatus(n.last_updated) === filter);

  const msgsLastMin = Object.values(stats).filter(
    (s) => Date.now() - s.lastMsgAt < 60_000,
  ).reduce((sum, s) => sum + s.msgCount, 0);

  return (
    <div style={{
      minHeight: "100vh",
      background: "#030712",
      color: "#e5e7eb",
      fontFamily: "'Inter', sans-serif",
      display: "flex",
      flexDirection: "column",
    }}>

      {/* ── Header ── */}
      <div style={{
        padding: "16px 24px",
        borderBottom: "1px solid #0f1f0f",
        background: "#020702",
        display: "flex",
        alignItems: "center",
        gap: 16,
        flexShrink: 0,
      }}>
        <div style={{ flex: 1 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 2 }}>
            <div style={{
              width: 8, height: 8, borderRadius: "50%",
              background: active > 0 ? "#22c55e" : "#374151",
              boxShadow: active > 0 ? "0 0 6px #22c55e" : "none",
            }} />
            <h1 style={{
              margin: 0, color: "#22c55e",
              fontSize: 15, fontWeight: 800,
              fontFamily: "monospace", letterSpacing: 3,
            }}>
              MESH NETWORK MONITOR
            </h1>
          </div>
          <p style={{ margin: 0, color: "#374151", fontSize: 11, letterSpacing: 1 }}>
            Real-time node status · data stream · link health
          </p>
        </div>

        <WsDot connected={wsConn} />

        {lastPoll && (
          <span style={{ color: "#1f2937", fontSize: 9, fontFamily: "monospace" }}>
            POLLED {lastPoll.toLocaleTimeString("en-GB", { hour12: false })}
          </span>
        )}
      </div>

      {/* ── Stats bar ── */}
      <div style={{
        padding: "12px 24px",
        borderBottom: "1px solid #0f1f0f",
        background: "#020a02",
        display: "flex",
        alignItems: "center",
        gap: 10,
        flexWrap: "wrap",
      }}>
        <StatBox label="TOTAL"   value={nodes.length} color="#6b7280" />
        <StatBox label="ACTIVE"  value={active}        color="#22c55e" />
        <StatBox label="STALE"   value={stale}         color="#f59e0b" />
        <StatBox label="LOST"    value={lost}          color="#ef4444" />
        <StatBox label="PKT/MIN" value={msgsLastMin}   color="#38bdf8" />

        <div style={{ flex: 1 }} />

        {/* Filter tabs */}
        {(["all", "active", "stale", "lost"] as const).map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            style={{
              padding: "5px 12px",
              borderRadius: 6,
              border: `1px solid ${filter === f ? "#16a34a" : "#1f2937"}`,
              background: filter === f ? "#052e16" : "transparent",
              color: filter === f ? "#22c55e" : "#4b5563",
              cursor: "pointer",
              fontSize: 10,
              letterSpacing: 1,
              fontFamily: "monospace",
              textTransform: "uppercase",
            }}
          >
            {f === "all" ? `ALL (${nodes.length})` : f === "active" ? `ACTIVE (${active})` : f === "stale" ? `STALE (${stale})` : `LOST (${lost})`}
          </button>
        ))}
      </div>

      {/* ── Body ── */}
      <div style={{
        flex: 1,
        display: "grid",
        gridTemplateColumns: "1fr 320px",
        gridTemplateRows: "1fr",
        overflow: "hidden",
      }}>

        {/* Node grid */}
        <div style={{ overflowY: "auto", padding: 20 }}>
          {visible.length === 0 ? (
            <div style={{
              display: "flex", flexDirection: "column", alignItems: "center",
              justifyContent: "center", height: "100%",
              gap: 12, opacity: 0.4,
            }}>
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#22c55e" strokeWidth="1.2">
                <circle cx="12" cy="5" r="2" />
                <circle cx="5"  cy="19" r="2" />
                <circle cx="19" cy="19" r="2" />
                <line x1="12" y1="7" x2="5"  y2="17" />
                <line x1="12" y1="7" x2="19" y2="17" />
              </svg>
              <span style={{ color: "#22c55e", fontSize: 12, fontFamily: "monospace", letterSpacing: 2 }}>
                {nodes.length === 0 ? "NO NODES DETECTED" : "NO NODES MATCH FILTER"}
              </span>
              <span style={{ color: "#374151", fontSize: 10 }}>
                {nodes.length === 0
                  ? "Waiting for field devices to connect…"
                  : `${nodes.length} node(s) hidden by filter`}
              </span>
            </div>
          ) : (
            <div style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fill, minmax(230px, 1fr))",
              gap: 12,
            }}>
              {visible.map((loc) => (
                <NodeCard
                  key={loc.user_id}
                  loc={loc}
                  stat={stats[loc.user_id]}
                  wsLive={wsConn}
                />
              ))}
            </div>
          )}
        </div>

        {/* Event log panel */}
        <div style={{
          borderLeft: "1px solid #0f1f0f",
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
          background: "#020802",
        }}>
          <div style={{
            padding: "10px 14px",
            borderBottom: "1px solid #0f1f0f",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
          }}>
            <span style={{ color: "#166534", fontSize: 9, fontFamily: "monospace", letterSpacing: 2 }}>
              DATA STREAM
            </span>
            <span style={{ color: "#1f2937", fontSize: 9, fontFamily: "monospace" }}>
              {log.length} events
            </span>
          </div>

          <div style={{ flex: 1, overflowY: "auto", padding: "8px 0" }}>
            {log.length === 0 ? (
              <div style={{ textAlign: "center", padding: "32px 16px", color: "#1f2937", fontSize: 11 }}>
                Awaiting data…
              </div>
            ) : log.map((e) => (
              <div
                key={e.id}
                style={{
                  padding: "4px 14px",
                  borderBottom: "1px solid #0a120a",
                  display: "flex",
                  gap: 8,
                  alignItems: "flex-start",
                }}
              >
                <span style={{ color: "#1f3d1f", fontSize: 9, fontFamily: "monospace", flexShrink: 0, paddingTop: 1 }}>
                  {e.ts}
                </span>
                <div style={{ minWidth: 0 }}>
                  <div style={{ display: "flex", gap: 5, alignItems: "center", marginBottom: 1 }}>
                    <span style={{
                      color: e.type === "LOC" ? "#22c55e" : e.type === "WS" ? "#60a5fa" : "#f59e0b",
                      fontSize: 8, fontFamily: "monospace", letterSpacing: 0.8,
                      background: e.type === "LOC" ? "#052e16" : e.type === "WS" ? "#0c1a2e" : "#2d1a00",
                      padding: "0px 4px", borderRadius: 2,
                    }}>
                      {e.type}
                    </span>
                    <span style={{ color: "#9ca3af", fontSize: 10, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {e.name}
                    </span>
                  </div>
                  <span style={{ color: "#374151", fontSize: 9, fontFamily: "monospace", wordBreak: "break-all" }}>
                    {e.detail}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Pulse animation */}
      <style>{`
        @keyframes pulse-dot {
          0%, 100% { opacity: 1; }
          50%       { opacity: 0.4; }
        }
      `}</style>
    </div>
  );
}
