import { useEffect, useState, useCallback, useRef } from "react";
import {
  MdOutlineRadio, MdClose, MdOutlineAdd, MdOutlineSearch,
  MdOutlineDownload, MdOutlineWarning, MdOutlinePersonOff,
  MdOutlineCheckCircle, MdOutlineCircle, MdLocationOn,
  MdOutlineVideoCall, MdOutlineNotifications, MdOutlineDelete,
  MdOutlineSchedule, MdOutlinePeople, MdOutlineMap,
  MdOutlineFlag, MdOutlineShield,
} from "react-icons/md";
import { missionApi, teamApi, zonesApi, routeApi, postsApi } from "../services/api";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";
import { useNavigate } from "react-router-dom";

// ── Types ─────────────────────────────────────────────────────────────────────

type MissionStatus = "draft" | "planned" | "active" | "suspended" | "completed" | "archived";

interface Mission {
  id: string;
  name: string;
  description?: string;
  status: MissionStatus;
  area_of_operations?: string;
  briefing_notes?: string;
  briefing_datetime?: string;
  briefing_audience?: string;
  live_session_id?: string;
  zone_ids?: string[];
  route_ids?: string[];
  facility_ids?: string[];
  start_date?: string;
  end_date?: string;
  created_at: string;
  objectives: { id: string; title: string; is_completed: boolean; description?: string }[];
  assignments: { id: string; team_id?: string; user_id?: string; role_in_mission?: string }[];
}

interface Incident {
  id: string;
  incident_type: string;
  title: string;
  description?: string;
  severity: "low" | "medium" | "high" | "critical";
  status: string;
  latitude?: number;
  longitude?: number;
  reported_by?: string;
  created_at: string;
}

interface Casualty {
  id: string;
  user_id?: string;
  casualty_type: "KIA" | "WIA" | "MIA";
  notes?: string;
  created_at: string;
}

interface MissionEvidence {
  id: string;
  title: string;
  evidence_type: string;
  file_url?: string;
  approval_status: "pending" | "approved" | "rejected";
  created_by?: string;
  created_at: string;
}

interface Team { id: string; name: string; color?: string; }
interface Zone { id: string; name: string; zone_type: string; }
interface Route { id: string; name: string; route_type: string; color: string; }
interface Facility { id: string; name: string; facility_type?: string; }

// ── Constants ─────────────────────────────────────────────────────────────────

const STATUS_META: Record<MissionStatus, { label: string; color: string; bg: string }> = {
  draft:     { label: "DRAFT",     color: "#9ca3af", bg: "#1f2937" },
  planned:   { label: "PLANNED",   color: "#60a5fa", bg: "#1e3a5f" },
  active:    { label: "ACTIVE",    color: "#22c55e", bg: "#052e16" },
  suspended: { label: "SUSPENDED", color: "#f59e0b", bg: "#2d1a00" },
  completed: { label: "COMPLETED", color: "#a78bfa", bg: "#1a0030" },
  archived:  { label: "ARCHIVED",  color: "#6b7280", bg: "#111827" },
};

const SEVERITY_META: Record<string, { color: string }> = {
  low:      { color: "#6b7280" },
  medium:   { color: "#f59e0b" },
  high:     { color: "#ef4444" },
  critical: { color: "#dc2626" },
};

const STATUSES: MissionStatus[] = ["draft", "planned", "active", "suspended", "completed", "archived"];

function fmtDate(s?: string) {
  if (!s) return "—";
  return new Date(s).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
}
function fmtDateTime(s?: string) {
  if (!s) return "—";
  return new Date(s).toLocaleString("en-GB", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });
}

// ── Searchable Multi-Select ───────────────────────────────────────────────────

function SearchableMultiSelect<T extends { id: string }>({
  label, items, selected, onToggle, renderLabel, accentColor = "#22c55e",
}: {
  label: string;
  items: T[];
  selected: string[];
  onToggle: (id: string) => void;
  renderLabel: (item: T) => string;
  accentColor?: string;
}) {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const filtered = items.filter(i => renderLabel(i).toLowerCase().includes(q.toLowerCase()));

  const inputStyle: React.CSSProperties = {
    width: "100%", padding: "8px 10px",
    background: "#040804", border: `1px solid ${open ? accentColor : "#1f2d1f"}`,
    color: "#d1fae5", fontSize: 13, borderRadius: 4, outline: "none",
    cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "space-between",
    boxSizing: "border-box",
  };

  return (
    <div ref={ref} style={{ position: "relative" }}>
      <div style={inputStyle} onClick={() => setOpen(p => !p)}>
        <span style={{ color: selected.length ? "#d1fae5" : "#4b5563", fontSize: 12 }}>
          {selected.length === 0 ? `Select ${label}…` : `${selected.length} ${label} selected`}
        </span>
        <span style={{ color: "#4b5563", fontSize: 10 }}>▾</span>
      </div>
      {open && (
        <div style={{
          position: "absolute", top: "calc(100% + 2px)", left: 0, right: 0, zIndex: 100,
          background: "#060d06", border: `1px solid ${accentColor}`, maxHeight: 220, overflow: "hidden",
          display: "flex", flexDirection: "column", boxShadow: "0 8px 24px rgba(0,0,0,0.5)",
        }}>
          <div style={{ padding: "6px 8px", borderBottom: "1px solid #0a1a0a", display: "flex", alignItems: "center", gap: 6 }}>
            <MdOutlineSearch size={13} color="#4b5563" />
            <input autoFocus value={q} onChange={e => setQ(e.target.value)}
              placeholder={`Search ${label}…`}
              style={{ background: "none", border: "none", outline: "none", color: "#d1fae5", fontSize: 12, flex: 1 }} />
          </div>
          <div style={{ overflowY: "auto", flex: 1 }}>
            {filtered.length === 0
              ? <div style={{ padding: "10px 12px", color: "#4b5563", fontSize: 12 }}>No results</div>
              : filtered.map(item => (
                  <label key={item.id} style={{ display: "flex", alignItems: "center", gap: 8, padding: "7px 12px", cursor: "pointer", background: selected.includes(item.id) ? "#0a1f0a" : "transparent" }}>
                    <input type="checkbox" checked={selected.includes(item.id)}
                      onChange={() => onToggle(item.id)}
                      style={{ accentColor }} />
                    <span style={{ color: "#d1fae5", fontSize: 12 }}>{renderLabel(item)}</span>
                  </label>
                ))
            }
          </div>
        </div>
      )}
    </div>
  );
}

