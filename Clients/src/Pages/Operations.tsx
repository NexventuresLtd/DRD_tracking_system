import { useEffect, useState } from "react";
import { missionApi, locationApi, teamApi } from "../services/api";
import type { Mission, LiveLocation, Team } from "../types";
import { MdPeople, MdLocationOn, MdAssignment, MdFiberManualRecord } from "react-icons/md";

const STATUS_COLORS: Record<string, string> = {
  active:  "text-green-400",
  stale:   "text-yellow-400",
  offline: "text-gray-500",
};

export default function Operations() {
  const [missions, setMissions] = useState<Mission[]>([]);
  const [locations, setLocations] = useState<LiveLocation[]>([]);
  const [teams, setTeams] = useState<Team[]>([]);

  useEffect(() => {
    missionApi.list({ status: "active" }).then(({ data }) => setMissions(data)).catch(() => {});
    locationApi.getLive().then(({ data }) => setLocations(data)).catch(() => {});
    teamApi.list().then(({ data }) => setTeams(data)).catch(() => {});
    const interval = setInterval(() => {
      locationApi.getLive().then(({ data }) => setLocations(data)).catch(() => {});
    }, 15000);
    return () => clearInterval(interval);
  }, []);

  const online = locations.filter((l) => l.status === "active").length;
  const stale = locations.filter((l) => l.status === "stale").length;
  const offline = locations.filter((l) => l.status === "offline").length;

  return (
    <div className="p-6 space-y-6">
      <div>
        <h2 className="text-white text-xl font-bold">Operations Board</h2>
        <p className="text-gray-400 text-sm">Live situational overview</p>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { label: "Active Missions", value: missions.length, icon: <MdAssignment size={22} />, color: "text-green-400", bg: "bg-green-900/30" },
          { label: "Online Now", value: online, icon: <MdLocationOn size={22} />, color: "text-emerald-400", bg: "bg-emerald-900/30" },
          { label: "Stale Signals", value: stale, icon: <MdFiberManualRecord size={22} />, color: "text-yellow-400", bg: "bg-yellow-900/30" },
          { label: "Active Teams", value: teams.length, icon: <MdPeople size={22} />, color: "text-green-400", bg: "bg-blue-900/30" },
        ].map((card) => (
          <div key={card.label} className="bg-gray-900 border border-gray-800 rounded-xl p-5">
            <div className={`w-10 h-10 rounded-lg ${card.bg} flex items-center justify-center ${card.color} mb-3`}>
              {card.icon}
            </div>
            <p className="text-2xl font-bold text-white">{card.value}</p>
            <p className="text-gray-400 text-sm mt-1">{card.label}</p>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
          <h3 className="text-white font-semibold mb-4">Active Missions</h3>
          {missions.length === 0 ? (
            <p className="text-gray-500 text-sm text-center py-6">No active missions</p>
          ) : (
            <div className="space-y-2">
              {missions.map((m) => (
                <div key={m.id} className="flex items-center justify-between py-2 border-b border-gray-800 last:border-0">
                  <div>
                    <p className="text-white text-sm font-medium">{m.name}</p>
                    <p className="text-gray-500 text-xs">{m.area_of_operations || "—"}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-gray-400 text-xs">{m.objectives.filter((o) => o.is_completed).length}/{m.objectives.length} obj.</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
          <h3 className="text-white font-semibold mb-4">Field Personnel</h3>
          {locations.length === 0 ? (
            <p className="text-gray-500 text-sm text-center py-6">No active trackers</p>
          ) : (
            <div className="space-y-2 max-h-64 overflow-y-auto">
              {locations.map((loc) => (
                <div key={loc.user_id} className="flex items-center gap-3 py-2 border-b border-gray-800 last:border-0">
                  <MdFiberManualRecord className={STATUS_COLORS[loc.status]} size={10} />
                  <div className="flex-1 min-w-0">
                    <p className="text-white text-sm truncate">
                      {loc.user?.full_name || loc.user_id.substring(0, 12) + "..."}
                    </p>
                    <p className="text-gray-500 text-xs">
                      {loc.latitude.toFixed(4)}, {loc.longitude.toFixed(4)}
                    </p>
                  </div>
                  <span className={`text-xs capitalize ${STATUS_COLORS[loc.status]}`}>{loc.status}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
          <h3 className="text-white font-semibold mb-4">Teams Overview</h3>
          {teams.length === 0 ? (
            <p className="text-gray-500 text-sm text-center py-6">No teams</p>
          ) : (
            <div className="space-y-2">
              {teams.map((team) => (
                <div key={team.id} className="flex items-center gap-3 py-2 border-b border-gray-800 last:border-0">
                  <div className="w-8 h-8 rounded-lg flex items-center justify-center text-white text-xs font-bold shrink-0" style={{ background: team.color }}>
                    {team.name.charAt(0)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-white text-sm truncate">{team.name}</p>
                    <p className="text-gray-500 text-xs">{team.member_count ?? 0} members</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
          <h3 className="text-white font-semibold mb-4">Signal Health</h3>
          <div className="space-y-3">
            {[
              { label: "Online", count: online, color: "bg-green-500", total: locations.length },
              { label: "Stale (>5min)", count: stale, color: "bg-yellow-500", total: locations.length },
              { label: "Offline (>15min)", count: offline, color: "bg-gray-600", total: locations.length },
            ].map(({ label, count, color, total }) => {
              const pct = total ? Math.round((count / total) * 100) : 0;
              return (
                <div key={label}>
                  <div className="flex justify-between text-sm mb-1">
                    <span className="text-gray-300">{label}</span>
                    <span className="text-gray-400">{count}</span>
                  </div>
                  <div className="h-2 bg-gray-800 rounded-full">
                    <div className={`h-2 ${color} rounded-full transition-all`} style={{ width: `${pct}%` }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
