import { useState, useEffect, useCallback, useRef } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { MapContainer, TileLayer, Marker, Popup } from "react-leaflet";
import L from "leaflet";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";
import { MdPersonAdd, MdStar, MdStarBorder, MdShare, MdDelete, MdEdit, MdCheck, MdClose } from "react-icons/md";

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
const TEAM_ROLES = ["member", "leader", "medic", "intel", "logistics", "comms"];

function memberIcon(color: string) {
  return L.divIcon({
    className: "",
    html: `<div style="width:14px;height:14px;background:${color};border:2px solid #fff;border-radius:50%;box-shadow:0 0 6px ${color}88"></div>`,
    iconSize: [14, 14], iconAnchor: [7, 7],
  });
}

interface UserInfo { id: string; full_name?: string; email?: string; role?: string; username?: string; }
interface TeamMember { id: string; user_id: string; team_id: string; role_in_team: string; joined_at: string; user?: UserInfo; }
interface TeamInfo { id: string; name: string; description?: string; leader_id?: string; location_sharing?: boolean; }
interface LiveLoc { user_id: string; latitude: number; longitude: number; status: string; }

function memberName(m: TeamMember) { return m.user?.full_name ?? m.user?.username ?? "Unknown"; }
function memberRole(m: TeamMember) { return m.user?.role ?? m.role_in_team ?? "member"; }
function memberEmail(m: TeamMember) { return m.user?.email ?? ""; }