// ── Create Mission Modal ──────────────────────────────────────────────────────

function CreateModal({
  onClose, onCreated, teams, zones, routes, facilities,
}: {
  onClose: () => void;
  onCreated: () => void;
  teams: Team[];
  zones: Zone[];
  routes: Route[];
  facilities: Facility[];
}) {
  const [form, setForm] = useState({
    name: "", description: "", area_of_operations: "", briefing_notes: "",
    status: "planned" as MissionStatus,
    start_date: "", end_date: "", briefing_datetime: "", briefing_audience: "all",
  });
  const [selectedTeams, setSelectedTeams] = useState<string[]>([]);
  const [selectedZones, setSelectedZones] = useState<string[]>([]);
  const [selectedRoutes, setSelectedRoutes] = useState<string[]>([]);
  const [selectedFacilities, setSelectedFacilities] = useState<string[]>([]);
  const [objectives, setObjectives] = useState<string[]>([""]);
  const [saving, setSaving] = useState(false);

  const toggle = (arr: string[], setArr: (v: string[]) => void) => (id: string) =>
    setArr(arr.includes(id) ? arr.filter(x => x !== id) : [...arr, id]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      const body: Record<string, unknown> = {
        ...form,
        zone_ids: selectedZones,
        route_ids: selectedRoutes,
        facility_ids: selectedFacilities,
        objectives: objectives.filter(o => o.trim()).map((title, i) => ({ title, order_index: i })),
      };
      if (!body.briefing_datetime) delete body.briefing_datetime;
      const { data: mission } = await missionApi.create(body);
      for (const tid of selectedTeams) {
        await missionApi.assign(mission.id, { team_id: tid, role_in_mission: "assigned" }).catch(() => {});
      }
      onCreated();
      onClose();
    } catch { /**/ } finally { setSaving(false); }
  };

  const inp: React.CSSProperties = {
    width: "100%", padding: "8px 10px", background: "#040804",
    border: "1px solid #1f2d1f", color: "#d1fae5", fontSize: 13,
    borderRadius: 4, outline: "none", boxSizing: "border-box",
  };
  const lbl: React.CSSProperties = {
    fontSize: 10, color: "#4b5563", letterSpacing: 1.5,
    textTransform: "uppercase", marginBottom: 5, display: "block",
    fontFamily: "JetBrains Mono, monospace",
  };

  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 700, maxHeight: "92vh", overflowY: "auto", background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #16a34a", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
          <div>
            <div style={{ color: "#16a34a", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>NEW ORDER</div>
            <div style={{ color: "#f0fdf4", fontSize: 18, fontWeight: 700 }}>Create Mission</div>
          </div>
          <button onClick={onClose} style={{ color: "#4b5563", background: "none", border: "none", cursor: "pointer" }}>
            <MdClose size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14, marginBottom: 14 }}>
            <div style={{ gridColumn: "1/-1" }}>
              <label style={lbl}>Mission Name *</label>
              <input required style={inp} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Operation CODENAME" />
            </div>
            <div>
              <label style={lbl}>Area of Operations</label>
              <input style={inp} value={form.area_of_operations} onChange={e => setForm({ ...form, area_of_operations: e.target.value })} placeholder="Northern Sector" />
            </div>
            <div>
              <label style={lbl}>Status</label>
              <select style={{ ...inp }} value={form.status} onChange={e => setForm({ ...form, status: e.target.value as MissionStatus })}>
                {STATUSES.slice(0, 4).map(s => <option key={s} value={s}>{STATUS_META[s].label}</option>)}
              </select>
            </div>
            <div>
              <label style={lbl}>Start Date</label>
              <input type="datetime-local" style={inp} value={form.start_date} onChange={e => setForm({ ...form, start_date: e.target.value })} />
            </div>
            <div>
              <label style={lbl}>End Date</label>
              <input type="datetime-local" style={inp} value={form.end_date} onChange={e => setForm({ ...form, end_date: e.target.value })} />
            </div>
          </div>

          <div style={{ marginBottom: 14 }}>
            <label style={lbl}>Description</label>
            <textarea style={{ ...inp, height: 56, resize: "none" }} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Mission overview…" />
          </div>

          {/* Briefing */}
          <div style={{ background: "#030903", border: "1px solid #0f1f0f", padding: "14px 16px", marginBottom: 14 }}>
            <div style={{ color: "#16a34a", fontSize: 9, letterSpacing: 3, marginBottom: 12, fontFamily: "JetBrains Mono, monospace" }}>BRIEFING DETAILS</div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 12 }}>
              <div>
                <label style={lbl}>Briefing Date & Time</label>
                <input type="datetime-local" style={inp} value={form.briefing_datetime} onChange={e => setForm({ ...form, briefing_datetime: e.target.value })} />
              </div>
              <div>
                <label style={lbl}>Audience</label>
                <select style={{ ...inp }} value={form.briefing_audience} onChange={e => setForm({ ...form, briefing_audience: e.target.value })}>
                  <option value="all">All Team Members</option>
                  <option value="team_leaders_only">Team Leaders Only</option>
                </select>
              </div>
            </div>
            <div>
              <label style={lbl}>Briefing Notes</label>
              <textarea style={{ ...inp, height: 68, resize: "none" }} value={form.briefing_notes} onChange={e => setForm({ ...form, briefing_notes: e.target.value })} placeholder="ROE, coordinates, comms channels…" />
            </div>
          </div>

          {/* Objectives */}
          <div style={{ marginBottom: 14 }}>
            <label style={lbl}>Objectives</label>
            {objectives.map((obj, i) => (
              <div key={i} style={{ display: "flex", gap: 6, marginBottom: 6 }}>
                <input style={{ ...inp, flex: 1 }} value={obj}
                  onChange={e => { const n = [...objectives]; n[i] = e.target.value; setObjectives(n); }}
                  placeholder={`Objective ${i + 1}`} />
                {objectives.length > 1 && (
                  <button type="button" onClick={() => setObjectives(objectives.filter((_, j) => j !== i))}
                    style={{ color: "#ef4444", background: "none", border: "none", cursor: "pointer" }}>
                    <MdClose size={14} />
                  </button>
                )}
              </div>
            ))}
            <button type="button" onClick={() => setObjectives([...objectives, ""])}
              style={{ color: "#22c55e", background: "none", border: "none", cursor: "pointer", fontSize: 12, display: "flex", alignItems: "center", gap: 4 }}>
              <MdOutlineAdd size={14} /> Add objective
            </button>
          </div>

          {/* Searchable dropdowns */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 20 }}>
            <div>
              <label style={lbl}>Assign Teams</label>
              <SearchableMultiSelect items={teams} selected={selectedTeams} onToggle={toggle(selectedTeams, setSelectedTeams)} label="teams" renderLabel={t => t.name} accentColor="#22c55e" />
            </div>
            <div>
              <label style={lbl}>Link Zones</label>
              <SearchableMultiSelect items={zones} selected={selectedZones} onToggle={toggle(selectedZones, setSelectedZones)} label="zones" renderLabel={z => z.name} accentColor="#a78bfa" />
            </div>
            <div>
              <label style={lbl}>Link Routes</label>
              <SearchableMultiSelect items={routes} selected={selectedRoutes} onToggle={toggle(selectedRoutes, setSelectedRoutes)} label="routes" renderLabel={r => r.name} accentColor="#38bdf8" />
            </div>
            <div>
              <label style={lbl}>Link Facilities</label>
              <SearchableMultiSelect items={facilities} selected={selectedFacilities} onToggle={toggle(selectedFacilities, setSelectedFacilities)} label="facilities" renderLabel={f => f.name} accentColor="#f59e0b" />
            </div>
          </div>

          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose}
              style={{ flex: 1, padding: 10, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>
              CANCEL
            </button>
            <button type="submit" disabled={saving || !form.name.trim()}
              style={{ flex: 2, padding: 10, background: saving ? "#374151" : "#16a34a", border: "none", color: "#000", cursor: saving ? "default" : "pointer", fontSize: 12, fontWeight: 700, letterSpacing: 1 }}>
              {saving ? "CREATING…" : "CREATE MISSION"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Notify Modal ─────────────────────────────────────────────────────────────

function NotifyModal({ mission, onClose }: { mission: Mission; onClose: () => void }) {
  const [message, setMessage] = useState(mission.briefing_notes ?? "");
  const [audience, setAudience] = useState(mission.briefing_audience ?? "all");
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState<number | null>(null);

  const send = async () => {
    setSending(true);
    try {
      const { data } = await missionApi.notify(mission.id, { message, audience });
      setSent(data.sent_to ?? 0);
    } catch { setSent(0); } finally { setSending(false); }
  };

  const inp: React.CSSProperties = {
    width: "100%", padding: "8px 10px", background: "#040804",
    border: "1px solid #1f2d1f", color: "#d1fae5", fontSize: 13, outline: "none",
  };

  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 440, background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #f59e0b", padding: "24px 28px" }}>
        <div style={{ marginBottom: 20 }}>
          <div style={{ color: "#f59e0b", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>PUSH NOTIFICATION</div>
          <div style={{ color: "#f0fdf4", fontSize: 16, fontWeight: 700 }}>Issue Briefing</div>
          <div style={{ color: "#4b5563", fontSize: 12, marginTop: 2 }}>{mission.name}</div>
        </div>
        {sent !== null ? (
          <div style={{ textAlign: "center", padding: "24px 0" }}>
            <MdOutlineRadio size={40} color="#22c55e" style={{ margin: "0 auto 12px" }} />
            <div style={{ color: "#22c55e", fontWeight: 700, fontSize: 16, marginBottom: 4 }}>Notifications Sent</div>
            <div style={{ color: "#6b7280", fontSize: 12 }}>{sent} personnel notified</div>
            <button onClick={onClose} style={{ marginTop: 20, padding: "8px 24px", background: "#16a34a", border: "none", color: "#000", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>CLOSE</button>
          </div>
        ) : (
          <>
            <div style={{ marginBottom: 12 }}>
              <label style={{ fontSize: 10, color: "#4b5563", letterSpacing: 1.5, display: "block", marginBottom: 5, fontFamily: "JetBrains Mono, monospace" }}>AUDIENCE</label>
              <select value={audience} onChange={e => setAudience(e.target.value)} style={{ ...inp }}>
                <option value="all">All Team Members</option>
                <option value="team_leaders_only">Team Leaders Only</option>
              </select>
            </div>
            <div style={{ marginBottom: 16 }}>
              <label style={{ fontSize: 10, color: "#4b5563", letterSpacing: 1.5, display: "block", marginBottom: 5, fontFamily: "JetBrains Mono, monospace" }}>MESSAGE</label>
              <textarea value={message} onChange={e => setMessage(e.target.value)} rows={5}
                placeholder="Briefing message…"
                style={{ ...inp, resize: "none", width: "100%" }} />
            </div>
            <div style={{ display: "flex", gap: 10 }}>
              <button onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
              <button onClick={send} disabled={sending}
                style={{ flex: 2, padding: 9, background: "#d97706", border: "none", color: "#000", cursor: "pointer", fontWeight: 700, fontSize: 12, display: "flex", alignItems: "center", justifyContent: "center", gap: 6 }}>
                <MdOutlineNotifications size={14} /> {sending ? "SENDING…" : "SEND BRIEFING"}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// ── Report Incident Modal ─────────────────────────────────────────────────────

function ReportIncidentModal({ missionId, onClose, onDone }: { missionId: string; onClose: () => void; onDone: () => void }) {
  const [form, setForm] = useState({ title: "", description: "", severity: "medium", incident_type: "patrol_report" });
  const [saving, setSaving] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      await missionApi.reportIncident(missionId, form);
      onDone(); onClose();
    } catch { /**/ } finally { setSaving(false); }
  };

  const inp: React.CSSProperties = { width: "100%", padding: "8px 10px", background: "#040804", border: "1px solid #1f2d1f", color: "#d1fae5", fontSize: 13, outline: "none", boxSizing: "border-box" };
  const lbl: React.CSSProperties = { fontSize: 10, color: "#4b5563", letterSpacing: 1.5, display: "block", marginBottom: 5, fontFamily: "JetBrains Mono, monospace" };

  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 440, background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #ef4444", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 20 }}>
          <div>
            <div style={{ color: "#ef4444", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>FIELD REPORT</div>
            <div style={{ color: "#f0fdf4", fontSize: 16, fontWeight: 700 }}>Report Incident</div>
          </div>
          <button onClick={onClose} style={{ background: "none", border: "none", color: "#4b5563", cursor: "pointer" }}><MdClose size={18} /></button>
        </div>
        <form onSubmit={submit}>
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Type</label>
            <select style={{ ...inp }} value={form.incident_type} onChange={e => setForm({ ...form, incident_type: e.target.value })}>
              <option value="patrol_report">Patrol Report</option>
              <option value="contact">Enemy Contact</option>
              <option value="obstacle">Obstacle / Hazard</option>
              <option value="equipment">Equipment Issue</option>
              <option value="other">Other</option>
            </select>
          </div>
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Title *</label>
            <input required style={inp} value={form.title} onChange={e => setForm({ ...form, title: e.target.value })} placeholder="Brief description" />
          </div>
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Details</label>
            <textarea style={{ ...inp, height: 72, resize: "none" }} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Full incident details…" />
          </div>
          <div style={{ marginBottom: 16 }}>
            <label style={lbl}>Severity</label>
            <select style={{ ...inp }} value={form.severity} onChange={e => setForm({ ...form, severity: e.target.value })}>
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
              <option value="critical">Critical</option>
            </select>
          </div>
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
            <button type="submit" disabled={saving} style={{ flex: 2, padding: 9, background: "#ef4444", border: "none", color: "#fff", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>
              {saving ? "SUBMITTING…" : "SUBMIT REPORT"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Report Casualty Modal ─────────────────────────────────────────────────────

function CasualtyModal({ missionId, users, onClose, onDone }: { missionId: string; users: { id: string; full_name: string; username: string }[]; onClose: () => void; onDone: () => void }) {
  const [form, setForm] = useState({ user_id: "", casualty_type: "WIA", notes: "" });
  const [saving, setSaving] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      await missionApi.reportCasualty(missionId, form);
      onDone(); onClose();
    } catch { /**/ } finally { setSaving(false); }
  };

  const inp: React.CSSProperties = { width: "100%", padding: "8px 10px", background: "#040804", border: "1px solid #1f2d1f", color: "#d1fae5", fontSize: 13, outline: "none", boxSizing: "border-box" };
  const lbl: React.CSSProperties = { fontSize: 10, color: "#4b5563", letterSpacing: 1.5, display: "block", marginBottom: 5, fontFamily: "JetBrains Mono, monospace" };

  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 420, background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #dc2626", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 20 }}>
          <div>
            <div style={{ color: "#dc2626", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>PRIORITY REPORT</div>
            <div style={{ color: "#f0fdf4", fontSize: 16, fontWeight: 700 }}>Casualty Report</div>
          </div>
          <button onClick={onClose} style={{ background: "none", border: "none", color: "#4b5563", cursor: "pointer" }}><MdClose size={18} /></button>
        </div>
        <form onSubmit={submit}>
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Personnel</label>
            <select style={{ ...inp }} value={form.user_id} onChange={e => setForm({ ...form, user_id: e.target.value })}>
              <option value="">Unknown / Not in system</option>
              {users.map(u => <option key={u.id} value={u.id}>{u.full_name || u.username}</option>)}
            </select>
          </div>
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Status</label>
            <div style={{ display: "flex", gap: 8 }}>
              {(["WIA", "KIA", "MIA"] as const).map(t => (
                <button key={t} type="button" onClick={() => setForm({ ...form, casualty_type: t })}
                  style={{
                    flex: 1, padding: "8px 0", fontSize: 12, fontWeight: 700, cursor: "pointer",
                    background: form.casualty_type === t ? (t === "KIA" ? "#7f1d1d" : t === "WIA" ? "#92400e" : "#1e3a5f") : "#0a140a",
                    border: `1px solid ${form.casualty_type === t ? (t === "KIA" ? "#dc2626" : t === "WIA" ? "#f59e0b" : "#3b82f6") : "#1f2d1f"}`,
                    color: form.casualty_type === t ? "#fff" : "#4b5563",
                  }}>
                  {t}
                </button>
              ))}
            </div>
          </div>
          <div style={{ marginBottom: 16 }}>
            <label style={lbl}>Notes</label>
            <textarea style={{ ...inp, height: 68, resize: "none" }} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} placeholder="Circumstances, location, actions taken…" />
          </div>
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
            <button type="submit" disabled={saving} style={{ flex: 2, padding: 9, background: "#dc2626", border: "none", color: "#fff", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>
              {saving ? "SUBMITTING…" : "FILE REPORT"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Main ─────────────────────────────────────────────────────────────────────

type DetailTab = "overview" | "incidents" | "evidence" | "casualties";

export default function Missions() {
  const { user } = useAuthStore();
  const navigate = useNavigate();
  const canManage = user?.role === "operations_coordinator" || user?.role === "planning_officer";
  const canReport = true; // all roles can report incidents

  const [missions, setMissions] = useState<Mission[]>([]);
  const [selected, setSelected] = useState<Mission | null>(null);
  const [filter, setFilter] = useState<MissionStatus | "all">("all");
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [showNotify, setShowNotify] = useState(false);
  const [showReportIncident, setShowReportIncident] = useState(false);
  const [showCasualty, setShowCasualty] = useState(false);
  const [detailTab, setDetailTab] = useState<DetailTab>("overview");
  const [startingBriefing, setStartingBriefing] = useState(false);

  const [teams, setTeams] = useState<Team[]>([]);
  const [zones, setZones] = useState<Zone[]>([]);
  const [routes, setRoutes] = useState<Route[]>([]);
  const [facilities, setFacilities] = useState<Facility[]>([]);
  const [allUsers, setAllUsers] = useState<{ id: string; full_name: string; username: string }[]>([]);

  // Mission detail data
  const [incidents, setIncidents] = useState<Incident[]>([]);
  const [casualties, setCasualties] = useState<Casualty[]>([]);
  const [evidence, setEvidence] = useState<MissionEvidence[]>([]);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data } = await missionApi.list();
      setMissions(data);
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  useEffect(() => {
    load();
    teamApi.list().then(({ data }) => setTeams(data?.teams ?? data ?? [])).catch(() => {});
    zonesApi.list().then(({ data }) => setZones(data)).catch(() => {});
    routeApi.list().then(({ data }) => setRoutes(data)).catch(() => {});
    postsApi.list().then(({ data }) => setFacilities(data?.posts ?? data ?? [])).catch(() => {});
    api.get("/users?page_size=100").then(({ data }) => setAllUsers(data?.users ?? [])).catch(() => {});
  }, [load]);

  const loadMissionDetail = useCallback(async (id: string) => {
    const [inc, cas, ev] = await Promise.allSettled([
      missionApi.listIncidents(id),
      missionApi.listCasualties(id),
      missionApi.listEvidence(id),
    ]);
    if (inc.status === "fulfilled") setIncidents(inc.value.data ?? []);
    if (cas.status === "fulfilled") setCasualties(cas.value.data ?? []);
    if (ev.status === "fulfilled") setEvidence(ev.value.data ?? []);
  }, []);

  useEffect(() => {
    if (selected) { loadMissionDetail(selected.id); }
    else { setIncidents([]); setCasualties([]); setEvidence([]); }
  }, [selected, loadMissionDetail]);

  const handleStatusChange = async (id: string, status: MissionStatus) => {
    await missionApi.update(id, { status }).catch(() => {});
    setMissions(prev => prev.map(m => m.id === id ? { ...m, status } : m));
    if (selected?.id === id) setSelected(s => s ? { ...s, status } : s);
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Delete this mission? This cannot be undone.")) return;
    await missionApi.delete(id).catch(() => {});
    setMissions(prev => prev.filter(m => m.id !== id));
    if (selected?.id === id) setSelected(null);
  };

  const handleStartBriefing = async () => {
    if (!selected) return;
    setStartingBriefing(true);
    try {
      const { data } = await missionApi.startBriefing(selected.id);
      navigate(`/live-feed?session=${data.session_id}`);
    } catch { /**/ } finally { setStartingBriefing(false); }
  };

  const handleApproveEvidence = async (evidenceId: string, action: "approve" | "reject") => {
    if (!selected) return;
    await missionApi.approveEvidence(selected.id, evidenceId, action).catch(() => {});
    await loadMissionDetail(selected.id);
  };

  const handleResolveIncident = async (incidentId: string) => {
    if (!selected) return;
    await missionApi.resolveIncident(selected.id, incidentId).catch(() => {});
    setIncidents(prev => prev.map(i => i.id === incidentId ? { ...i, status: "resolved" } : i));
  };

  const handleDownloadPackage = async () => {
    if (!selected) return;
    try {
      const { data } = await missionApi.downloadPackage(selected.id);
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `mission_${selected.name.replace(/\s+/g, "_")}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch { /**/ }
  };

  const filtered = filter === "all" ? missions : missions.filter(m => m.status === filter);

  const S: React.CSSProperties = { fontFamily: "Inter, sans-serif", height: "100%", display: "flex", background: "#030903", color: "#d1fae5" };
  const secHdr: React.CSSProperties = { color: "#1f3d1f", fontSize: 8, fontFamily: "JetBrains Mono, monospace", letterSpacing: 2, marginBottom: 6 };

  return (
    <div style={S}>
      {/* ── Left panel ── */}
      <div style={{ width: 280, minWidth: 280, display: "flex", flexDirection: "column", background: "#060d06", borderRight: "1px solid #0a1f0a" }}>
        <div style={{ padding: "14px 14px 10px", borderBottom: "1px solid #0a1f0a" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
            <div>
              <div style={{ color: "#16a34a", fontSize: 8, letterSpacing: 3, marginBottom: 3, fontFamily: "JetBrains Mono, monospace" }}>OPERATIONS</div>
              <div style={{ color: "#f0fdf4", fontWeight: 700, fontSize: 15 }}>Missions</div>
            </div>
            {canManage && (
              <button onClick={() => setShowCreate(true)}
                style={{ padding: "5px 12px", background: "#16a34a", border: "none", color: "#000", fontWeight: 700, fontSize: 11, cursor: "pointer", letterSpacing: 1, display: "flex", alignItems: "center", gap: 4 }}>
                <MdOutlineAdd size={14} /> NEW
              </button>
            )}
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
            {(["all", "active", "planned", "draft"] as const).map(s => (
              <button key={s} onClick={() => setFilter(s as MissionStatus | "all")}
                style={{
                  padding: "3px 8px", fontSize: 10, cursor: "pointer", border: "none",
                  background: filter === s ? (s === "all" ? "#1f2937" : STATUS_META[s as MissionStatus].bg) : "transparent",
                  color: filter === s ? (s === "all" ? "#d1fae5" : STATUS_META[s as MissionStatus].color) : "#4b5563",
                  fontFamily: "JetBrains Mono, monospace", letterSpacing: 1,
                }}>
                {s === "all" ? `ALL (${missions.length})` : `${STATUS_META[s].label} (${missions.filter(m => m.status === s).length})`}
              </button>
            ))}
          </div>
        </div>
        <div style={{ flex: 1, overflowY: "auto" }}>
          {loading
            ? [...Array(4)].map((_, i) => <div key={i} style={{ margin: "8px 12px", height: 64, background: "#0a1a0a" }} />)
            : filtered.length === 0
              ? <div style={{ padding: 32, textAlign: "center", color: "#374151", fontSize: 12 }}>No missions</div>
              : filtered.map(m => {
                  const meta = STATUS_META[m.status];
                  const isSel = selected?.id === m.id;
                  return (
                    <div key={m.id} onClick={() => { setSelected(m); setDetailTab("overview"); }}
                      style={{ padding: "10px 14px", cursor: "pointer", borderBottom: "1px solid #040804", borderLeft: `2px solid ${isSel ? "#16a34a" : "transparent"}`, background: isSel ? "#0a1f0a" : "transparent" }}>
                      <div style={{ display: "flex", justifyContent: "space-between", gap: 8, marginBottom: 4 }}>
                        <div style={{ color: "#f0fdf4", fontSize: 12, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", flex: 1 }}>{m.name}</div>
                        <span style={{ fontSize: 9, padding: "2px 6px", background: meta.bg, color: meta.color, fontFamily: "JetBrains Mono, monospace", flexShrink: 0 }}>{meta.label}</span>
                      </div>
                      {m.area_of_operations && <div style={{ color: "#4b5563", fontSize: 10, marginBottom: 2 }}>{m.area_of_operations}</div>}
                      <div style={{ color: "#1f3d1f", fontSize: 10, fontFamily: "JetBrains Mono, monospace" }}>
                        {m.assignments.length} teams · {m.objectives.length} obj · {fmtDate(m.created_at)}
                      </div>
                    </div>
                  );
                })
          }
        </div>
      </div>

      {/* ── Detail panel ── */}
      <div style={{ flex: 1, overflowY: "auto" }}>
        {!selected ? (
          <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 12, color: "#1f3d1f" }}>
            <MdOutlineFlag size={48} color="#1f3d1f" />
            <div style={{ fontFamily: "JetBrains Mono, monospace", fontSize: 10, letterSpacing: 3 }}>SELECT A MISSION</div>
          </div>
        ) : (
          <div style={{ padding: "24px 28px", maxWidth: 900 }}>
            {/* Header */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 20 }}>
              <div>
                <div style={{ color: "#16a34a", fontSize: 9, letterSpacing: 3, marginBottom: 6, fontFamily: "JetBrains Mono, monospace" }}>MISSION BRIEF</div>
                <div style={{ color: "#f0fdf4", fontSize: 22, fontWeight: 700, marginBottom: 4 }}>{selected.name}</div>
                {selected.area_of_operations && (
                  <div style={{ color: "#4b5563", fontSize: 12, display: "flex", alignItems: "center", gap: 4 }}>
                    <MdLocationOn size={12} /> {selected.area_of_operations}
                  </div>
                )}
              </div>
              <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 8 }}>
                <span style={{ fontSize: 10, padding: "4px 10px", background: STATUS_META[selected.status].bg, color: STATUS_META[selected.status].color, fontFamily: "JetBrains Mono, monospace", letterSpacing: 1 }}>
                  {STATUS_META[selected.status].label}
                </span>
                <div style={{ display: "flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
                  {canManage && (
                    <select value={selected.status}
                      onChange={e => handleStatusChange(selected.id, e.target.value as MissionStatus)}
                      style={{ padding: "4px 8px", background: "#0a140a", border: "1px solid #1f2d1f", color: "#9ca3af", fontSize: 11, outline: "none" }}>
                      {STATUSES.map(s => <option key={s} value={s}>{STATUS_META[s].label}</option>)}
                    </select>
                  )}
                  {canManage && (
                    <button onClick={handleStartBriefing} disabled={startingBriefing}
                      style={{ padding: "4px 10px", background: "#0e7490", border: "none", color: "#fff", fontSize: 10, fontWeight: 700, cursor: "pointer", letterSpacing: 1, display: "flex", alignItems: "center", gap: 4 }}>
                      <MdOutlineVideoCall size={13} /> {startingBriefing ? "STARTING…" : "LIVE BRIEF"}
                    </button>
                  )}
                  {canManage && (
                    <button onClick={() => setShowNotify(true)}
                      style={{ padding: "4px 10px", background: "#d97706", border: "none", color: "#000", fontSize: 10, fontWeight: 700, cursor: "pointer", letterSpacing: 1, display: "flex", alignItems: "center", gap: 4 }}>
                      <MdOutlineRadio size={13} /> BRIEF
                    </button>
                  )}
                  {canManage && (
                    <button onClick={() => handleDelete(selected.id)}
                      style={{ padding: "4px 10px", background: "#7f1d1d", border: "none", color: "#fca5a5", fontSize: 10, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}>
                      <MdOutlineDelete size={13} /> DEL
                    </button>
                  )}
                  <button onClick={handleDownloadPackage}
                    style={{ padding: "4px 10px", background: "#1f2937", border: "1px solid #374151", color: "#9ca3af", fontSize: 10, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}>
                    <MdOutlineDownload size={13} /> PKG
                  </button>
                </div>
              </div>
            </div>

            {/* Stats */}
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(130px, 1fr))", gap: 8, marginBottom: 20 }}>
              {([
                ["START", fmtDate(selected.start_date), MdOutlineSchedule],
                ["END", fmtDate(selected.end_date), MdOutlineSchedule],
                ["BRIEFING", fmtDateTime(selected.briefing_datetime), MdOutlineSchedule],
                ["TEAMS", `${selected.assignments.length}`, MdOutlinePeople],
                ["OBJECTIVES", `${selected.objectives.length}`, MdOutlineFlag],
                ["INCIDENTS", `${incidents.length}`, MdOutlineWarning],
              ] as [string, string, React.ElementType][]).map(([k, v, Icon]) => (
                <div key={k} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "8px 12px" }}>
                  <div style={{ ...secHdr, display: "flex", alignItems: "center", gap: 4 }}>
                    <Icon size={10} /> {k}
                  </div>
                  <div style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{v}</div>
                </div>
              ))}
            </div>

            {/* Tabs */}
            <div style={{ display: "flex", borderBottom: "1px solid #0a1f0a", marginBottom: 20, gap: 0 }}>
              {(["overview", "incidents", "evidence", "casualties"] as DetailTab[]).map(tab => (
                <button key={tab} onClick={() => setDetailTab(tab)}
                  style={{
                    padding: "8px 16px", fontSize: 11, cursor: "pointer", background: "none",
                    border: "none", borderBottom: detailTab === tab ? "2px solid #16a34a" : "2px solid transparent",
                    color: detailTab === tab ? "#22c55e" : "#4b5563",
                    fontFamily: "JetBrains Mono, monospace", letterSpacing: 1, textTransform: "uppercase",
                  }}>
                  {tab}{tab === "incidents" && incidents.length > 0 ? ` (${incidents.length})` : ""}
                  {tab === "casualties" && casualties.length > 0 ? ` (${casualties.length})` : ""}
                  {tab === "evidence" && evidence.filter(e => e.approval_status === "pending").length > 0 ? ` (${evidence.filter(e => e.approval_status === "pending").length})` : ""}
                </button>
              ))}
            </div>

            {/* ── Overview tab ── */}
            {detailTab === "overview" && (
              <>
                {selected.description && (
                  <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 12 }}>
                    <div style={secHdr}>DESCRIPTION</div>
                    <div style={{ color: "#9ca3af", fontSize: 12, lineHeight: 1.6 }}>{selected.description}</div>
                  </div>
                )}
                {selected.briefing_notes && (
                  <div style={{ background: "#030903", border: "1px solid #1a2d1a", padding: "12px 14px", marginBottom: 12 }}>
                    <div style={{ ...secHdr, color: "#16a34a" }}>BRIEFING NOTES</div>
                    <pre style={{ color: "#d1fae5", fontSize: 12, lineHeight: 1.7, fontFamily: "JetBrains Mono, monospace", whiteSpace: "pre-wrap", margin: 0 }}>{selected.briefing_notes}</pre>
                  </div>
                )}
                {selected.objectives.length > 0 && (
                  <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 12 }}>
                    <div style={secHdr}>OBJECTIVES</div>
                    {selected.objectives.map((obj, i) => (
                      <div key={obj.id} style={{ display: "flex", gap: 10, alignItems: "flex-start", marginBottom: 8 }}>
                        <div style={{ width: 20, height: 20, borderRadius: "50%", border: `2px solid ${obj.is_completed ? "#16a34a" : "#374151"}`, background: obj.is_completed ? "#052e16" : "transparent", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, fontSize: 10, color: "#16a34a" }}>
                          {obj.is_completed ? <MdOutlineCheckCircle size={12} /> : i + 1}
                        </div>
                        <div style={{ color: obj.is_completed ? "#374151" : "#d1fae5", fontSize: 12, textDecoration: obj.is_completed ? "line-through" : "none", lineHeight: 1.5 }}>{obj.title}</div>
                      </div>
                    ))}
                  </div>
                )}
                {/* Linked resources */}
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 12 }}>
                  {(selected.zone_ids ?? []).length > 0 && (
                    <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "10px 12px" }}>
                      <div style={secHdr}>ZONES</div>
                      {(selected.zone_ids ?? []).map(zid => {
                        const z = zones.find(x => x.id === zid);
                        return <div key={zid} style={{ fontSize: 11, color: "#a78bfa", marginBottom: 4, display: "flex", alignItems: "center", gap: 4 }}><MdOutlineMap size={11} /> {z?.name ?? zid.slice(0, 8)}</div>;
                      })}
                    </div>
                  )}
                  {(selected.route_ids ?? []).length > 0 && (
                    <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "10px 12px" }}>
                      <div style={secHdr}>ROUTES</div>
                      {(selected.route_ids ?? []).map(rid => {
                        const r = routes.find(x => x.id === rid);
                        return <div key={rid} style={{ fontSize: 11, color: r?.color ?? "#22c55e", marginBottom: 4 }}>{r?.name ?? rid.slice(0, 8)}</div>;
                      })}
                    </div>
                  )}
                  {(selected.facility_ids ?? []).length > 0 && (
                    <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "10px 12px" }}>
                      <div style={secHdr}>FACILITIES</div>
                      {(selected.facility_ids ?? []).map(fid => {
                        const f = facilities.find(x => x.id === fid);
                        return <div key={fid} style={{ fontSize: 11, color: "#f59e0b", marginBottom: 4, display: "flex", alignItems: "center", gap: 4 }}><MdOutlineShield size={11} /> {f?.name ?? fid.slice(0, 8)}</div>;
                      })}
                    </div>
                  )}
                </div>
                {selected.briefing_datetime && (
                  <div style={{ display: "flex", gap: 10, padding: "8px 12px", background: "#0a1400", border: "1px solid #1a2d00", fontSize: 11, alignItems: "center" }}>
                    <MdOutlineSchedule color="#f59e0b" size={14} />
                    <span style={{ color: "#d97706" }}>Briefing at {fmtDateTime(selected.briefing_datetime)}</span>
                    <span style={{ color: "#4b5563" }}>·</span>
                    <span style={{ color: "#6b7280" }}>{selected.briefing_audience === "team_leaders_only" ? "Team Leaders Only" : "All Personnel"}</span>
                  </div>
                )}
              </>
            )}

            {/* ── Incidents tab ── */}
            {detailTab === "incidents" && (
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                  <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>Mission Incidents</div>
                  <button onClick={() => setShowReportIncident(true)}
                    style={{ padding: "5px 12px", background: "#16a34a", border: "none", color: "#000", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}>
                    <MdOutlineAdd size={13} /> REPORT
                  </button>
                </div>
                {incidents.length === 0
                  ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No incidents reported</div>
                  : incidents.map(inc => (
                      <div key={inc.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 8, display: "flex", gap: 12, alignItems: "flex-start" }}>
                        <div style={{ width: 10, height: 10, borderRadius: "50%", background: SEVERITY_META[inc.severity]?.color ?? "#6b7280", marginTop: 4, flexShrink: 0 }} />
                        <div style={{ flex: 1 }}>
                          <div style={{ display: "flex", gap: 8, alignItems: "center", marginBottom: 4 }}>
                            <span style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{inc.title}</span>
                            <span style={{ fontSize: 9, padding: "2px 6px", background: inc.status === "resolved" ? "#052e16" : "#1f2937", color: inc.status === "resolved" ? "#22c55e" : "#9ca3af", fontFamily: "JetBrains Mono, monospace" }}>
                              {inc.status.toUpperCase()}
                            </span>
                            <span style={{ fontSize: 9, padding: "2px 6px", background: "#1f2937", color: SEVERITY_META[inc.severity]?.color ?? "#6b7280", fontFamily: "JetBrains Mono, monospace", marginLeft: "auto" }}>
                              {inc.severity.toUpperCase()}
                            </span>
                          </div>
                          {inc.description && <div style={{ color: "#6b7280", fontSize: 12, marginBottom: 4 }}>{inc.description}</div>}
                          <div style={{ color: "#374151", fontSize: 10, fontFamily: "JetBrains Mono, monospace" }}>
                            {inc.incident_type.replace("_", " ")} · {fmtDateTime(inc.created_at)}
                          </div>
                        </div>
                        {canManage && inc.status !== "resolved" && (
                          <button onClick={() => handleResolveIncident(inc.id)}
                            style={{ padding: "3px 8px", background: "#052e16", border: "1px solid #16a34a", color: "#22c55e", fontSize: 10, cursor: "pointer", flexShrink: 0, display: "flex", alignItems: "center", gap: 3 }}>
                            <MdOutlineCheckCircle size={11} /> RESOLVE
                          </button>
                        )}
                      </div>
                    ))
                }
              </div>
            )}

            {/* ── Evidence tab ── */}
            {detailTab === "evidence" && (
              <div>
                <div style={{ marginBottom: 12 }}>
                  <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>Field Evidence</div>
                  <div style={{ color: "#4b5563", fontSize: 11, marginTop: 2 }}>Approve evidence to mark mission progress. All approved triggers completion check.</div>
                </div>
                {evidence.length === 0
                  ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No evidence submitted</div>
                  : evidence.map(ev => (
                      <div key={ev.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 8, display: "flex", gap: 12, alignItems: "center" }}>
                        <MdOutlineShield size={16} color="#4b5563" style={{ flexShrink: 0 }} />
                        <div style={{ flex: 1 }}>
                          <div style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600, marginBottom: 2 }}>{ev.title}</div>
                          <div style={{ color: "#4b5563", fontSize: 11, fontFamily: "JetBrains Mono, monospace" }}>
                            {ev.evidence_type} · {fmtDateTime(ev.created_at)}
                          </div>
                        </div>
                        <span style={{
                          fontSize: 9, padding: "2px 8px", fontFamily: "JetBrains Mono, monospace",
                          background: ev.approval_status === "approved" ? "#052e16" : ev.approval_status === "rejected" ? "#7f1d1d" : "#1f2937",
                          color: ev.approval_status === "approved" ? "#22c55e" : ev.approval_status === "rejected" ? "#fca5a5" : "#9ca3af",
                        }}>
                          {ev.approval_status.toUpperCase()}
                        </span>
                        {canManage && ev.approval_status === "pending" && (
                          <div style={{ display: "flex", gap: 6 }}>
                            <button onClick={() => handleApproveEvidence(ev.id, "approve")}
                              style={{ padding: "3px 8px", background: "#052e16", border: "1px solid #16a34a", color: "#22c55e", fontSize: 10, cursor: "pointer" }}>
                              APPROVE
                            </button>
                            <button onClick={() => handleApproveEvidence(ev.id, "reject")}
                              style={{ padding: "3px 8px", background: "#7f1d1d", border: "1px solid #dc2626", color: "#fca5a5", fontSize: 10, cursor: "pointer" }}>
                              REJECT
                            </button>
                          </div>
                        )}
                      </div>
                    ))
                }
              </div>
            )}

            {/* ── Casualties tab ── */}
            {detailTab === "casualties" && (
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                  <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>Casualty Reports</div>
                  <button onClick={() => setShowCasualty(true)}
                    style={{ padding: "5px 12px", background: "#dc2626", border: "none", color: "#fff", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}>
                    <MdOutlinePersonOff size={13} /> REPORT
                  </button>
                </div>
                {casualties.length === 0
                  ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No casualties reported</div>
                  : casualties.map(c => {
                      const typeColor = c.casualty_type === "KIA" ? "#dc2626" : c.casualty_type === "WIA" ? "#f59e0b" : "#3b82f6";
                      const typeBg = c.casualty_type === "KIA" ? "#7f1d1d" : c.casualty_type === "WIA" ? "#2d1a00" : "#1e3a5f";
                      return (
                        <div key={c.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 8, display: "flex", gap: 12, alignItems: "flex-start" }}>
                          <span style={{ fontSize: 9, padding: "4px 8px", background: typeBg, color: typeColor, fontFamily: "JetBrains Mono, monospace", fontWeight: 700, flexShrink: 0, marginTop: 2 }}>
                            {c.casualty_type}
                          </span>
                          <div style={{ flex: 1 }}>
                            <div style={{ color: "#d1fae5", fontSize: 12, marginBottom: 2 }}>
                              {c.user_id ? (allUsers.find(u => u.id === c.user_id)?.full_name ?? "Unknown") : "Unknown Personnel"}
                            </div>
                            {c.notes && <div style={{ color: "#6b7280", fontSize: 12 }}>{c.notes}</div>}
                            <div style={{ color: "#374151", fontSize: 10, fontFamily: "JetBrains Mono, monospace", marginTop: 4 }}>{fmtDateTime(c.created_at)}</div>
                          </div>
                        </div>
                      );
                    })
                }
              </div>
            )}
          </div>
        )}
      </div>

      {/* Modals */}
      {showCreate && (
        <CreateModal onClose={() => setShowCreate(false)} onCreated={load}
          teams={teams} zones={zones} routes={routes} facilities={facilities} />
      )}
      {showNotify && selected && (
        <NotifyModal mission={selected} onClose={() => setShowNotify(false)} />
      )}
      {showReportIncident && selected && (
        <ReportIncidentModal missionId={selected.id} onClose={() => setShowReportIncident(false)} onDone={() => loadMissionDetail(selected.id)} />
      )}
      {showCasualty && selected && (
        <CasualtyModal missionId={selected.id} users={allUsers} onClose={() => setShowCasualty(false)} onDone={() => loadMissionDetail(selected.id)} />
      )}
    </div>
  );
}
