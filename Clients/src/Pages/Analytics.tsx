import { useState, useEffect, useCallback } from "react";
import api from "../services/api";

interface Stats { total_users: number; active_users: number; total_missions: number; active_missions: number; total_teams: number; total_evidence: number; total_messages: number; total_sos: number; }

interface MissionByStatus { status: string; count: number; }

function StatCard({ label, value, icon, color }: { label: string; value: number | string; icon: string; color: string }) {
  return (
    <div className="rounded-xl p-5" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
      <div className="flex items-start justify-between">
        <div>
          <p className="text-gray-500 text-xs uppercase tracking-widest mb-1">{label}</p>
          <p className="text-white text-3xl font-black">{value}</p>
        </div>
        <span className="text-3xl">{icon}</span>
      </div>
      <div className="mt-3 h-1 rounded-full" style={{ background: `${color}30` }}>
        <div className="h-1 rounded-full" style={{ background: color, width: "100%" }} />
      </div>
    </div>
  );
}

function HBar({ label, value, max, color }: { label: string; value: number; max: number; color: string }) {
  const pct = max > 0 ? (value / max) * 100 : 0;
  return (
    <div className="flex items-center gap-3 py-1.5">
      <span className="text-gray-400 text-xs w-24 shrink-0 capitalize">{label}</span>
      <div className="flex-1 h-2 rounded-full" style={{ background: "#0a140a" }}>
        <div className="h-2 rounded-full transition-all" style={{ background: color, width: `${pct}%` }} />
      </div>
      <span className="text-white text-xs font-semibold w-6 text-right">{value}</span>
    </div>
  );
}

const STATUS_COLORS: Record<string, string> = {
  active: "#22c55e", planned: "#22c55e", draft: "#6b7280", completed: "#8b5cf6", suspended: "#f59e0b", archived: "#374151",
};

export default function AnalyticsPage() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [missionsByStatus, setMissionsByStatus] = useState<MissionByStatus[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [statsRes, missionsRes] = await Promise.allSettled([
        api.get("/admin/stats"),
        api.get("/missions"),
      ]);

      if (statsRes.status === "fulfilled") setStats(statsRes.value.data);

      if (missionsRes.status === "fulfilled") {
        const missions = missionsRes.value.data as { status: string }[];
        const counts: Record<string, number> = {};
        missions.forEach((m) => { counts[m.status] = (counts[m.status] ?? 0) + 1; });
        setMissionsByStatus(Object.entries(counts).map(([status, count]) => ({ status, count })));
      }
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  if (loading) return <div className="p-6 text-center text-gray-500">Loading analytics…</div>;

  const maxMission = Math.max(...missionsByStatus.map((m) => m.count), 1);

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-white font-bold text-xl">Analytics</h1>
          <p className="text-gray-500 text-sm mt-0.5">Platform-wide activity overview</p>
        </div>
        <button onClick={load} className="px-4 py-2 rounded-lg text-sm font-semibold text-white hover:opacity-90" style={{ background: "#0a140a" }}>
          Refresh
        </button>
      </div>

      {/* Stat cards */}
      {stats && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <StatCard label="Total Users" value={stats.total_users} icon="👤" color="#16a34a" />
          <StatCard label="Active Now" value={stats.active_users} icon="🟢" color="#22c55e" />
          <StatCard label="Missions" value={stats.total_missions} icon="📋" color="#f59e0b" />
          <StatCard label="Active Missions" value={stats.active_missions} icon="🎯" color="#ef4444" />
          <StatCard label="Teams" value={stats.total_teams} icon="👥" color="#6366f1" />
          <StatCard label="Evidence Items" value={stats.total_evidence} icon="📁" color="#0891b2" />
          <StatCard label="Messages" value={stats.total_messages} icon="💬" color="#8b5cf6" />
          <StatCard label="SOS Events" value={stats.total_sos ?? 0} icon="🆘" color="#dc2626" />
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Missions by status */}
        <div className="rounded-xl p-5" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
          <h2 className="text-white font-semibold text-sm mb-4">Missions by Status</h2>
          {missionsByStatus.length === 0 ? (
            <p className="text-gray-500 text-sm">No missions yet</p>
          ) : (
            <div className="space-y-1">
              {missionsByStatus.sort((a, b) => b.count - a.count).map((m) => (
                <HBar key={m.status} label={m.status} value={m.count} max={maxMission}
                  color={STATUS_COLORS[m.status] ?? "#6b7280"} />
              ))}
            </div>
          )}
        </div>

        {/* Activity feed */}
        <div className="rounded-xl p-5" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
          <h2 className="text-white font-semibold text-sm mb-4">Platform Summary</h2>
          {stats ? (
            <div className="space-y-3">
              {[
                { label: "Deployment capacity", value: stats.total_users > 0 ? `${Math.round((stats.active_users / stats.total_users) * 100)}% online` : "0%", color: "#22c55e" },
                { label: "Mission utilisation", value: stats.total_missions > 0 ? `${Math.round((stats.active_missions / stats.total_missions) * 100)}% active` : "—", color: "#f59e0b" },
                { label: "Evidence density", value: stats.total_missions > 0 ? `${(stats.total_evidence / Math.max(stats.total_missions, 1)).toFixed(1)} items/mission` : "—", color: "#0891b2" },
                { label: "Comms activity", value: `${stats.total_messages} messages`, color: "#8b5cf6" },
                { label: "Alert status", value: (stats.total_sos ?? 0) > 0 ? `${stats.total_sos} SOS recorded` : "All clear", color: (stats.total_sos ?? 0) > 0 ? "#ef4444" : "#22c55e" },
              ].map((row) => (
                <div key={row.label} className="flex items-center justify-between py-2" style={{ borderBottom: "1px solid #040804" }}>
                  <span className="text-gray-400 text-sm">{row.label}</span>
                  <span className="text-sm font-semibold" style={{ color: row.color }}>{row.value}</span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-gray-500 text-sm">Stats unavailable (coordinator access required)</p>
          )}
        </div>
      </div>
    </div>
  );
}
