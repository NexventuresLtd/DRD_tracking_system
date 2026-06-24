import { useState, useEffect, useCallback } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { MapContainer, TileLayer, Marker, Popup } from "react-leaflet";
import L from "leaflet";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";

delete (L.Icon.Default.prototype as unknown as Record<string, unknown>)._getIconUrl;
L.Icon.Default.mergeOptions({ iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png", shadowUrl: "" });

const ROLE_LABELS: Record<string, string> = {
  operations_coordinator: "Coord",
  planning_officer: "Planner",
  team_leader: "Leader",
  field_user: "Field",
};
const ROLE_COLORS: Record<string, string> = {
  operations_coordinator: "#dc2626",
  planning_officer: "#f59e0b",
  team_leader: "#16a34a",
  field_user: "#22c55e",
};

function memberIcon(color: string) {
  return L.divIcon({
    className: "",
    html: `<div style="width:14px;height:14px;background:${color};border:2px solid #fff;border-radius:50%;box-shadow:0 0 6px ${color}88"></div>`,
    iconSize: [14, 14], iconAnchor: [7, 7],
  });
}

interface UserInfo { id: string; full_name?: string; email?: string; role?: string; username?: string; }
interface TeamMember { id: string; user_id: string; team_id: string; role_in_team: string; joined_at: string; user?: UserInfo; }
interface TeamInfo { id: string; name: string; description?: string; leader_id?: string; }
interface LiveLoc { user_id: string; latitude: number; longitude: number; status: string; }

function memberName(m: TeamMember) { return m.user?.full_name ?? m.user?.username ?? "Unknown"; }
function memberRole(m: TeamMember) { return m.user?.role ?? m.role_in_team ?? "member"; }
function memberEmail(m: TeamMember) { return m.user?.email ?? ""; }

export default function TeamDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user: me } = useAuthStore();
  const [team, setTeam] = useState<TeamInfo | null>(null);
  const [members, setMembers] = useState<TeamMember[]>([]);
  const [locations, setLocations] = useState<LiveLoc[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    if (!id) return;
    try {
      const [teamRes, membersRes, locsRes] = await Promise.allSettled([
        api.get(`/teams/${id}`),
        api.get(`/teams/${id}/members`),
        api.get(`/teams/${id}/locations`),
      ]);
      if (teamRes.status === "fulfilled") setTeam(teamRes.value.data);
      if (membersRes.status === "fulfilled") setMembers(membersRes.value.data);
      if (locsRes.status === "fulfilled") setLocations(locsRes.value.data);
    } catch { /**/ } finally { setLoading(false); }
  }, [id]);

  useEffect(() => { load(); }, [load]);

  const removeMember = async (uid: string) => {
    if (!confirm("Remove this member?")) return;
    try { await api.delete(`/teams/${id}/members/${uid}`); setMembers((prev) => prev.filter((m) => m.user_id !== uid)); } catch { /**/ }
  };

  const canManage = me && ["operations_coordinator", "planning_officer"].includes(me.role);

  if (loading) return <div className="p-6 text-center text-gray-500">Loading team…</div>;
  if (!team) return <div className="p-6 text-center text-gray-500">Team not found</div>;

  const hasLocs = locations.length > 0;
  const mapCenter: [number, number] = hasLocs
    ? [locations.reduce((s, l) => s + l.latitude, 0) / locations.length,
       locations.reduce((s, l) => s + l.longitude, 0) / locations.length]
    : [-1.9441, 30.0619];

  return (
    <div className="p-6 max-w-6xl mx-auto">
      {/* Back */}
      <button onClick={() => navigate("/teams")} className="text-green-400 text-sm hover:text-green-300 mb-4 flex items-center gap-1">
        ← Back to Teams
      </button>

      {/* Header */}
      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-white font-bold text-2xl">{team.name}</h1>
          {team.description && <p className="text-gray-400 text-sm mt-1">{team.description}</p>}
          <p className="text-gray-500 text-xs mt-1">{members.length} members · {locations.length} online</p>
        </div>
        {canManage && (
          <button className="px-4 py-2 rounded-lg text-sm font-semibold text-white hover:opacity-90" style={{ background: "#16a34a" }}>
            Edit Team
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Members */}
        <div className="rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
          <div className="px-5 py-4" style={{ borderBottom: "1px solid #0a140a" }}>
            <h2 className="text-white font-semibold text-sm">Members ({members.length})</h2>
          </div>
          <div className="divide-y" style={{ borderColor: "#040804" }}>
            {members.length === 0 ? (
              <p className="p-4 text-center text-gray-500 text-sm">No members</p>
            ) : (
              members.map((m) => {
                const role = memberRole(m);
                const color = ROLE_COLORS[role] ?? "#6b7280";
                const isLeader = m.user_id === team.leader_id;
                const loc = locations.find((l) => l.user_id === m.user_id);
                const name = memberName(m);
                return (
                  <div key={m.id} className="px-5 py-3 flex items-center gap-3">
                    <div className="w-9 h-9 rounded-full flex items-center justify-center font-bold text-sm shrink-0"
                      style={{ background: `${color}20`, color, border: `1px solid ${color}40` }}>
                      {(name).charAt(0).toUpperCase()}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="text-white text-sm font-medium truncate">{name}</p>
                        {isLeader && <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: "#16653430", color: "#4ade80" }}>Leader</span>}
                      </div>
                      <p className="text-gray-500 text-xs truncate">{memberEmail(m)}</p>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: `${color}15`, color }}>
                        {ROLE_LABELS[role] ?? role}
                      </span>
                      {loc && <span className="w-2 h-2 rounded-full" style={{ background: "#22c55e" }} title="Online" />}
                      {canManage && m.user_id !== me?.id && (
                        <button onClick={() => removeMember(m.user_id)} className="text-gray-600 hover:text-red-400 text-xs">✕</button>
                      )}
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* Live Map */}
        <div className="rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
          <div className="px-5 py-4" style={{ borderBottom: "1px solid #0a140a" }}>
            <h2 className="text-white font-semibold text-sm">Live Positions ({locations.length} online)</h2>
          </div>
          <div style={{ height: 360 }}>
            <MapContainer center={mapCenter} zoom={13} style={{ height: "100%", width: "100%" }}>
              <TileLayer
                url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
                subdomains={["a", "b", "c"]}
              />
              {locations.map((loc) => {
                const member = members.find((m) => m.user_id === loc.user_id);
                const role = memberRole(member ?? { id: "", user_id: loc.user_id, team_id: "", role_in_team: "field_user", joined_at: "" });
                const color = ROLE_COLORS[role] ?? "#22c55e";
                return (
                  <Marker key={loc.user_id} position={[loc.latitude, loc.longitude]} icon={memberIcon(color)}>
                    <Popup>
                      <div style={{ color: "#fff", background: "#060d06", padding: "4px 8px", borderRadius: 6 }}>
                        <strong>{member ? memberName(member) : "Unknown"}</strong>
                        <br /><span style={{ color: "#9ca3af", fontSize: 11 }}>{loc.status}</span>
                      </div>
                    </Popup>
                  </Marker>
                );
              })}
            </MapContainer>
          </div>
        </div>
      </div>
    </div>
  );
}
