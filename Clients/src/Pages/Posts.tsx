import { useState, useEffect, useRef, useCallback } from "react";
import { MapContainer, TileLayer, useMapEvents, Marker } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { postsApi, userApi } from "../services/api";
import { useAuthStore } from "../stores/authStore";

// ── Types ─────────────────────────────────────────────────────────────────

const FACILITY_TYPES: Record<string, { label: string; icon: string; color: string }> = {
  forward_operating_base:  { label: "Forward Operating Base",  icon: "⬡", color: "#ef4444" },
  main_operating_base:     { label: "Main Operating Base",     icon: "★", color: "#dc2626" },
  combat_outpost:          { label: "Combat Outpost",          icon: "⬟", color: "#f97316" },
  checkpoint:              { label: "Checkpoint",              icon: "⬢", color: "#eab308" },
  logistics_depot:         { label: "Logistics Depot",         icon: "▣", color: "#84cc16" },
  medical_center:          { label: "Medical Center",          icon: "✚", color: "#22c55e" },
  command_center:          { label: "Command Center",          icon: "◈", color: "#14b8a6" },
  communications_hub:      { label: "Communications Hub",      icon: "◎", color: "#06b6d4" },
  armory:                  { label: "Armory",                  icon: "⚙", color: "#3b82f6" },
  training_facility:       { label: "Training Facility",       icon: "◇", color: "#6366f1" },
  detention_center:        { label: "Detention Center",        icon: "⊡", color: "#8b5cf6" },
  airfield:                { label: "Airfield / Helipad",      icon: "✈", color: "#a855f7" },
  naval_facility:          { label: "Naval Facility",          icon: "⚓", color: "#ec4899" },
  office:                  { label: "Administrative Office",   icon: "▦", color: "#6b7280" },
  border_post:             { label: "Border Post",             icon: "⬛", color: "#78716c" },
  safe_house:              { label: "Safe House",              icon: "⌂", color: "#059669" },
  intelligence_post:       { label: "Intelligence Post",       icon: "◉", color: "#7c3aed" },
  barracks:                { label: "Barracks",                icon: "⊞", color: "#374151" },
  supply_point:            { label: "Supply Point",            icon: "◫", color: "#b45309" },
  other:                   { label: "Other",                   icon: "◌", color: "#4b5563" },
};

const STATUS_COLORS: Record<string, string> = {
  active: "#22c55e",
  inactive: "#6b7280",
  decommissioned: "#ef4444",
  under_construction: "#f59e0b",
};

const CLASSIFICATIONS = ["unclassified", "restricted", "confidential", "secret"];

const THREAT_COLORS: Record<string, { bg: string; text: string; label: string }> = {
  green: { bg: "#14532d", text: "#22c55e", label: "GREEN — Secure" },
  amber: { bg: "#451a03", text: "#f59e0b", label: "AMBER — Caution" },
  red:   { bg: "#450a0a", text: "#ef4444", label: "RED — Threat Active" },
  black: { bg: "#111827", text: "#9ca3af", label: "BLACK — Compromised" },
};

// Dynamic required / suggested fields per facility type
const TYPE_HINTS: Record<string, string> = {
  medical_center: "Set capacity (patient beds). Contact is the medical officer.",
  armory: "Classification should be Confidential or Secret.",
  airfield: "Capacity = max aircraft slots. Contact = air traffic control.",
  detention_center: "Classification should be at least Restricted.",
  intelligence_post: "Classification should be Secret. Description will be restricted.",
  safe_house: "Visibility should be Planning Only for security.",
  logistics_depot: "Set capacity for tonnage/vehicle count.",
  barracks: "Capacity = number of personnel quarters.",
};

type Post = {
  id: string;
  name: string;
  facility_type: string;
  description?: string;
  mission?: string;
  latitude: number;
  longitude: number;
  address?: string;
  region?: string;
  status: string;
  is_published: boolean;
  visibility: string;
  capacity?: number;
  commander_name?: string;
  commander_user_id?: string;
  contact_info?: string;
  classification: string;
  threat_level: string;
  allowed_team_ids: string[];
  editor_ids?: string[];
  can_edit: boolean;
  created_at: string;
  updated_at: string;
};

const BLANK: Omit<Post, "id" | "can_edit" | "created_at" | "updated_at" | "editor_ids"> = {
  name: "",
  facility_type: "command_center",
  description: "",
  mission: "",
  latitude: 0,
  longitude: 0,
  address: "",
  region: "",
  status: "active",
  is_published: false,
  visibility: "all_personnel",
  capacity: undefined,
  commander_name: "",
  commander_user_id: undefined,
  contact_info: "",
  classification: "restricted",
  threat_level: "green",
  allowed_team_ids: [],
};

// ── Map Picker sub-component ────────────────────────────────────────────────

function MapClickLayer({ onPick }: { onPick: (lat: number, lng: number) => void }) {
  useMapEvents({ click(e) { onPick(e.latlng.lat, e.latlng.lng); } });
  return null;
}