// ── Add Member Modal ──────────────────────────────────────────────────────────
function AddMemberModal({ teamId, existingIds, onClose, onAdded }: {
  teamId: string; existingIds: Set<string>; onClose: () => void; onAdded: () => void;
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<UserInfo[]>([]);
  const [loading, setLoading] = useState(false);
  const [adding, setAdding] = useState<string | null>(null);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!query.trim()) { setResults([]); return; }
    if (debounce.current) clearTimeout(debounce.current);
    debounce.current = setTimeout(async () => {
      setLoading(true);
      try {
        const res = await api.get(`/users?search=${encodeURIComponent(query)}&page_size=10&role=field_user`);
        const all: UserInfo[] = Array.isArray(res.data) ? res.data : (res.data.users ?? []);
        setResults(all.filter((u) => !existingIds.has(u.id)));
      } catch { setResults([]); }
      setLoading(false);
    }, 300);
  }, [query, existingIds]);

  const add = async (user: UserInfo) => {
    setAdding(user.id);
    try {
      await api.post(`/teams/${teamId}/members`, { user_id: user.id, role_in_team: "member" });
      onAdded();
      setResults((prev) => prev.filter((u) => u.id !== user.id));
    } catch { /**/ }
    setAdding(null);
  };

  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 999, background: "rgba(0,0,0,0.7)", display: "flex", alignItems: "center", justifyContent: "center" }} onClick={onClose}>
      <div style={{ background: "#0a100a", border: "1px solid #14532d", borderRadius: 14, width: 420, maxHeight: "80vh", display: "flex", flexDirection: "column" }} onClick={(e) => e.stopPropagation()}>
        <div style={{ padding: "16px 20px", borderBottom: "1px solid #14532d", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ color: "#fff", fontWeight: 600 }}>Add Members to Team</span>
          <button onClick={onClose} style={{ background: "none", border: "none", color: "#6b7280", cursor: "pointer", fontSize: 18 }}>✕</button>
        </div>
        <div style={{ padding: 16 }}>
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search by name, email or username…"
            style={{ width: "100%", background: "#111827", border: "1px solid #374151", borderRadius: 8, padding: "10px 12px", color: "#fff", fontSize: 13, boxSizing: "border-box" }}
          />
        </div>
        <div style={{ flex: 1, overflowY: "auto", padding: "0 16px 16px" }}>
          {loading && <p style={{ color: "#6b7280", fontSize: 12, textAlign: "center" }}>Searching…</p>}
          {!loading && query && results.length === 0 && <p style={{ color: "#6b7280", fontSize: 12, textAlign: "center" }}>No users found</p>}
          {results.map((u) => (
            <div key={u.id} style={{ display: "flex", alignItems: "center", gap: 12, padding: "10px 12px", marginBottom: 6, background: "#0f1a0f", border: "1px solid #1f2937", borderRadius: 10 }}>
              <div style={{ width: 34, height: 34, borderRadius: "50%", background: "#1f2937", display: "flex", alignItems: "center", justifyContent: "center", color: "#fff", fontWeight: 700, fontSize: 14, flexShrink: 0 }}>
                {(u.full_name ?? u.username ?? "?")[0].toUpperCase()}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <p style={{ color: "#fff", fontSize: 13, fontWeight: 500, margin: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{u.full_name ?? u.username}</p>
                <p style={{ color: "#6b7280", fontSize: 11, margin: 0 }}>{u.email} · {ROLE_LABELS[u.role ?? ""] ?? u.role}</p>
              </div>
              <button
                onClick={() => add(u)}
                disabled={adding === u.id}
                style={{ padding: "5px 14px", background: "#16a34a", border: "none", borderRadius: 7, color: "#fff", fontSize: 12, fontWeight: 600, cursor: "pointer", flexShrink: 0 }}
              >
                {adding === u.id ? "…" : "Add"}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ── Inline role editor ────────────────────────────────────────────────────────
function RoleEditor({ teamId, member, onUpdated }: { teamId: string; member: TeamMember; onUpdated: (m: TeamMember) => void }) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState(member.role_in_team);
  const [saving, setSaving] = useState(false);

  const save = async () => {
    if (value === member.role_in_team) { setEditing(false); return; }
    setSaving(true);
    try {
      const res = await api.patch(`/teams/${teamId}/members/${member.user_id}`, { role_in_team: value });
      onUpdated({ ...member, role_in_team: res.data.role_in_team ?? value });
      setEditing(false);
    } catch { /**/ }
    setSaving(false);
  };

  if (!editing) {
    return (
      <button onClick={() => setEditing(true)} title="Change team role" style={{ background: "none", border: "none", cursor: "pointer", color: "#6b7280", padding: 2 }}>
        <MdEdit size={13} />
      </button>
    );
  }

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
      <select
        value={value}
        onChange={(e) => setValue(e.target.value)}
        style={{ background: "#111827", border: "1px solid #374151", borderRadius: 4, color: "#fff", fontSize: 11, padding: "2px 4px" }}
      >
        {TEAM_ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
      </select>
      <button onClick={save} disabled={saving} style={{ background: "none", border: "none", cursor: "pointer", color: "#4ade80", padding: 2 }}>
        <MdCheck size={13} />
      </button>
      <button onClick={() => { setValue(member.role_in_team); setEditing(false); }} style={{ background: "none", border: "none", cursor: "pointer", color: "#ef4444", padding: 2 }}>
        <MdClose size={13} />
      </button>
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────────
export default function TeamDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user: me } = useAuthStore();
  const [team, setTeam] = useState<TeamInfo | null>(null);
  const [members, setMembers] = useState<TeamMember[]>([]);
  const [locations, setLocations] = useState<LiveLoc[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  const [settingLeader, setSettingLeader] = useState<string | null>(null);
  const [togglingShare, setTogglingShare] = useState(false);

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
    if (!confirm("Remove this member from the team?")) return;
    try {
      await api.delete(`/teams/${id}/members/${uid}`);
      setMembers((prev) => prev.filter((m) => m.user_id !== uid));
    } catch { /**/ }
  };

  const setLeader = async (uid: string) => {
    setSettingLeader(uid);
    try {
      await api.put(`/teams/${id}`, { leader_id: uid });
      setTeam((prev) => prev ? { ...prev, leader_id: uid } : prev);
    } catch { /**/ }
    setSettingLeader(null);
  };

  const toggleLocationSharing = async () => {
    if (!team) return;
    setTogglingShare(true);
    try {
      const res = await api.patch(`/teams/${id}/location-sharing`, { enabled: !team.location_sharing });
      setTeam((prev) => prev ? { ...prev, location_sharing: res.data.location_sharing } : prev);
    } catch { /**/ }
    setTogglingShare(false);
  };

  const updateMember = (updated: TeamMember) => {
    setMembers((prev) => prev.map((m) => m.id === updated.id ? updated : m));
  };

  const isCoordinator = me && ["operations_coordinator", "planning_officer"].includes(me.role);
  // Team leaders can manage their own team
  const isOwnTeamLeader = me?.role === "team_leader" && team?.leader_id === me?.id;
  const canManage = isCoordinator || isOwnTeamLeader;

  if (loading) return <div className="p-6 text-center text-gray-500">Loading team…</div>;
  if (!team) return <div className="p-6 text-center text-gray-500">Team not found</div>;

  const hasLocs = locations.length > 0;
  const mapCenter: [number, number] = hasLocs
    ? [locations.reduce((s, l) => s + l.latitude, 0) / locations.length,
       locations.reduce((s, l) => s + l.longitude, 0) / locations.length]
    : [-1.9441, 30.0619];

  const existingIds = new Set(members.map((m) => m.user_id));

  return (
    <div className="p-6 max-w-6xl mx-auto">
      {showAddModal && (
        <AddMemberModal
          teamId={id!}
          existingIds={existingIds}
          onClose={() => setShowAddModal(false)}
          onAdded={() => { load(); }}
        />
      )}

      <button onClick={() => navigate("/teams")} className="text-green-400 text-sm hover:text-green-300 mb-4 flex items-center gap-1">
        ← Back to Teams
      </button>

      {/* Header */}
      <div className="flex items-start justify-between mb-6 flex-wrap gap-3">
        <div>
          <h1 className="text-white font-bold text-2xl">{team.name}</h1>
          {team.description && <p className="text-gray-400 text-sm mt-1">{team.description}</p>}
          <p className="text-gray-500 text-xs mt-1">{members.length} members · {locations.length} live</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          {/* Location sharing toggle — coordinator only */}
          {isCoordinator && (
            <button
              onClick={toggleLocationSharing}
              disabled={togglingShare}
              style={{
                display: "flex", alignItems: "center", gap: 6,
                padding: "7px 14px", borderRadius: 8, fontSize: 12, fontWeight: 600, cursor: "pointer",
                background: team.location_sharing ? "#14532d" : "#1f2937",
                border: `1px solid ${team.location_sharing ? "#16a34a" : "#374151"}`,
                color: team.location_sharing ? "#4ade80" : "#6b7280",
              }}
            >
              <MdShare size={14} />
              {team.location_sharing ? "Sharing ON" : "Sharing OFF"}
            </button>
          )}
          {/* Add member */}
          {canManage && (
            <button
              onClick={() => setShowAddModal(true)}
              style={{ display: "flex", alignItems: "center", gap: 6, padding: "7px 14px", background: "#16a34a", border: "none", borderRadius: 8, color: "#fff", fontSize: 12, fontWeight: 600, cursor: "pointer" }}
            >
              <MdPersonAdd size={15} /> Add Member
            </button>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Members */}
        <div className="rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
          <div className="px-5 py-4" style={{ borderBottom: "1px solid #0a140a" }}>
            <h2 className="text-white font-semibold text-sm">Members ({members.length})</h2>
          </div>
          <div className="divide-y" style={{ borderColor: "#040804" }}>
            {members.length === 0 ? (
              <p className="p-4 text-center text-gray-500 text-sm">No members — use "Add Member" to add users</p>
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
                      {name.charAt(0).toUpperCase()}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="text-white text-sm font-medium truncate">{name}</p>
                        {isLeader && (
                          <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: "#16653430", color: "#4ade80" }}>Leader</span>
                        )}
                      </div>
                      <p className="text-gray-500 text-xs truncate">{memberEmail(m)}</p>
                    </div>
                    <div className="flex items-center gap-1.5 shrink-0">
                      <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: `${color}15`, color }}>
                        {ROLE_LABELS[role] ?? role}
                      </span>
                      {/* In-team role badge */}
                      <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: "#1f293780", color: "#9ca3af" }}>
                        {m.role_in_team}
                      </span>
                      {loc && <span className="w-2 h-2 rounded-full bg-green-400" title="Online" />}
                      {/* Role editor */}
                      {canManage && m.user_id !== me?.id && (
                        <RoleEditor teamId={id!} member={m} onUpdated={updateMember} />
                      )}
                      {/* Set as team leader — coordinator only */}
                      {isCoordinator && !isLeader && m.user_id !== me?.id && (
                        <button
                          onClick={() => setLeader(m.user_id)}
                          disabled={settingLeader === m.user_id}
                          title="Set as team leader"
                          style={{ background: "none", border: "none", cursor: "pointer", color: "#6b7280", padding: 2 }}
                        >
                          {settingLeader === m.user_id ? <span style={{ fontSize: 10 }}>…</span> : <MdStarBorder size={15} />}
                        </button>
                      )}
                      {isLeader && <MdStar size={15} color="#f59e0b" title="Team leader" />}
                      {/* Remove */}
                      {canManage && m.user_id !== me?.id && (
                        <button onClick={() => removeMember(m.user_id)} title="Remove from team" style={{ background: "none", border: "none", cursor: "pointer", color: "#4b5563", padding: 2 }}>
                          <MdDelete size={14} />
                        </button>
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
          <div className="px-5 py-4" style={{ borderBottom: "1px solid #0a140a", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <h2 className="text-white font-semibold text-sm">Live Positions ({locations.length} online)</h2>
            {!team.location_sharing && isCoordinator && (
              <span style={{ color: "#f59e0b", fontSize: 11 }}>Location sharing is off</span>
            )}
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