function MapPicker({ lat, lng, onPick, onClose }: { lat: number; lng: number; onPick: (lat: number, lng: number) => void; onClose: () => void }) {
  const [picked, setPicked] = useState<{ lat: number; lng: number } | null>(lat && lng ? { lat, lng } : null);
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.9)", zIndex: 2000, display: "flex", flexDirection: "column" }}>
      <div style={{ padding: "12px 16px", background: "#050d05", borderBottom: "1px solid #0f1f0f", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <span style={{ color: "#22c55e", fontFamily: "'JetBrains Mono', monospace", fontSize: 12, letterSpacing: 2 }}>
          PICK LOCATION — {picked ? `${picked.lat.toFixed(5)}, ${picked.lng.toFixed(5)}` : "Click on map"}
        </span>
        <div style={{ display: "flex", gap: 8 }}>
          <button
            onClick={() => picked && onPick(picked.lat, picked.lng)}
            disabled={!picked}
            style={{ padding: "6px 16px", background: picked ? "#16a34a" : "#1f2d1f", border: "none", color: "#fff", cursor: picked ? "pointer" : "not-allowed", fontSize: 12, fontWeight: 700 }}
          >
            CONFIRM
          </button>
          <button onClick={onClose} style={{ padding: "6px 12px", background: "none", border: "1px solid #374151", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
        </div>
      </div>
      <div style={{ flex: 1 }}>
        <MapContainer
          center={picked ? [picked.lat, picked.lng] : [-1.9441, 30.0619]}
          zoom={10}
          style={{ height: "100%", width: "100%" }}
        >
          <TileLayer url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png" attribution="©CARTO" />
          <MapClickLayer onPick={(lat, lng) => setPicked({ lat, lng })} />
          {picked && (
            <Marker
              position={[picked.lat, picked.lng]}
              icon={L.divIcon({ className: "", html: `<div style="width:12px;height:12px;background:#22c55e;border:2px solid #fff;border-radius:50%;"></div>`, iconSize: [12, 12], iconAnchor: [6, 6] })}
            />
          )}
        </MapContainer>
      </div>
    </div>
  );
}

// ── Sub-components ─────────────────────────────────────────────────────────

function StatusBadge({ value, size = 10 }: { value: string; size?: number }) {
  return (
    <span style={{
      fontSize: size, fontFamily: "'JetBrains Mono', monospace",
      color: STATUS_COLORS[value] || "#6b7280",
      letterSpacing: 1, textTransform: "uppercase",
    }}>
      ● {value.replace(/_/g, " ")}
    </span>
  );
}

function ClassBadge({ value }: { value: string }) {
  const c: Record<string, string> = {
    unclassified: "#22c55e", restricted: "#f59e0b",
    confidential: "#f97316", secret: "#ef4444",
  };
  return (
    <span style={{
      fontSize: 8, letterSpacing: 2, fontFamily: "'JetBrains Mono', monospace",
      color: c[value] || "#6b7280", textTransform: "uppercase", padding: "2px 6px",
      border: `1px solid ${c[value] || "#6b7280"}30`, background: `${c[value] || "#6b7280"}10`,
    }}>
      {value}
    </span>
  );
}

function FacilityIcon({ type, size = 16 }: { type: string; size?: number }) {
  const meta = FACILITY_TYPES[type] || FACILITY_TYPES.other;
  return (
    <span style={{ fontSize: size, color: meta.color, flexShrink: 0 }}>
      {meta.icon}
    </span>
  );
}

function Skeleton() {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 1 }}>
      {[1, 2, 3, 4, 5].map((i) => (
        <div key={i} style={{
          height: 52, background: "rgba(22,163,74,0.03)",
          border: "1px solid #0f1f0f",
          animation: "pulse 1.5s ease-in-out infinite",
        }} />
      ))}
      <style>{`@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}`}</style>
    </div>
  );
}

// ── Modal ──────────────────────────────────────────────────────────────────

function PostModal({
  initial,
  onSave,
  onClose,
  role,
}: {
  initial?: Post;
  onSave: (data: Partial<Post>) => void;
  onClose: () => void;
  role: string;
}) {
  const [form, setForm] = useState<any>(initial ? { ...initial } : { ...BLANK });
  const [saving, setSaving] = useState(false);
  const [showMapPicker, setShowMapPicker] = useState(false);
  const [commanderSearch, setCommanderSearch] = useState("");
  const [commanderResults, setCommanderResults] = useState<any[]>([]);
  const [selectedCommander, setSelectedCommander] = useState<any>(null);

  const set = (k: string, v: any) => setForm((f: any) => ({ ...f, [k]: v }));

  const searchCommanders = useCallback(async (q: string) => {
    if (!q) { setCommanderResults([]); return; }
    try {
      const { data } = await postsApi.searchCommanders(q);
      setCommanderResults(data);
    } catch { setCommanderResults([]); }
  }, []);

  useEffect(() => {
    const t = setTimeout(() => searchCommanders(commanderSearch), 300);
    return () => clearTimeout(t);
  }, [commanderSearch, searchCommanders]);

  const handleSave = async () => {
    if (!form.name || !form.latitude || !form.longitude) return;
    setSaving(true);
    await onSave(form);
    setSaving(false);
  };

  const isCoord = role === "operations_coordinator";
  const typeHint = TYPE_HINTS[form.facility_type];

  const Row = ({ label, children }: { label: string; children: React.ReactNode }) => (
    <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
      <label style={{ color: "#6b7280", fontSize: 10, letterSpacing: 2, textTransform: "uppercase" }}>{label}</label>
      {children}
    </div>
  );

  const inputStyle = {
    width: "100%", padding: "9px 12px",
    background: "#050d05", border: "1px solid rgba(22,163,74,0.15)",
    color: "#d1fae5", fontSize: 12, outline: "none", boxSizing: "border-box" as const,
    fontFamily: "'Inter', sans-serif",
  };

  const selectStyle = { ...inputStyle };

  return (
    <div style={{
      position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)",
      display: "flex", alignItems: "center", justifyContent: "center",
      zIndex: 1000, padding: 20,
    }}>
      <div style={{
        background: "#0a120a", border: "1px solid rgba(22,163,74,0.2)",
        width: "100%", maxWidth: 680, maxHeight: "90vh",
        display: "flex", flexDirection: "column",
      }}>
        {/* Header */}
        <div style={{
          padding: "16px 20px", borderBottom: "1px solid #0f1f0f",
          display: "flex", justifyContent: "space-between", alignItems: "center", flexShrink: 0,
        }}>
          <div>
            <div style={{ color: "#1f4d1f", fontSize: 9, letterSpacing: 3, marginBottom: 3, fontFamily: "'JetBrains Mono', monospace" }}>
              {initial ? "EDIT FACILITY" : "NEW FACILITY"}
            </div>
            <h2 style={{ color: "#d1fae5", fontSize: 14, fontWeight: 700, margin: 0, letterSpacing: 1 }}>
              {initial ? initial.name : "Register New Post"}
            </h2>
          </div>
          <button onClick={onClose} style={{ background: "none", border: "none", color: "#4b5563", fontSize: 18, cursor: "pointer" }}>✕</button>
        </div>

        {/* Body */}
        <div style={{ flex: 1, overflowY: "auto", padding: 20, display: "flex", flexDirection: "column", gap: 14 }}>
          {/* Grid 1: Name + Type */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
            <Row label="Facility Name">
              <input style={inputStyle} value={form.name} onChange={(e) => set("name", e.target.value)} placeholder="Name" />
            </Row>
            <Row label="Facility Type">
              <select style={selectStyle} value={form.facility_type} onChange={(e) => set("facility_type", e.target.value)}>
                {Object.entries(FACILITY_TYPES).map(([k, v]) => (
                  <option key={k} value={k}>{v.icon} {v.label}</option>
                ))}
              </select>
            </Row>
          </div>

          {/* Type hint */}
          {typeHint && (
            <div style={{ background: "#0f2d0f", border: "1px solid #14532d", padding: "8px 12px", fontSize: 10, color: "#22c55e", fontFamily: "'JetBrains Mono', monospace", letterSpacing: 0.5 }}>
              ⚑ {typeHint}
            </div>
          )}

          {/* Grid 2: Lat + Lon + Map Picker */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr auto", gap: 12, alignItems: "end" }}>
            <Row label="Latitude">
              <input style={inputStyle} type="number" step="any" value={form.latitude}
                onChange={(e) => set("latitude", parseFloat(e.target.value))} placeholder="-1.9441" />
            </Row>
            <Row label="Longitude">
              <input style={inputStyle} type="number" step="any" value={form.longitude}
                onChange={(e) => set("longitude", parseFloat(e.target.value))} placeholder="30.0619" />
            </Row>
            <button
              onClick={() => setShowMapPicker(true)}
              style={{ padding: "9px 12px", background: "#052e16", border: "1px solid #15803d", color: "#22c55e", cursor: "pointer", fontSize: 11, whiteSpace: "nowrap", fontFamily: "'JetBrains Mono', monospace" }}
              title="Pick location on map"
            >
              📍 MAP
            </button>
          </div>

          {showMapPicker && (
            <MapPicker
              lat={form.latitude}
              lng={form.longitude}
              onPick={(lat, lng) => { set("latitude", parseFloat(lat.toFixed(6))); set("longitude", parseFloat(lng.toFixed(6))); setShowMapPicker(false); }}
              onClose={() => setShowMapPicker(false)}
            />
          )}

          {/* Address + Region */}
          <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 12 }}>
            <Row label="Address / Location">
              <input style={inputStyle} value={form.address || ""} onChange={(e) => set("address", e.target.value)} placeholder="Street address or grid reference" />
            </Row>
            <Row label="Region / Sector">
              <input style={inputStyle} value={form.region || ""} onChange={(e) => set("region", e.target.value)} placeholder="Region" />
            </Row>
          </div>

          <Row label="Description">
            <textarea style={{ ...inputStyle, resize: "vertical", minHeight: 64 }}
              value={form.description || ""} onChange={(e) => set("description", e.target.value)}
              placeholder="Brief description of this facility" />
          </Row>

          <Row label="Mission / Role">
            <textarea style={{ ...inputStyle, resize: "vertical", minHeight: 64 }}
              value={form.mission || ""} onChange={(e) => set("mission", e.target.value)}
              placeholder="What this facility does / its operational role" />
          </Row>

          {/* Threat Level */}
          <Row label="Threat Level">
            <div style={{ display: "flex", gap: 6 }}>
              {Object.entries(THREAT_COLORS).map(([level, meta]) => (
                <button
                  key={level}
                  onClick={() => set("threat_level", level)}
                  style={{
                    flex: 1, padding: "7px 4px", fontSize: 9, letterSpacing: 1,
                    fontFamily: "'JetBrains Mono', monospace", cursor: "pointer",
                    background: form.threat_level === level ? meta.bg : "#050d05",
                    border: `1px solid ${form.threat_level === level ? meta.text : "#1f2d1f"}`,
                    color: form.threat_level === level ? meta.text : "#374151",
                    textTransform: "uppercase",
                  }}
                >
                  {level}
                </button>
              ))}
            </div>
            <div style={{ fontSize: 10, color: THREAT_COLORS[form.threat_level]?.text ?? "#22c55e", fontFamily: "'JetBrains Mono', monospace", marginTop: 2 }}>
              {THREAT_COLORS[form.threat_level]?.label}
            </div>
          </Row>

          {/* Commander + Contact */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
            <Row label="Commander / OIC (free text)">
              <input style={inputStyle} value={form.commander_name || ""} onChange={(e) => set("commander_name", e.target.value)} placeholder="Name or callsign" />
            </Row>
            <Row label="Contact Info">
              <input style={inputStyle} value={form.contact_info || ""} onChange={(e) => set("contact_info", e.target.value)} placeholder="Radio freq, phone, etc." />
            </Row>
          </div>

          {/* Commander linked to system user */}
          <Row label="Commander (System User)">
            <div style={{ position: "relative" }}>
              <input
                style={inputStyle}
                value={selectedCommander ? `${selectedCommander.full_name} (@${selectedCommander.username})` : commanderSearch}
                onChange={(e) => { setSelectedCommander(null); set("commander_user_id", undefined); setCommanderSearch(e.target.value); }}
                placeholder="Search by name or username…"
              />
              {commanderResults.length > 0 && !selectedCommander && (
                <div style={{ position: "absolute", top: "100%", left: 0, right: 0, background: "#0a120a", border: "1px solid #1f2d1f", zIndex: 100, maxHeight: 160, overflowY: "auto" }}>
                  {commanderResults.map((u) => (
                    <button
                      key={u.id}
                      onClick={() => { setSelectedCommander(u); set("commander_user_id", u.id); setCommanderSearch(""); setCommanderResults([]); }}
                      style={{ width: "100%", display: "flex", alignItems: "center", gap: 8, padding: "8px 12px", background: "none", border: "none", cursor: "pointer", textAlign: "left", borderBottom: "1px solid #0f1f0f" }}
                    >
                      <div style={{ width: 26, height: 26, borderRadius: "50%", background: "#14532d", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, color: "#22c55e", flexShrink: 0 }}>
                        {u.full_name?.charAt(0) ?? "?"}
                      </div>
                      <div>
                        <div style={{ color: "#d1fae5", fontSize: 12 }}>{u.full_name}</div>
                        <div style={{ color: "#4b5563", fontSize: 10 }}>@{u.username} · {u.role.replace(/_/g, " ")}</div>
                      </div>
                    </button>
                  ))}
                </div>
              )}
              {selectedCommander && (
                <button onClick={() => { setSelectedCommander(null); set("commander_user_id", undefined); }} style={{ position: "absolute", right: 8, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "#ef4444", cursor: "pointer", fontSize: 14 }}>✕</button>
              )}
            </div>
          </Row>

          {/* Status + Classification + Capacity */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
            <Row label="Status">
              <select style={selectStyle} value={form.status} onChange={(e) => set("status", e.target.value)}>
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
                <option value="under_construction">Under Construction</option>
                <option value="decommissioned">Decommissioned</option>
              </select>
            </Row>
            <Row label="Classification">
              <select style={selectStyle} value={form.classification} onChange={(e) => set("classification", e.target.value)}>
                {CLASSIFICATIONS.map((c) => <option key={c} value={c}>{c.charAt(0).toUpperCase() + c.slice(1)}</option>)}
              </select>
            </Row>
            <Row label="Capacity (personnel)">
              <input style={inputStyle} type="number" value={form.capacity || ""}
                onChange={(e) => set("capacity", e.target.value ? parseInt(e.target.value) : undefined)} placeholder="0" />
            </Row>
          </div>

          {/* Visibility — coordinator only */}
          {isCoord && (
            <Row label="Map Visibility">
              <select style={selectStyle} value={form.visibility} onChange={(e) => set("visibility", e.target.value)}>
                <option value="all_personnel">All Personnel (field users see on map)</option>
                <option value="planning_only">Planning Only (hidden from field users)</option>
                <option value="assigned_teams">Assigned Teams Only</option>
              </select>
            </Row>
          )}
        </div>

        {/* Footer */}
        <div style={{
          padding: "14px 20px", borderTop: "1px solid #0f1f0f",
          display: "flex", justifyContent: "flex-end", gap: 8, flexShrink: 0,
        }}>
          <button onClick={onClose} style={{
            padding: "9px 20px", background: "none", border: "1px solid #1f2d1f",
            color: "#6b7280", cursor: "pointer", fontSize: 12,
          }}>Cancel</button>
          <button onClick={handleSave} disabled={saving || !form.name} style={{
            padding: "9px 24px", background: "#16a34a", border: "none",
            color: "#000", cursor: "pointer", fontSize: 12, fontWeight: 700,
            opacity: saving || !form.name ? 0.5 : 1,
          }}>
            {saving ? "Saving..." : initial ? "Save Changes" : "Create Facility"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Main Page ──────────────────────────────────────────────────────────────

export default function Posts() {
  const { user } = useAuthStore();
  const role = user?.role || "field_user";
  const isCoord = role === "operations_coordinator";
  const canCreate = role === "operations_coordinator" || role === "planning_officer";

  const [posts, setPosts] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [filterType, setFilterType] = useState("");
  const [filterStatus, setFilterStatus] = useState("");
  const [search, setSearch] = useState("");

  const [modal, setModal] = useState<{ open: boolean; post?: Post }>({ open: false });
  const [detailPost, setDetailPost] = useState<Post | null>(null);

  const [planningUsers, setPlanningUsers] = useState<any[]>([]);
  const [accessModal, setAccessModal] = useState<Post | null>(null);

  const load = async () => {
    setLoading(true);
    try {
      const { data } = await postsApi.list({ facility_type: filterType || undefined, status: filterStatus || undefined });
      setPosts(data);
    } catch {
      setError("Failed to load facilities");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [filterType, filterStatus]);

  const loadPlanningUsers = async () => {
    const { data } = await userApi.list();
    setPlanningUsers(data.filter((u: any) => u.role === "planning_officer"));
  };

  const handleSave = async (form: any, existing?: Post) => {
    try {
      if (existing) {
        await postsApi.update(existing.id, form);
      } else {
        await postsApi.create(form);
      }
      setModal({ open: false });
      await load();
    } catch (e: any) {
      alert(e.response?.data?.detail || "Failed to save");
    }
  };

  const handleDelete = async (post: Post) => {
    if (!confirm(`Delete "${post.name}"? This cannot be undone.`)) return;
    try {
      await postsApi.delete(post.id);
      await load();
    } catch (e: any) {
      alert(e.response?.data?.detail || "Failed to delete");
    }
  };

  const handlePublish = async (post: Post) => {
    await postsApi.togglePublish(post.id);
    await load();
  };

  const handleGrantAccess = async (postId: string, userId: string) => {
    await postsApi.grantAccess(postId, userId);
    await load();
    setAccessModal(posts.find((p) => p.id === postId) || null);
  };

  const handleRevokeAccess = async (postId: string, userId: string) => {
    await postsApi.revokeAccess(postId, userId);
    await load();
    setAccessModal(posts.find((p) => p.id === postId) || null);
  };

  const filtered = posts.filter((p) => {
    if (!search) return true;
    const q = search.toLowerCase();
    return (
      p.name.toLowerCase().includes(q) ||
      p.facility_type.includes(q) ||
      (p.region || "").toLowerCase().includes(q) ||
      (p.description || "").toLowerCase().includes(q)
    );
  });

  const S = {
    page: { flex: 1, display: "flex", flexDirection: "column" as const, background: "#060e06", fontFamily: "'Inter', sans-serif", minHeight: 0, overflow: "hidden" },
    header: { padding: "14px 20px 0", flexShrink: 0 },
    titleRow: { display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14 },
    title: { color: "#d1fae5", fontSize: 15, fontWeight: 700, margin: 0, letterSpacing: 1 },
    subtitle: { color: "#374151", fontSize: 11, marginTop: 3 },
    toolbar: { display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" as const, marginBottom: 14 },
    searchInput: {
      flex: 1, minWidth: 160, padding: "7px 12px",
      background: "#040804", border: "1px solid rgba(22,163,74,0.15)",
      color: "#d1fae5", fontSize: 11, outline: "none",
    },
    select: {
      padding: "7px 10px", background: "#040804", border: "1px solid rgba(22,163,74,0.15)",
      color: "#6b7280", fontSize: 11, outline: "none",
    },
    addBtn: {
      padding: "7px 16px", background: "#16a34a", border: "none",
      color: "#000", fontSize: 11, fontWeight: 700, cursor: "pointer",
      letterSpacing: 0.5, whiteSpace: "nowrap" as const,
    },
    body: { flex: 1, overflowY: "auto" as const, padding: "0 20px 20px" },
  };

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div style={S.titleRow}>
          <div>
            <h1 style={S.title}>Posts & Facilities</h1>
            <p style={S.subtitle}>
              {filtered.length} facilit{filtered.length !== 1 ? "ies" : "y"} —{" "}
              {posts.filter((p) => p.is_published).length} published
            </p>
          </div>
          {canCreate && (
            <button style={S.addBtn} onClick={() => setModal({ open: true })}>
              + Register Facility
            </button>
          )}
        </div>

        <div style={S.toolbar}>
          <input
            style={S.searchInput}
            placeholder="Search by name, region, type..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <select style={S.select} value={filterType} onChange={(e) => setFilterType(e.target.value)}>
            <option value="">All Types</option>
            {Object.entries(FACILITY_TYPES).map(([k, v]) => (
              <option key={k} value={k}>{v.icon} {v.label}</option>
            ))}
          </select>
          <select style={S.select} value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)}>
            <option value="">All Status</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
            <option value="under_construction">Under Construction</option>
            <option value="decommissioned">Decommissioned</option>
          </select>
        </div>
      </div>

      <div style={S.body}>
        {loading ? (
          <Skeleton />
        ) : error ? (
          <div style={{ color: "#ef4444", padding: 20, fontSize: 13 }}>{error}</div>
        ) : filtered.length === 0 ? (
          <div style={{
            padding: 48, textAlign: "center",
            border: "1px dashed rgba(22,163,74,0.1)", color: "#374151",
          }}>
            <div style={{ fontSize: 32, marginBottom: 12 }}>◌</div>
            <div style={{ fontSize: 13, marginBottom: 6, color: "#4b5563" }}>No facilities found</div>
            {canCreate && <div style={{ fontSize: 11 }}>Register your first facility using the button above</div>}
          </div>
        ) : (
          <>
            {/* Stats row */}
            <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 1, marginBottom: 1 }}>
              {[
                { label: "Total", value: posts.length },
                { label: "Published", value: posts.filter((p) => p.is_published).length, green: true },
                { label: "Active", value: posts.filter((p) => p.status === "active").length },
                { label: "Types", value: new Set(posts.map((p) => p.facility_type)).size },
              ].map(({ label, value, green }) => (
                <div key={label} style={{
                  background: "rgba(10,18,10,0.9)", border: "1px solid rgba(22,163,74,0.08)",
                  padding: "10px 14px",
                }}>
                  <div style={{ color: "#1f4d1f", fontSize: 8, letterSpacing: 2, marginBottom: 4, fontFamily: "'JetBrains Mono', monospace" }}>{label}</div>
                  <div style={{ color: green ? "#22c55e" : "#d1fae5", fontSize: 20, fontWeight: 700 }}>{value}</div>
                </div>
              ))}
            </div>

            {/* List */}
            <div style={{ display: "flex", flexDirection: "column", gap: 1, marginTop: 1 }}>
              {filtered.map((post) => {
                const meta = FACILITY_TYPES[post.facility_type] || FACILITY_TYPES.other;
                return (
                  <div
                    key={post.id}
                    style={{
                      background: "rgba(10,18,10,0.9)", border: "1px solid rgba(22,163,74,0.08)",
                      padding: "12px 16px",
                      display: "flex", alignItems: "center", gap: 14,
                      cursor: "pointer", transition: "border-color 0.1s",
                    }}
                    onMouseEnter={(e) => (e.currentTarget.style.borderColor = "rgba(22,163,74,0.25)")}
                    onMouseLeave={(e) => (e.currentTarget.style.borderColor = "rgba(22,163,74,0.08)")}
                    onClick={() => setDetailPost(post)}
                  >
                    {/* Type icon */}
                    <div style={{
                      width: 36, height: 36, flexShrink: 0,
                      background: `${meta.color}15`,
                      border: `1px solid ${meta.color}40`,
                      display: "flex", alignItems: "center", justifyContent: "center",
                      fontSize: 18, color: meta.color,
                    }}>
                      {meta.icon}
                    </div>

                    {/* Name + Type + Region */}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 3 }}>
                        <span style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>{post.name}</span>
                        <ClassBadge value={post.classification} />
                        {post.is_published && (
                          <span style={{ fontSize: 8, color: "#22c55e", letterSpacing: 2, fontFamily: "'JetBrains Mono', monospace" }}>
                            ● PUBLISHED
                          </span>
                        )}
                      </div>
                      <div style={{ display: "flex", gap: 14, flexWrap: "wrap" }}>
                        <span style={{ color: "#374151", fontSize: 11 }}>{meta.label}</span>
                        {post.region && <span style={{ color: "#1f4d1f", fontSize: 11, fontFamily: "'JetBrains Mono', monospace" }}>{post.region}</span>}
                        {post.commander_name && <span style={{ color: "#374151", fontSize: 11 }}>OIC: {post.commander_name}</span>}
                      </div>
                    </div>

                    {/* Status */}
                    <div style={{ flexShrink: 0, textAlign: "right" }}>
                      <StatusBadge value={post.status} />
                      <div style={{ color: "#1f4d1f", fontSize: 9, fontFamily: "'JetBrains Mono', monospace", marginTop: 3 }}>
                        {post.latitude.toFixed(4)}, {post.longitude.toFixed(4)}
                      </div>
                    </div>

                    {/* Actions */}
                    {(post.can_edit || isCoord) && (
                      <div style={{ display: "flex", gap: 4, flexShrink: 0 }} onClick={(e) => e.stopPropagation()}>
                        {isCoord && (
                          <button
                            onClick={() => handlePublish(post)}
                            title={post.is_published ? "Unpublish" : "Publish to map"}
                            style={{
                              padding: "5px 8px", fontSize: 10,
                              background: post.is_published ? "rgba(34,197,94,0.15)" : "#052e16",
                              border: `1px solid ${post.is_published ? "#16a34a" : "#0f1f0f"}`,
                              color: post.is_published ? "#22c55e" : "#374151", cursor: "pointer",
                            }}
                          >
                            {post.is_published ? "↓ Unpublish" : "↑ Publish"}
                          </button>
                        )}
                        {post.can_edit && (
                          <button
                            onClick={() => setModal({ open: true, post })}
                            style={{ padding: "5px 8px", fontSize: 10, background: "#0a140a", border: "1px solid #0f1f0f", color: "#374151", cursor: "pointer" }}
                          >
                            Edit
                          </button>
                        )}
                        {isCoord && (
                          <>
                            <button
                              onClick={() => { setAccessModal(post); loadPlanningUsers(); }}
                              style={{ padding: "5px 8px", fontSize: 10, background: "#0a140a", border: "1px solid #0f1f0f", color: "#374151", cursor: "pointer" }}
                              title="Manage edit access"
                            >
                              Access
                            </button>
                            <button
                              onClick={() => handleDelete(post)}
                              style={{ padding: "5px 8px", fontSize: 10, background: "#1a0808", border: "1px solid #450a0a", color: "#ef4444", cursor: "pointer" }}
                            >
                              Delete
                            </button>
                          </>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </>
        )}
      </div>

      {/* Create / Edit Modal */}
      {modal.open && (
        <PostModal
          initial={modal.post}
          role={role}
          onSave={(form) => handleSave(form, modal.post)}
          onClose={() => setModal({ open: false })}
        />
      )}

      {/* Detail Drawer */}
      {detailPost && (
        <div style={{
          position: "fixed", right: 0, top: 0, bottom: 0, width: 360,
          background: "#0a120a", borderLeft: "1px solid rgba(22,163,74,0.15)",
          zIndex: 900, display: "flex", flexDirection: "column",
          boxShadow: "-8px 0 32px rgba(0,0,0,0.5)",
        }}>
          <div style={{ padding: "16px 20px", borderBottom: "1px solid #0f1f0f", display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
            <div>
              <div style={{ color: "#1f4d1f", fontSize: 8, letterSpacing: 3, fontFamily: "'JetBrains Mono', monospace", marginBottom: 4 }}>
                FACILITY RECORD
              </div>
              <h2 style={{ color: "#d1fae5", fontSize: 14, fontWeight: 700, margin: 0 }}>{detailPost.name}</h2>
            </div>
            <button onClick={() => setDetailPost(null)} style={{ background: "none", border: "none", color: "#4b5563", fontSize: 18, cursor: "pointer" }}>✕</button>
          </div>
          <div style={{ flex: 1, overflowY: "auto", padding: 20, display: "flex", flexDirection: "column", gap: 16 }}>
            {/* Type + Status */}
            <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
              <FacilityIcon type={detailPost.facility_type} size={24} />
              <div>
                <div style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>
                  {(FACILITY_TYPES[detailPost.facility_type] || FACILITY_TYPES.other).label}
                </div>
                <StatusBadge value={detailPost.status} />
              </div>
            </div>

            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <ClassBadge value={detailPost.classification} />
              {detailPost.is_published && (
                <span style={{ fontSize: 8, color: "#22c55e", letterSpacing: 2, fontFamily: "'JetBrains Mono', monospace", padding: "2px 6px", border: "1px solid #16a34a30", background: "#16a34a10" }}>
                  ● PUBLISHED
                </span>
              )}
              <span style={{ fontSize: 8, color: "#374151", letterSpacing: 2, fontFamily: "'JetBrains Mono', monospace", padding: "2px 6px", border: "1px solid #0f1f0f" }}>
                {detailPost.visibility.replace(/_/g, " ").toUpperCase()}
              </span>
            </div>

            {/* Location */}
            <div style={{ background: "#040804", border: "1px solid #0f1f0f", padding: "10px 14px" }}>
              <div style={{ color: "#1f4d1f", fontSize: 8, letterSpacing: 2, marginBottom: 6, fontFamily: "'JetBrains Mono', monospace" }}>LOCATION</div>
              <div style={{ color: "#22c55e", fontSize: 11, fontFamily: "'JetBrains Mono', monospace", marginBottom: 4 }}>
                {detailPost.latitude.toFixed(6)}, {detailPost.longitude.toFixed(6)}
              </div>
              {detailPost.address && <div style={{ color: "#374151", fontSize: 11 }}>{detailPost.address}</div>}
              {detailPost.region && <div style={{ color: "#374151", fontSize: 11 }}>{detailPost.region}</div>}
            </div>

            {/* Description */}
            {detailPost.description && (
              <div>
                <div style={{ color: "#1f4d1f", fontSize: 8, letterSpacing: 2, marginBottom: 6, fontFamily: "'JetBrains Mono', monospace" }}>DESCRIPTION</div>
                <p style={{ color: "#6b7280", fontSize: 12, margin: 0, lineHeight: 1.6 }}>{detailPost.description}</p>
              </div>
            )}

            {/* Mission */}
            {detailPost.mission && (
              <div style={{ background: "rgba(22,163,74,0.05)", border: "1px solid rgba(22,163,74,0.12)", padding: "10px 14px" }}>
                <div style={{ color: "#1f4d1f", fontSize: 8, letterSpacing: 2, marginBottom: 6, fontFamily: "'JetBrains Mono', monospace" }}>MISSION / ROLE</div>
                <p style={{ color: "#d1fae5", fontSize: 12, margin: 0, lineHeight: 1.6 }}>{detailPost.mission}</p>
              </div>
            )}

            {/* Commander + Contact */}
            {(detailPost.commander_name || detailPost.contact_info) && (
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
                {detailPost.commander_name && (
                  <div style={{ background: "#040804", border: "1px solid #0f1f0f", padding: "8px 12px" }}>
                    <div style={{ color: "#1f4d1f", fontSize: 7, letterSpacing: 2, marginBottom: 4, fontFamily: "'JetBrains Mono', monospace" }}>COMMANDER</div>
                    <div style={{ color: "#d1fae5", fontSize: 11 }}>{detailPost.commander_name}</div>
                  </div>
                )}
                {detailPost.contact_info && (
                  <div style={{ background: "#040804", border: "1px solid #0f1f0f", padding: "8px 12px" }}>
                    <div style={{ color: "#1f4d1f", fontSize: 7, letterSpacing: 2, marginBottom: 4, fontFamily: "'JetBrains Mono', monospace" }}>CONTACT</div>
                    <div style={{ color: "#d1fae5", fontSize: 11 }}>{detailPost.contact_info}</div>
                  </div>
                )}
              </div>
            )}

            {detailPost.capacity && (
              <div style={{ color: "#374151", fontSize: 11 }}>
                Capacity: <span style={{ color: "#d1fae5" }}>{detailPost.capacity} personnel</span>
              </div>
            )}

            <div style={{ color: "#1f4d1f", fontSize: 10, fontFamily: "'JetBrains Mono', monospace", borderTop: "1px solid #0f1f0f", paddingTop: 12 }}>
              Updated {new Date(detailPost.updated_at).toLocaleDateString()}
            </div>
          </div>
        </div>
      )}

      {/* Access Management Modal */}
      {accessModal && (
        <div style={{
          position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)",
          display: "flex", alignItems: "center", justifyContent: "center", zIndex: 1100,
        }}>
          <div style={{
            background: "#0a120a", border: "1px solid rgba(22,163,74,0.2)",
            width: 480, maxHeight: "70vh", display: "flex", flexDirection: "column",
          }}>
            <div style={{ padding: "16px 20px", borderBottom: "1px solid #0f1f0f", display: "flex", justifyContent: "space-between" }}>
              <div>
                <div style={{ color: "#1f4d1f", fontSize: 9, letterSpacing: 3, fontFamily: "'JetBrains Mono', monospace", marginBottom: 3 }}>EDIT ACCESS</div>
                <h3 style={{ color: "#d1fae5", fontSize: 13, fontWeight: 700, margin: 0 }}>{accessModal.name}</h3>
              </div>
              <button onClick={() => setAccessModal(null)} style={{ background: "none", border: "none", color: "#4b5563", fontSize: 18, cursor: "pointer" }}>✕</button>
            </div>
            <div style={{ flex: 1, overflowY: "auto", padding: 20 }}>
              <p style={{ color: "#374151", fontSize: 12, margin: "0 0 16px" }}>
                Grant planning officers the ability to edit this facility.
              </p>
              {planningUsers.map((u: any) => {
                const hasAccess = (accessModal.editor_ids || []).includes(u.id);
                return (
                  <div key={u.id} style={{
                    display: "flex", justifyContent: "space-between", alignItems: "center",
                    padding: "10px 12px", background: "#040804",
                    border: "1px solid #0f1f0f", marginBottom: 4,
                  }}>
                    <div>
                      <div style={{ color: "#d1fae5", fontSize: 12 }}>{u.full_name}</div>
                      <div style={{ color: "#374151", fontSize: 10 }}>@{u.username}</div>
                    </div>
                    <button
                      onClick={() => hasAccess
                        ? handleRevokeAccess(accessModal.id, u.id)
                        : handleGrantAccess(accessModal.id, u.id)
                      }
                      style={{
                        padding: "5px 12px", fontSize: 10, cursor: "pointer", border: "none",
                        background: hasAccess ? "#1a0808" : "#052e16",
                        color: hasAccess ? "#ef4444" : "#22c55e",
                      }}
                    >
                      {hasAccess ? "Revoke" : "Grant Access"}
                    </button>
                  </div>
                );
              })}
              {planningUsers.length === 0 && (
                <div style={{ color: "#374151", fontSize: 12, textAlign: "center", padding: 20 }}>No planning officers found</div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
