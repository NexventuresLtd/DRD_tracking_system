import { useEffect, useState, useCallback, useRef } from "react";
import {
  MdOutlineRadio, MdClose, MdOutlineAdd, MdOutlineSearch,
  MdOutlineDownload, MdOutlineWarning, MdOutlinePersonOff,
  MdOutlineCheckCircle, MdLocationOn,
  MdOutlineVideoCall, MdOutlineNotifications, MdOutlineDelete,
  MdOutlineSchedule, MdOutlinePeople, MdOutlineMap,
  MdOutlineFlag, MdOutlineShield, MdOutlineRoute, MdOutlineDomain,
  MdArrowDownward, MdOutlineGavel, MdOutlineAssignment,
} from "react-icons/md";
import { missionApi, teamApi, zonesApi, routeApi, postsApi } from "../services/api";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";
import { useNavigate } from "react-router-dom";

// ── Types ─────────────────────────────────────────────────────────────────────

type MissionStatus =
  | "draft" | "approved" | "assigned" | "pending_acknowledgement"
  | "briefing" | "active" | "deploying" | "extraction"
  | "suspended" | "awaiting_review" | "debrief"
  | "completed" | "archived" | "planned";

type MissionPriority = "critical" | "high" | "medium" | "low";
type ReportCategory = "incident" | "contact" | "intelligence";

interface Mission {
  id: string;
  name: string;
  mission_code?: string;
  description?: string;
  status: MissionStatus;
  priority?: MissionPriority;
  area_of_operations?: string;
  briefing_notes?: string;
  briefing_datetime?: string;
  briefing_audience?: string;
  supporting_assets?: string;
  suspension_reason?: string;
  live_session_id?: string;
  zone_ids?: string[];
  route_ids?: string[];
  facility_ids?: string[];
  start_date?: string;
  end_date?: string;
  created_at: string;
  objectives: { id: string; title: string; is_completed: boolean; description?: string; order_index?: number; zone_id?: string; route_id?: string; facility_id?: string; completed_at?: string; completed_by?: string }[];
  assignments: { id: string; team_id?: string; user_id?: string; role_in_mission?: string }[];
}

interface Incident {
  id: string;
  report_category?: ReportCategory;
  incident_type: string;
  title: string;
  description?: string;
  severity: "low" | "medium" | "high" | "critical";
  status: string;
  latitude?: number;
  longitude?: number;
  contact_size?: string;
  contact_activity?: string;
  contact_unit?: string;
  contact_equipment?: string;
  reported_by?: string;
  created_at: string;
}

interface Casualty { id: string; user_id?: string; casualty_type: "KIA" | "WIA" | "MIA" | "captured"; notes?: string; created_at: string; }
interface MissionEvidence { id: string; title: string; evidence_type: string; file_url?: string; approval_status: "pending" | "approved" | "rejected"; created_by?: string; created_at: string; }
interface Ack { id: string; user_id: string; user_name: string; status: string; acknowledged_at?: string; }
interface AttendanceRec { id: string; user_id: string; user_name: string; status: string; marked_at: string; }
interface Sitrep { id: string; submitted_by?: string; team_status?: string; objective_progress?: string; conditions?: string; delays?: string; risks?: string; requests?: string; submitted_at: string; }
interface CompletionReport { id: string; objective_summary?: string; personnel_status?: string; incident_summary?: string; evidence_summary?: string; recommendations?: string; review_decision?: string; review_notes?: string; submitted_at: string; }
interface DebriefRecord { id: string; submitted_by?: string; lessons_learned?: string; incident_review?: string; evidence_review?: string; team_feedback?: string; created_at: string; }

interface Team { id: string; name: string; color?: string; }
interface Zone { id: string; name: string; zone_type: string; }
interface Route { id: string; name: string; route_type: string; color: string; }
interface Facility { id: string; name: string; facility_type?: string; }

// ── Constants ─────────────────────────────────────────────────────────────────

const STATUS_META: Record<string, { label: string; color: string; bg: string }> = {
  draft:                    { label: "DRAFT",      color: "#9ca3af", bg: "#1f2937" },
  planned:                  { label: "PLANNED",    color: "#60a5fa", bg: "#1e3a5f" },
  approved:                 { label: "APPROVED",   color: "#34d399", bg: "#064e3b" },
  assigned:                 { label: "ASSIGNED",   color: "#38bdf8", bg: "#0c4a6e" },
  pending_acknowledgement:  { label: "PENDING ACK",color: "#fbbf24", bg: "#2d1a00" },
  briefing:                 { label: "BRIEFING",   color: "#a78bfa", bg: "#2e1065" },
  active:                   { label: "ACTIVE",     color: "#22c55e", bg: "#052e16" },
  deploying:                { label: "DEPLOYING",  color: "#16a34a", bg: "#052e16" },
  extraction:               { label: "EXTRACTION", color: "#86efac", bg: "#052e16" },
  suspended:                { label: "SUSPENDED",  color: "#f59e0b", bg: "#2d1a00" },
  awaiting_review:          { label: "REVIEW",     color: "#fb923c", bg: "#431407" },
  debrief:                  { label: "DEBRIEF",    color: "#c084fc", bg: "#1a0030" },
  completed:                { label: "COMPLETED",  color: "#a78bfa", bg: "#1a0030" },
  archived:                 { label: "ARCHIVED",   color: "#6b7280", bg: "#111827" },
};

const PRIORITY_META: Record<MissionPriority, { color: string; bg: string }> = {
  critical: { color: "#ef4444", bg: "#7f1d1d" },
  high:     { color: "#f97316", bg: "#431407" },
  medium:   { color: "#fbbf24", bg: "#2d1a00" },
  low:      { color: "#22c55e", bg: "#052e16" },
};

const SEVERITY_META: Record<string, { color: string }> = {
  low: { color: "#6b7280" }, medium: { color: "#f59e0b" },
  high: { color: "#ef4444" }, critical: { color: "#dc2626" },
};

const LIFECYCLE = ["draft","approved","assigned","pending_acknowledgement","briefing","active","deploying","extraction","awaiting_review","debrief","completed","archived"];

function fmtDate(s?: string) { if (!s) return "—"; return new Date(s).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }); }
function fmtDateTime(s?: string) { if (!s) return "—"; return new Date(s).toLocaleString("en-GB", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }); }

const inp: React.CSSProperties = { width: "100%", padding: "8px 10px", background: "#040804", border: "1px solid #1f2d1f", color: "#d1fae5", fontSize: 13, outline: "none", boxSizing: "border-box" };
const lbl: React.CSSProperties = { fontSize: 10, color: "#4b5563", letterSpacing: 1.5, textTransform: "uppercase" as const, marginBottom: 5, display: "block", fontFamily: "JetBrains Mono, monospace" };

// ── SearchableMultiSelect ─────────────────────────────────────────────────────

function SearchableMultiSelect<T extends { id: string }>({ label, items, selected, onToggle, renderLabel, accentColor = "#22c55e" }: { label: string; items: T[]; selected: string[]; onToggle: (id: string) => void; renderLabel: (item: T) => string; accentColor?: string; }) {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const h = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, []);
  const filtered = items.filter(i => renderLabel(i).toLowerCase().includes(q.toLowerCase()));
  return (
    <div ref={ref} style={{ position: "relative" }}>
      <div style={{ ...inp, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "space-between", border: `1px solid ${open ? accentColor : "#1f2d1f"}` }} onClick={() => setOpen(p => !p)}>
        <span style={{ color: selected.length ? "#d1fae5" : "#4b5563", fontSize: 12 }}>{selected.length === 0 ? `Select ${label}…` : `${selected.length} ${label} selected`}</span>
        <span style={{ color: "#4b5563", fontSize: 10 }}>▾</span>
      </div>
      {open && (
        <div style={{ position: "absolute", top: "calc(100% + 2px)", left: 0, right: 0, zIndex: 100, background: "#060d06", border: `1px solid ${accentColor}`, maxHeight: 220, overflow: "hidden", display: "flex", flexDirection: "column", boxShadow: "0 8px 24px rgba(0,0,0,0.5)" }}>
          <div style={{ padding: "6px 8px", borderBottom: "1px solid #0a1a0a", display: "flex", alignItems: "center", gap: 6 }}>
            <MdOutlineSearch size={13} color="#4b5563" />
            <input autoFocus value={q} onChange={e => setQ(e.target.value)} placeholder={`Search ${label}…`} style={{ background: "none", border: "none", outline: "none", color: "#d1fae5", fontSize: 12, flex: 1 }} />
          </div>
          <div style={{ overflowY: "auto", flex: 1 }}>
            {filtered.length === 0 ? <div style={{ padding: "10px 12px", color: "#4b5563", fontSize: 12 }}>No results</div>
              : filtered.map(item => (
                <label key={item.id} style={{ display: "flex", alignItems: "center", gap: 8, padding: "7px 12px", cursor: "pointer", background: selected.includes(item.id) ? "#0a1f0a" : "transparent" }}>
                  <input type="checkbox" checked={selected.includes(item.id)} onChange={() => onToggle(item.id)} style={{ accentColor }} />
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

function ExecutionOrderTimeline({ objectives, zones, routes, facilities }: { objectives: Mission['objectives']; zones: Zone[]; routes: Route[]; facilities: Facility[] }) {
  const stepObjs = objectives.filter(o => o.title.startsWith("[ZONE]") || o.title.startsWith("[ROUTE]") || o.title.startsWith("[FACILITY]"));
  if (stepObjs.length === 0) return null;
  return (
    <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 12 }}>
      <div style={{ fontSize: 9, color: "#16a34a", letterSpacing: 3, marginBottom: 12, fontFamily: "JetBrains Mono, monospace" }}>EXECUTION ORDER</div>
      {stepObjs.map((obj, i) => {
        const isZone = obj.title.startsWith("[ZONE]"), isReturn = obj.title.startsWith("[ROUTE] Return via"), isRoute = obj.title.startsWith("[ROUTE]"), isFacility = obj.title.startsWith("[FACILITY]");
        const color = isZone ? "#a78bfa" : isRoute ? "#38bdf8" : "#f59e0b";
        const icon = isZone ? <MdOutlineMap size={14} /> : isRoute ? <MdOutlineRoute size={14} /> : <MdOutlineDomain size={14} />;
        const typeLabel = isZone ? "ZONE" : isReturn ? "RETURN" : isRoute ? "ROUTE" : "FACILITY";
        const displayTitle = obj.title.replace(/^\[ZONE\] Deploy to: |^\[ROUTE\] Return via: |^\[ROUTE\] Follow: |^\[FACILITY\] Report to: /, "");
        return (
          <div key={obj.id}>
            <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
              <div style={{ width: 28, height: 28, borderRadius: "50%", border: `2px solid ${color}`, background: obj.is_completed ? color + "22" : "transparent", display: "flex", alignItems: "center", justifyContent: "center", color, flexShrink: 0 }}>
                {obj.is_completed ? <MdOutlineCheckCircle size={14} /> : icon}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 11, color: obj.is_completed ? "#374151" : "#d1fae5", fontWeight: 600, textDecoration: obj.is_completed ? "line-through" : "none" }}>Step {i + 1}: {displayTitle}</div>
                <div style={{ fontSize: 9, color, letterSpacing: 1, fontFamily: "JetBrains Mono, monospace" }}>{typeLabel}</div>
              </div>
              {obj.is_completed && <div style={{ fontSize: 9, color: "#16a34a", fontFamily: "JetBrains Mono, monospace" }}>DONE</div>}
            </div>
            {i < stepObjs.length - 1 && <div style={{ marginLeft: 9, margin: "2px 0 2px 9px" }}><div style={{ width: 10, borderLeft: "2px dashed #1f2937", height: 16 }} /></div>}
          </div>
        );
      })}
    </div>
  );
}

// ── Lifecycle Pipeline ────────────────────────────────────────────────────────

function LifecyclePipeline({ mission, isCoord, isLeader, onTransition }: {
  mission: Mission;
  isCoord: boolean;
  isLeader: boolean;
  onTransition: (action: string, opts?: { reason?: string; decision?: string; notes?: string }) => Promise<void>;
}) {
  const [suspendReason, setSuspendReason] = useState("");
  const [showSuspend, setShowSuspend] = useState(false);
  const [reviewNotes, setReviewNotes] = useState("");
  const [busy, setBusy] = useState(false);

  const status = mission.status;
  const currentIdx = LIFECYCLE.indexOf(status);

  const act = async (action: string, opts?: object) => {
    setBusy(true);
    try { await onTransition(action, opts); } finally { setBusy(false); }
  };

  const actionBtn = (label: string, action: string, color: string, opts?: object) => (
    <button disabled={busy} onClick={() => act(action, opts)}
      style={{ padding: "5px 14px", background: color, border: "none", color: color === "#f59e0b" ? "#000" : "#fff", fontSize: 11, fontWeight: 700, cursor: "pointer", letterSpacing: 1, opacity: busy ? 0.5 : 1 }}>
      {busy ? "…" : label}
    </button>
  );

  return (
    <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 16 }}>
      {/* Phase scroll */}
      <div style={{ overflowX: "auto", display: "flex", gap: 0, alignItems: "center", marginBottom: 12, paddingBottom: 4 }}>
        {LIFECYCLE.map((phase, i) => {
          const isCurrent = phase === status;
          const isPast = currentIdx > i && status !== "suspended";
          const meta = STATUS_META[phase];
          return (
            <div key={phase} style={{ display: "flex", alignItems: "center", flexShrink: 0 }}>
              <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3 }}>
                <div style={{ width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8, borderRadius: "50%", background: isCurrent ? meta.color : isPast ? "#16a34a44" : "#1f2937", border: `1.5px solid ${isCurrent ? meta.color : isPast ? "#16a34a" : "#374151"}`, transition: "all 0.2s" }} />
                <div style={{ fontSize: 8, color: isCurrent ? meta.color : isPast ? "#4b5563" : "#374151", fontFamily: "JetBrains Mono, monospace", whiteSpace: "nowrap", letterSpacing: 0.5 }}>
                  {phase.replace(/_/g, " ").toUpperCase().slice(0, 8)}
                </div>
              </div>
              {i < LIFECYCLE.length - 1 && <div style={{ width: 20, height: 1, background: isPast ? "#16a34a44" : "#1f2937", margin: "0 2px", marginBottom: 14 }} />}
            </div>
          );
        })}
        {status === "suspended" && (
          <div style={{ display: "flex", alignItems: "center", gap: 4, marginLeft: 8, padding: "3px 8px", background: "#2d1a00", border: "1px solid #f59e0b", color: "#f59e0b", fontSize: 9, fontFamily: "JetBrains Mono, monospace" }}>
            ⚠ SUSPENDED
          </div>
        )}
      </div>

      {/* Action buttons */}
      {isCoord && (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          {status === "draft"                   && actionBtn("APPROVE", "approve", "#16a34a")}
          {status === "approved"                && actionBtn("ASSIGN & NOTIFY", "assign_notify", "#0e7490")}
          {(status === "assigned" || status === "pending_acknowledgement") && actionBtn("START BRIEFING", "start_briefing", "#7c3aed")}
          {status === "briefing"                && actionBtn("ACTIVATE", "activate", "#16a34a")}
          {status === "awaiting_review"         && actionBtn("ACCEPT → DEBRIEF", "review_complete", "#16a34a")}
          {status === "awaiting_review"         && actionBtn("RETURN TO ACTIVE", "review_return", "#6b7280")}
          {status === "debrief"                 && actionBtn("START DEBRIEF CALL", "start_debrief", "#7c3aed")}
          {!["completed","archived"].includes(status) && actionBtn("MARK COMPLETE", "complete", "#16a34a")}
          {status === "completed"               && actionBtn("ARCHIVE", "archive", "#374151")}
          {status !== "suspended" && status !== "completed" && status !== "archived" && (
            <button onClick={() => setShowSuspend(true)}
              style={{ padding: "5px 14px", background: "#7f1d1d", border: "none", color: "#fca5a5", fontSize: 11, fontWeight: 700, cursor: "pointer", letterSpacing: 1 }}>
              SUSPEND
            </button>
          )}
          {status === "suspended" && actionBtn("RESUME", "resume", "#f59e0b")}
        </div>
      )}

      {/* Non-coordinator acknowledge */}
      {!isCoord && (status === "assigned" || status === "pending_acknowledgement") && (
        <button onClick={() => act("acknowledge")}
          style={{ padding: "7px 20px", background: "#16a34a", border: "none", color: "#000", fontSize: 12, fontWeight: 700, cursor: "pointer", letterSpacing: 1 }}>
          ✓ ACKNOWLEDGE MISSION
        </button>
      )}

      {/* Suspension reason info */}
      {status === "suspended" && mission.suspension_reason && (
        <div style={{ marginTop: 8, fontSize: 11, color: "#f59e0b", fontFamily: "JetBrains Mono, monospace" }}>
          Reason: {mission.suspension_reason}
        </div>
      )}

      {/* Suspend prompt */}
      {showSuspend && (
        <div style={{ marginTop: 10, display: "flex", gap: 8, alignItems: "center" }}>
          <input value={suspendReason} onChange={e => setSuspendReason(e.target.value)} placeholder="Reason for suspension…"
            style={{ ...inp, flex: 1 }} />
          <button disabled={!suspendReason.trim() || busy}
            onClick={async () => { await act("suspend", { reason: suspendReason }); setShowSuspend(false); setSuspendReason(""); }}
            style={{ padding: "7px 14px", background: "#7f1d1d", border: "none", color: "#fca5a5", fontSize: 11, fontWeight: 700, cursor: "pointer" }}>
            CONFIRM
          </button>
          <button onClick={() => setShowSuspend(false)} style={{ background: "none", border: "none", color: "#4b5563", cursor: "pointer" }}><MdClose size={16} /></button>
        </div>
      )}

      {/* Review notes prompt for return */}
      {showSuspend === false && status === "awaiting_review" && isCoord && (
        <div style={{ marginTop: 8, display: "flex", gap: 8, alignItems: "center" }}>
          <input value={reviewNotes} onChange={e => setReviewNotes(e.target.value)} placeholder="Review notes (optional)…" style={{ ...inp, flex: 1 }} />
        </div>
      )}
    </div>
  );
}

// ── CreateModal ───────────────────────────────────────────────────────────────

type ObjFollowType = "none" | "zone" | "route" | "facility";
interface ObjectiveForm { id: string; title: string; followType: ObjFollowType; resourceId?: string; }

const FOLLOW_META: Record<ObjFollowType, { label: string; color: string }> = {
  none:     { label: "—",        color: "#4b5563" },
  zone:     { label: "Zone",     color: "#a78bfa" },
  route:    { label: "Route",    color: "#38bdf8" },
  facility: { label: "Facility", color: "#f59e0b" },
};

function CreateModal({ onClose, onCreated, teams, zones, routes, facilities }: { onClose: () => void; onCreated: () => void; teams: Team[]; zones: Zone[]; routes: Route[]; facilities: Facility[]; }) {
  const [form, setForm] = useState({ name: "", mission_code: "", description: "", area_of_operations: "", briefing_notes: "", supporting_assets: "", status: "draft", priority: "medium" as MissionPriority, start_date: "", end_date: "", briefing_datetime: "", briefing_audience: "all" });
  const [selectedTeams, setSelectedTeams] = useState<string[]>([]);
  const [objectives, setObjectives] = useState<ObjectiveForm[]>([{ id: "1", title: "", followType: "none", resourceId: undefined }]);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const updateObj = (id: string, patch: Partial<ObjectiveForm>) =>
    setObjectives(prev => prev.map(o => o.id === id ? { ...o, ...patch } : o));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) return;
    setSaving(true);
    setSaveError(null);
    try {
      const builtObjectives = objectives.filter(o => o.title.trim()).map((o, i) => {
        const prefix = o.followType === "zone" ? "[ZONE] Deploy to: " : o.followType === "route" ? "[ROUTE] Follow: " : o.followType === "facility" ? "[FACILITY] Report to: " : "";
        const resourceName = o.followType === "zone" ? zones.find(z => z.id === o.resourceId)?.name : o.followType === "route" ? routes.find(r => r.id === o.resourceId)?.name : o.followType === "facility" ? facilities.find(f => f.id === o.resourceId)?.name : undefined;
        return {
          title: o.followType !== "none" && o.resourceId ? `${prefix}${resourceName ?? o.title}` : o.title,
          order_index: i,
          zone_id:     o.followType === "zone"     ? o.resourceId : undefined,
          route_id:    o.followType === "route"    ? o.resourceId : undefined,
          facility_id: o.followType === "facility" ? o.resourceId : undefined,
        };
      });
      const body: Record<string, unknown> = {
        ...form,
        mission_code: form.mission_code || undefined,
        zone_ids:     [...new Set(objectives.filter(o => o.followType === "zone"     && o.resourceId).map(o => o.resourceId!))],
        route_ids:    [...new Set(objectives.filter(o => o.followType === "route"    && o.resourceId).map(o => o.resourceId!))],
        facility_ids: [...new Set(objectives.filter(o => o.followType === "facility" && o.resourceId).map(o => o.resourceId!))],
        objectives: builtObjectives,
      };
      if (!body.briefing_datetime) delete body.briefing_datetime;
      const { data: mission } = await missionApi.create(body);
      for (const tid of selectedTeams) await missionApi.assign(mission.id, { team_id: tid, role_in_mission: "assigned" }).catch(() => {});
      onCreated(); onClose();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail ?? "Failed to create mission";
      setSaveError(msg);
    } finally { setSaving(false); }
  };

  const rsInp: React.CSSProperties = { padding: "7px 8px", background: "#040804", border: "1px solid #1f2d1f", color: "#d1fae5", fontSize: 12, outline: "none", flex: 1, minWidth: 0 };

  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 700, maxHeight: "92vh", overflowY: "auto", background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #16a34a", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
          <div>
            <div style={{ color: "#16a34a", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>NEW ORDER</div>
            <div style={{ color: "#f0fdf4", fontSize: 18, fontWeight: 700 }}>Create Mission</div>
          </div>
          <button onClick={onClose} style={{ color: "#4b5563", background: "none", border: "none", cursor: "pointer" }}><MdClose size={18} /></button>
        </div>
        <form onSubmit={handleSubmit}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14, marginBottom: 14 }}>
            <div>
              <label style={lbl}>Mission Name *</label>
              <input required style={inp} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Operation CODENAME" />
            </div>
            <div>
              <label style={lbl}>Mission Code</label>
              <input style={inp} value={form.mission_code} onChange={e => setForm({ ...form, mission_code: e.target.value })} placeholder="OP-ALPHA-01" />
            </div>
            <div>
              <label style={lbl}>Priority</label>
              <select style={{ ...inp }} value={form.priority} onChange={e => setForm({ ...form, priority: e.target.value as MissionPriority })}>
                <option value="critical">CRITICAL</option>
                <option value="high">HIGH</option>
                <option value="medium">MEDIUM</option>
                <option value="low">LOW</option>
              </select>
            </div>
            <div>
              <label style={lbl}>Area of Operations</label>
              <input style={inp} value={form.area_of_operations} onChange={e => setForm({ ...form, area_of_operations: e.target.value })} placeholder="Northern Sector" />
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
          <div style={{ marginBottom: 14 }}>
            <label style={lbl}>Supporting Assets</label>
            <textarea style={{ ...inp, height: 48, resize: "none" }} value={form.supporting_assets} onChange={e => setForm({ ...form, supporting_assets: e.target.value })} placeholder="Vehicles, air support, comms assets…" />
          </div>
          <div style={{ background: "#030903", border: "1px solid #0f1f0f", padding: "14px 16px", marginBottom: 14 }}>
            <div style={{ color: "#16a34a", fontSize: 9, letterSpacing: 3, marginBottom: 12, fontFamily: "JetBrains Mono, monospace" }}>BRIEFING DETAILS</div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 12 }}>
              <div><label style={lbl}>Briefing Date & Time</label><input type="datetime-local" style={inp} value={form.briefing_datetime} onChange={e => setForm({ ...form, briefing_datetime: e.target.value })} /></div>
              <div><label style={lbl}>Audience</label><select style={{ ...inp }} value={form.briefing_audience} onChange={e => setForm({ ...form, briefing_audience: e.target.value })}><option value="all">All Team Members</option><option value="team_leaders_only">Team Leaders Only</option></select></div>
            </div>
            <div><label style={lbl}>Briefing Notes</label><textarea style={{ ...inp, height: 68, resize: "none" }} value={form.briefing_notes} onChange={e => setForm({ ...form, briefing_notes: e.target.value })} placeholder="ROE, coordinates, comms channels…" /></div>
          </div>

          {/* Objectives with inline zone/route/facility selection */}
          <div style={{ background: "#030903", border: "1px solid #0f1f0f", padding: "14px 16px", marginBottom: 14 }}>
            <div style={{ color: "#22c55e", fontSize: 9, letterSpacing: 3, marginBottom: 12, fontFamily: "JetBrains Mono, monospace" }}>OBJECTIVES</div>
            {objectives.map((obj, i) => {
              const meta = FOLLOW_META[obj.followType];
              const resourceOpts = obj.followType === "zone" ? zones : obj.followType === "route" ? routes : obj.followType === "facility" ? facilities : [];
              return (
                <div key={obj.id} style={{ marginBottom: 10 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: obj.followType !== "none" ? 6 : 0 }}>
                    <div style={{ width: 20, height: 20, borderRadius: "50%", background: "#0a1400", border: "1.5px solid #1f2d1f", display: "flex", alignItems: "center", justifyContent: "center", color: "#4b5563", fontSize: 9, fontWeight: 700, flexShrink: 0 }}>{i + 1}</div>
                    <input
                      style={{ ...rsInp }}
                      value={obj.title}
                      onChange={e => updateObj(obj.id, { title: e.target.value })}
                      placeholder={`Objective ${i + 1}…`}
                    />
                    {/* Type selector */}
                    <div style={{ display: "flex", gap: 2, flexShrink: 0 }}>
                      {(["none", "zone", "route", "facility"] as ObjFollowType[]).map(t => (
                        <button
                          key={t}
                          type="button"
                          onClick={() => updateObj(obj.id, { followType: t, resourceId: undefined })}
                          style={{ padding: "4px 7px", fontSize: 10, cursor: "pointer", fontWeight: obj.followType === t ? 700 : 400, background: obj.followType === t ? FOLLOW_META[t].color + "22" : "transparent", border: `1px solid ${obj.followType === t ? FOLLOW_META[t].color : "#1f2d1f"}`, color: obj.followType === t ? FOLLOW_META[t].color : "#4b5563", fontFamily: "JetBrains Mono, monospace" }}
                        >
                          {FOLLOW_META[t].label}
                        </button>
                      ))}
                    </div>
                    {objectives.length > 1 && (
                      <button type="button" onClick={() => setObjectives(prev => prev.filter(o => o.id !== obj.id))} style={{ color: "#ef4444", background: "none", border: "none", cursor: "pointer", flexShrink: 0 }}><MdClose size={14} /></button>
                    )}
                  </div>
                  {obj.followType !== "none" && (
                    <div style={{ display: "flex", alignItems: "center", gap: 6, marginLeft: 26 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 4, padding: "3px 8px", background: meta.color + "15", border: `1px solid ${meta.color}30`, color: meta.color, fontSize: 10, fontFamily: "JetBrains Mono, monospace", flexShrink: 0 }}>
                        {obj.followType === "zone" ? <MdOutlineMap size={11} /> : obj.followType === "route" ? <MdOutlineRoute size={11} /> : <MdOutlineDomain size={11} />}
                        {obj.followType.toUpperCase()}
                      </div>
                      <select
                        style={{ ...rsInp, border: `1px solid ${meta.color}40`, color: obj.resourceId ? "#d1fae5" : "#4b5563" }}
                        value={obj.resourceId ?? ""}
                        onChange={e => updateObj(obj.id, { resourceId: e.target.value || undefined })}
                      >
                        <option value="">— select {obj.followType} —</option>
                        {(resourceOpts as { id: string; name: string }[]).map(r => (
                          <option key={r.id} value={r.id}>{r.name}</option>
                        ))}
                      </select>
                    </div>
                  )}
                </div>
              );
            })}
            <button
              type="button"
              onClick={() => setObjectives(prev => [...prev, { id: Math.random().toString(36).slice(2), title: "", followType: "none", resourceId: undefined }])}
              style={{ color: "#22c55e", background: "none", border: "none", cursor: "pointer", fontSize: 12, display: "flex", alignItems: "center", gap: 4, marginTop: 4 }}
            >
              <MdOutlineAdd size={14} /> Add objective
            </button>
          </div>

          <div style={{ marginBottom: 20 }}>
            <label style={lbl}>Assign Teams</label>
            <SearchableMultiSelect items={teams} selected={selectedTeams} onToggle={(id) => setSelectedTeams(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id])} label="teams" renderLabel={t => t.name} accentColor="#22c55e" />
          </div>
          {saveError && (
            <div style={{ marginBottom: 10, padding: "8px 12px", background: "#7f1d1d", border: "1px solid #dc2626", color: "#fca5a5", fontSize: 11, fontFamily: "JetBrains Mono, monospace" }}>
              ERROR: {saveError}
            </div>
          )}
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: 10, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>CANCEL</button>
            <button type="submit" disabled={saving || !form.name.trim()} style={{ flex: 2, padding: 10, background: saving ? "#374151" : "#16a34a", border: "none", color: "#000", cursor: saving ? "default" : "pointer", fontSize: 12, fontWeight: 700, letterSpacing: 1 }}>{saving ? "CREATING…" : "CREATE MISSION"}</button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── NotifyModal ───────────────────────────────────────────────────────────────

function NotifyModal({ mission, onClose }: { mission: Mission; onClose: () => void }) {
  const [message, setMessage] = useState(mission.briefing_notes ?? "");
  const [audience, setAudience] = useState(mission.briefing_audience ?? "all");
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState<number | null>(null);
  const send = async () => { setSending(true); try { const { data } = await missionApi.notify(mission.id, { message, audience }); setSent(data.sent_to ?? 0); } catch { setSent(0); } finally { setSending(false); } };
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
            <div style={{ marginBottom: 12 }}><label style={lbl}>AUDIENCE</label><select value={audience} onChange={e => setAudience(e.target.value)} style={{ ...inp }}><option value="all">All Team Members</option><option value="team_leaders_only">Team Leaders Only</option></select></div>
            <div style={{ marginBottom: 16 }}><label style={lbl}>MESSAGE</label><textarea value={message} onChange={e => setMessage(e.target.value)} rows={5} placeholder="Briefing message…" style={{ ...inp, resize: "none" }} /></div>
            <div style={{ display: "flex", gap: 10 }}>
              <button onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
              <button onClick={send} disabled={sending} style={{ flex: 2, padding: 9, background: "#d97706", border: "none", color: "#000", cursor: "pointer", fontWeight: 700, fontSize: 12, display: "flex", alignItems: "center", justifyContent: "center", gap: 6 }}>
                <MdOutlineNotifications size={14} /> {sending ? "SENDING…" : "SEND BRIEFING"}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// ── ReportIncidentModal ───────────────────────────────────────────────────────

function ReportIncidentModal({ missionId, onClose, onDone }: { missionId: string; onClose: () => void; onDone: () => void }) {
  const [form, setForm] = useState({ title: "", description: "", severity: "medium", incident_type: "patrol_report", report_category: "incident" as ReportCategory, contact_size: "", contact_activity: "", contact_unit: "", contact_equipment: "" });
  const [saving, setSaving] = useState(false);
  const isContact = form.report_category === "contact";
  const submit = async (e: React.FormEvent) => {
    e.preventDefault(); setSaving(true);
    try { await missionApi.reportIncident(missionId, form); onDone(); onClose(); }
    catch { /**/ } finally { setSaving(false); }
  };
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 500, maxHeight: "90vh", overflowY: "auto", background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #ef4444", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 20 }}>
          <div><div style={{ color: "#ef4444", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>FIELD REPORT</div><div style={{ color: "#f0fdf4", fontSize: 16, fontWeight: 700 }}>Report Incident</div></div>
          <button onClick={onClose} style={{ background: "none", border: "none", color: "#4b5563", cursor: "pointer" }}><MdClose size={18} /></button>
        </div>
        <form onSubmit={submit}>
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Report Category</label>
            <div style={{ display: "flex", gap: 6 }}>
              {(["incident","contact","intelligence"] as ReportCategory[]).map(cat => (
                <button key={cat} type="button" onClick={() => setForm({ ...form, report_category: cat })}
                  style={{ flex: 1, padding: "7px 0", fontSize: 11, fontWeight: 700, cursor: "pointer", background: form.report_category === cat ? (cat === "contact" ? "#7f1d1d" : cat === "intelligence" ? "#1e3a5f" : "#052e16") : "#0a140a", border: `1px solid ${form.report_category === cat ? (cat === "contact" ? "#ef4444" : cat === "intelligence" ? "#3b82f6" : "#16a34a") : "#1f2d1f"}`, color: form.report_category === cat ? "#fff" : "#4b5563" }}>
                  {cat.toUpperCase()}
                </button>
              ))}
            </div>
          </div>
          <div style={{ marginBottom: 12 }}><label style={lbl}>Title *</label><input required style={inp} value={form.title} onChange={e => setForm({ ...form, title: e.target.value })} placeholder="Brief description" /></div>
          <div style={{ marginBottom: 12 }}><label style={lbl}>Details</label><textarea style={{ ...inp, height: 72, resize: "none" }} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Full details…" /></div>
          <div style={{ marginBottom: 12 }}><label style={lbl}>Severity</label><select style={{ ...inp }} value={form.severity} onChange={e => setForm({ ...form, severity: e.target.value })}><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option><option value="critical">Critical</option></select></div>
          {isContact && (
            <div style={{ background: "#1f0000", border: "1px solid #7f1d1d", padding: "12px 14px", marginBottom: 12 }}>
              <div style={{ color: "#ef4444", fontSize: 9, letterSpacing: 2, marginBottom: 10, fontFamily: "JetBrains Mono, monospace" }}>SALUTE REPORT</div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
                <div><label style={lbl}>Size</label><input style={inp} value={form.contact_size} onChange={e => setForm({ ...form, contact_size: e.target.value })} placeholder="e.g. 6-8 personnel" /></div>
                <div><label style={lbl}>Unit / ID</label><input style={inp} value={form.contact_unit} onChange={e => setForm({ ...form, contact_unit: e.target.value })} placeholder="Unknown" /></div>
                <div style={{ gridColumn: "1/-1" }}><label style={lbl}>Activity</label><textarea style={{ ...inp, height: 56, resize: "none" }} value={form.contact_activity} onChange={e => setForm({ ...form, contact_activity: e.target.value })} placeholder="What were they doing?" /></div>
                <div style={{ gridColumn: "1/-1" }}><label style={lbl}>Equipment</label><textarea style={{ ...inp, height: 48, resize: "none" }} value={form.contact_equipment} onChange={e => setForm({ ...form, contact_equipment: e.target.value })} placeholder="Weapons, vehicles, comms…" /></div>
              </div>
            </div>
          )}
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
            <button type="submit" disabled={saving} style={{ flex: 2, padding: 9, background: "#ef4444", border: "none", color: "#fff", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>{saving ? "SUBMITTING…" : "SUBMIT REPORT"}</button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── CasualtyModal ─────────────────────────────────────────────────────────────

function CasualtyModal({ missionId, users, onClose, onDone }: { missionId: string; users: { id: string; full_name: string; username: string }[]; onClose: () => void; onDone: () => void }) {
  const [form, setForm] = useState({ user_id: "", casualty_type: "WIA", notes: "" });
  const [saving, setSaving] = useState(false);
  const submit = async (e: React.FormEvent) => { e.preventDefault(); setSaving(true); try { await missionApi.reportCasualty(missionId, form); onDone(); onClose(); } catch { /**/ } finally { setSaving(false); } };
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 420, background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #dc2626", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 20 }}><div><div style={{ color: "#dc2626", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>PRIORITY REPORT</div><div style={{ color: "#f0fdf4", fontSize: 16, fontWeight: 700 }}>Casualty Report</div></div><button onClick={onClose} style={{ background: "none", border: "none", color: "#4b5563", cursor: "pointer" }}><MdClose size={18} /></button></div>
        <form onSubmit={submit}>
          <div style={{ marginBottom: 12 }}><label style={lbl}>Personnel</label><select style={{ ...inp }} value={form.user_id} onChange={e => setForm({ ...form, user_id: e.target.value })}><option value="">Unknown / Not in system</option>{users.map(u => <option key={u.id} value={u.id}>{u.full_name || u.username}</option>)}</select></div>
          <div style={{ marginBottom: 12 }}><label style={lbl}>Status</label><div style={{ display: "flex", gap: 8 }}>{(["WIA", "KIA", "MIA"] as const).map(t => <button key={t} type="button" onClick={() => setForm({ ...form, casualty_type: t })} style={{ flex: 1, padding: "8px 0", fontSize: 12, fontWeight: 700, cursor: "pointer", background: form.casualty_type === t ? (t === "KIA" ? "#7f1d1d" : t === "WIA" ? "#92400e" : "#1e3a5f") : "#0a140a", border: `1px solid ${form.casualty_type === t ? (t === "KIA" ? "#dc2626" : t === "WIA" ? "#f59e0b" : "#3b82f6") : "#1f2d1f"}`, color: form.casualty_type === t ? "#fff" : "#4b5563" }}>{t}</button>)}</div></div>
          <div style={{ marginBottom: 16 }}><label style={lbl}>Notes</label><textarea style={{ ...inp, height: 68, resize: "none" }} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} placeholder="Circumstances, location, actions taken…" /></div>
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
            <button type="submit" disabled={saving} style={{ flex: 2, padding: 9, background: "#dc2626", border: "none", color: "#fff", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>{saving ? "SUBMITTING…" : "FILE REPORT"}</button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── SitrepModal ───────────────────────────────────────────────────────────────

function SitrepModal({ missionId, onClose, onDone }: { missionId: string; onClose: () => void; onDone: () => void }) {
  const [form, setForm] = useState({ team_status: "", objective_progress: "", conditions: "", delays: "", risks: "", requests: "" });
  const [saving, setSaving] = useState(false);
  const submit = async (e: React.FormEvent) => { e.preventDefault(); setSaving(true); try { await missionApi.submitSitrep(missionId, form); onDone(); onClose(); } catch { /**/ } finally { setSaving(false); } };
  const field = (key: keyof typeof form, label: string) => (
    <div style={{ marginBottom: 12 }}><label style={lbl}>{label}</label><textarea style={{ ...inp, height: 56, resize: "none" }} value={form[key]} onChange={e => setForm({ ...form, [key]: e.target.value })} /></div>
  );
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 520, maxHeight: "90vh", overflowY: "auto", background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #38bdf8", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 20 }}><div><div style={{ color: "#38bdf8", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>SITUATION REPORT</div><div style={{ color: "#f0fdf4", fontSize: 16, fontWeight: 700 }}>Submit SITREP</div></div><button onClick={onClose} style={{ background: "none", border: "none", color: "#4b5563", cursor: "pointer" }}><MdClose size={18} /></button></div>
        <form onSubmit={submit}>
          {field("team_status", "Team Status")}
          {field("objective_progress", "Objective Progress")}
          {field("conditions", "Current Conditions")}
          {field("delays", "Delays / Obstacles")}
          {field("risks", "Risks")}
          {field("requests", "Requests / Needs")}
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
            <button type="submit" disabled={saving} style={{ flex: 2, padding: 9, background: "#0e7490", border: "none", color: "#fff", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>{saving ? "SUBMITTING…" : "SUBMIT SITREP"}</button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── CompletionReportModal ─────────────────────────────────────────────────────

function CompletionReportModal({ missionId, onClose, onDone }: { missionId: string; onClose: () => void; onDone: () => void }) {
  const [form, setForm] = useState({ objective_summary: "", personnel_status: "", incident_summary: "", evidence_summary: "", recommendations: "" });
  const [saving, setSaving] = useState(false);
  const submit = async (e: React.FormEvent) => { e.preventDefault(); setSaving(true); try { await missionApi.submitCompletionReport(missionId, form); onDone(); onClose(); } catch { /**/ } finally { setSaving(false); } };
  const field = (key: keyof typeof form, label: string) => (
    <div style={{ marginBottom: 12 }}><label style={lbl}>{label}</label><textarea style={{ ...inp, height: 60, resize: "none" }} value={form[key]} onChange={e => setForm({ ...form, [key]: e.target.value })} /></div>
  );
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 540, maxHeight: "90vh", overflowY: "auto", background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #16a34a", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 20 }}><div><div style={{ color: "#16a34a", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>MISSION CLOSURE</div><div style={{ color: "#f0fdf4", fontSize: 16, fontWeight: 700 }}>Completion Report</div></div><button onClick={onClose} style={{ background: "none", border: "none", color: "#4b5563", cursor: "pointer" }}><MdClose size={18} /></button></div>
        <form onSubmit={submit}>
          {field("objective_summary", "Objective Summary")}
          {field("personnel_status", "Personnel Status")}
          {field("incident_summary", "Incident Summary")}
          {field("evidence_summary", "Evidence Summary")}
          {field("recommendations", "Recommendations")}
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
            <button type="submit" disabled={saving} style={{ flex: 2, padding: 9, background: "#16a34a", border: "none", color: "#000", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>{saving ? "SUBMITTING…" : "REQUEST CLOSURE"}</button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── DebriefModal ──────────────────────────────────────────────────────────────

function DebriefModal({ missionId, onClose, onDone }: { missionId: string; onClose: () => void; onDone: () => void }) {
  const [form, setForm] = useState({ lessons_learned: "", incident_review: "", evidence_review: "", team_feedback: "" });
  const [saving, setSaving] = useState(false);
  const submit = async (e: React.FormEvent) => { e.preventDefault(); setSaving(true); try { await missionApi.submitDebrief(missionId, form); onDone(); onClose(); } catch { /**/ } finally { setSaving(false); } };
  const field = (key: keyof typeof form, label: string) => (
    <div style={{ marginBottom: 12 }}><label style={lbl}>{label}</label><textarea style={{ ...inp, height: 68, resize: "none" }} value={form[key]} onChange={e => setForm({ ...form, [key]: e.target.value })} /></div>
  );
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.85)", zIndex: 999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ width: "100%", maxWidth: 520, maxHeight: "90vh", overflowY: "auto", background: "#060d06", border: "1px solid #0a1f0a", borderTop: "2px solid #c084fc", padding: "24px 28px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 20 }}><div><div style={{ color: "#c084fc", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>POST-MISSION</div><div style={{ color: "#f0fdf4", fontSize: 16, fontWeight: 700 }}>Debrief</div></div><button onClick={onClose} style={{ background: "none", border: "none", color: "#4b5563", cursor: "pointer" }}><MdClose size={18} /></button></div>
        <form onSubmit={submit}>
          {field("lessons_learned", "Lessons Learned")}
          {field("incident_review", "Incident Review")}
          {field("evidence_review", "Evidence Review")}
          {field("team_feedback", "Team Feedback")}
          <div style={{ display: "flex", gap: 10 }}>
            <button type="button" onClick={onClose} style={{ flex: 1, padding: 9, background: "#0a140a", border: "1px solid #1f2d1f", color: "#6b7280", cursor: "pointer", fontSize: 12 }}>Cancel</button>
            <button type="submit" disabled={saving} style={{ flex: 2, padding: 9, background: "#7c3aed", border: "none", color: "#fff", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>{saving ? "SUBMITTING…" : "SUBMIT DEBRIEF"}</button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Main ──────────────────────────────────────────────────────────────────────

type DetailTab = "overview" | "incidents" | "evidence" | "casualties" | "acknowledgements" | "attendance" | "sitreps" | "completion" | "debrief";

export default function Missions() {
  const { user } = useAuthStore();
  const navigate = useNavigate();
  const isCoord = user?.role === "operations_coordinator";
  const isPlanning = user?.role === "planning_officer";
  const isLeader = user?.role === "team_leader";
  const canManage = isCoord || isPlanning;

  const [isMobile, setIsMobile] = useState(window.innerWidth < 768);
  useEffect(() => {
    const handler = () => setIsMobile(window.innerWidth < 768);
    window.addEventListener("resize", handler);
    return () => window.removeEventListener("resize", handler);
  }, []);

  const [missions, setMissions] = useState<Mission[]>([]);
  const [selected, setSelected] = useState<Mission | null>(null);
  const [filter, setFilter] = useState<string>("all");
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [showNotify, setShowNotify] = useState(false);
  const [showAddTeam, setShowAddTeam] = useState(false);
  const [addingTeam, setAddingTeam] = useState(false);
  const [showReportIncident, setShowReportIncident] = useState(false);
  const [showCasualty, setShowCasualty] = useState(false);
  const [showSitrep, setShowSitrep] = useState(false);
  const [showCompletion, setShowCompletion] = useState(false);
  const [showDebrief, setShowDebrief] = useState(false);
  const [detailTab, setDetailTab] = useState<DetailTab>("overview");
  const [startingBriefing, setStartingBriefing] = useState(false);
  const [startingDebrief, setStartingDebrief] = useState(false);

  const [teams, setTeams] = useState<Team[]>([]);
  const [zones, setZones] = useState<Zone[]>([]);
  const [routes, setRoutes] = useState<Route[]>([]);
  const [facilities, setFacilities] = useState<Facility[]>([]);
  const [allUsers, setAllUsers] = useState<{ id: string; full_name: string; username: string }[]>([]);

  const [incidents, setIncidents] = useState<Incident[]>([]);
  const [casualties, setCasualties] = useState<Casualty[]>([]);
  const [evidence, setEvidence] = useState<MissionEvidence[]>([]);
  const [acks, setAcks] = useState<Ack[]>([]);
  const [attendance, setAttendance] = useState<AttendanceRec[]>([]);
  const [sitreps, setSitreps] = useState<Sitrep[]>([]);
  const [completionReport, setCompletionReport] = useState<CompletionReport | null>(null);
  const [debriefs, setDebriefs] = useState<DebriefRecord[]>([]);
  const [incidentFilter, setIncidentFilter] = useState<ReportCategory | "all">("all");

  const load = useCallback(async () => {
    setLoading(true);
    try { const { data } = await missionApi.list(); setMissions(data); }
    catch { /**/ } finally { setLoading(false); }
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
    const [inc, cas, ev] = await Promise.allSettled([missionApi.listIncidents(id), missionApi.listCasualties(id), missionApi.listEvidence(id)]);
    if (inc.status === "fulfilled") setIncidents(inc.value.data ?? []);
    if (cas.status === "fulfilled") setCasualties(cas.value.data ?? []);
    if (ev.status === "fulfilled") setEvidence(ev.value.data ?? []);
  }, []);

  const loadTabData = useCallback(async (tab: DetailTab, id: string) => {
    if (tab === "acknowledgements") missionApi.listAcknowledgements(id).then(r => setAcks(r.data ?? [])).catch(() => {});
    if (tab === "attendance") missionApi.getAttendance(id).then(r => setAttendance(r.data ?? [])).catch(() => {});
    if (tab === "sitreps") missionApi.listSitreps(id).then(r => setSitreps(r.data ?? [])).catch(() => {});
    if (tab === "completion") missionApi.getCompletionReport(id).then(r => setCompletionReport(r.data)).catch(() => setCompletionReport(null));
    if (tab === "debrief") missionApi.listDebriefs(id).then(r => setDebriefs(r.data ?? [])).catch(() => {});
  }, []);

  useEffect(() => {
    if (selected) { loadMissionDetail(selected.id); }
    else { setIncidents([]); setCasualties([]); setEvidence([]); }
    setShowAddTeam(false);
  }, [selected, loadMissionDetail]);

  useEffect(() => {
    if (!selected) return;
    if (detailTab === "incidents" || detailTab === "evidence" || detailTab === "casualties") {
      loadMissionDetail(selected.id);
    } else if (detailTab !== "overview") {
      loadTabData(detailTab, selected.id);
    }
  }, [detailTab, selected, loadTabData, loadMissionDetail]);

  const handleLifecycleTransition = async (action: string, opts?: { reason?: string; decision?: string; notes?: string }) => {
    if (!selected) return;
    const id = selected.id;
    try {
      let newStatus = selected.status;
      if (action === "approve") { await missionApi.approve(id); newStatus = "approved"; }
      else if (action === "assign_notify") { setShowNotify(true); return; }
      else if (action === "start_briefing") { setStartingBriefing(true); try { const { data } = await missionApi.startLiveBriefing(id); navigate(`/live-feed?session=${data.session_id}`); return; } finally { setStartingBriefing(false); } }
      else if (action === "start_debrief") { setStartingDebrief(true); try { const { data } = await missionApi.startLiveDebrief(id); navigate(`/live-feed?session=${data.session_id}`); return; } finally { setStartingDebrief(false); } }
      else if (action === "activate") { await missionApi.activate(id); newStatus = "active"; }
      else if (action === "suspend") { await missionApi.suspend(id, { reason: opts?.reason ?? "" }); newStatus = "suspended"; }
      else if (action === "resume") { await missionApi.resume(id); newStatus = "active"; }
      else if (action === "review_complete") { await missionApi.reviewMission(id, { decision: "complete", notes: opts?.notes }); newStatus = "debrief"; }
      else if (action === "review_return") { await missionApi.reviewMission(id, { decision: "return", notes: opts?.notes }); newStatus = "active"; }
      else if (action === "complete") { await missionApi.completeMission(id); newStatus = "completed"; }
      else if (action === "archive") { await missionApi.archive(id); newStatus = "archived"; }
      else if (action === "acknowledge") { await missionApi.acknowledge(id); return; }
      const updated = { ...selected, status: newStatus as MissionStatus, suspension_reason: action === "suspend" ? opts?.reason : action === "resume" ? undefined : selected.suspension_reason };
      setSelected(updated);
      setMissions(prev => prev.map(m => m.id === id ? updated : m));
    } catch { /**/ }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Delete this mission? This cannot be undone.")) return;
    await missionApi.delete(id).catch(() => {});
    setMissions(prev => prev.filter(m => m.id !== id));
    if (selected?.id === id) setSelected(null);
  };

  const handleAddTeam = async (teamId: string) => {
    if (!selected || addingTeam) return;
    setAddingTeam(true);
    try {
      await missionApi.assign(selected.id, { team_id: teamId, role_in_mission: "assigned" });
      const { data } = await missionApi.getById(selected.id);
      setSelected(data);
      setMissions(prev => prev.map(m => m.id === selected.id ? data : m));
      setShowAddTeam(false);
    } catch { /**/ } finally { setAddingTeam(false); }
  };

  const handleRemoveTeam = async (assignmentId: string) => {
    if (!selected) return;
    try {
      await missionApi.unassign(selected.id, assignmentId);
      const updated = { ...selected, assignments: selected.assignments.filter(a => a.id !== assignmentId) };
      setSelected(updated);
      setMissions(prev => prev.map(m => m.id === selected.id ? updated : m));
    } catch { /**/ }
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

  const handleMarkAttendance = async (userId: string, status: string) => {
    if (!selected) return;
    await missionApi.markAttendance(selected.id, userId, status).catch(() => {});
    setAttendance(prev => prev.map(r => r.user_id === userId ? { ...r, status } : r));
  };

  const handleDownloadPackage = async () => {
    if (!selected) return;
    try {
      const { data } = await missionApi.downloadPackage(selected.id);
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a"); a.href = url; a.download = `mission_${selected.name.replace(/\s+/g, "_")}.json`; a.click(); URL.revokeObjectURL(url);
    } catch { /**/ }
  };

  const handleMarkObjectiveComplete = (objectiveId: string) => {
    if (!selected) return;
    const id = selected.id;
    const doComplete = async (lat?: number, lng?: number) => {
      await missionApi.completeObjective(id, objectiveId, { latitude: lat, longitude: lng }).catch(() => {});
      const { data } = await missionApi.getById(id);
      setSelected(data);
      setMissions((prev) => prev.map((m) => m.id === id ? data : m));
    };
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (pos) => doComplete(pos.coords.latitude, pos.coords.longitude).catch(() => {}),
        () => doComplete().catch(() => {}),
        { timeout: 5000 }
      );
    } else {
      doComplete().catch(() => {});
    }
  };

  const filteredMissions = filter === "all" ? missions : missions.filter(m => m.status === filter);
  const secHdr: React.CSSProperties = { color: "#1f3d1f", fontSize: 8, fontFamily: "JetBrains Mono, monospace", letterSpacing: 2, marginBottom: 6 };

  const TABS: { key: DetailTab; label: string; badge?: number }[] = [
    { key: "overview", label: "OVERVIEW" },
    { key: "incidents", label: "INCIDENTS", badge: incidents.length || undefined },
    { key: "evidence", label: "EVIDENCE", badge: evidence.filter(e => e.approval_status === "pending").length || undefined },
    { key: "casualties", label: "CASUALTIES", badge: casualties.length || undefined },
    { key: "acknowledgements", label: "ACKS" },
    { key: "attendance", label: "ATTENDANCE" },
    { key: "sitreps", label: "SITREPS" },
    { key: "completion", label: "COMPLETION" },
    { key: "debrief", label: "DEBRIEF" },
  ];

  return (
    <div style={{ fontFamily: "Inter, sans-serif", height: "100%", display: "flex", background: "#030903", color: "#d1fae5" }}>
      {/* ── Left panel ── */}
      <div style={{ width: isMobile ? "100%" : 280, minWidth: isMobile ? 0 : 280, display: isMobile && selected ? "none" : "flex", flexDirection: "column", background: "#060d06", borderRight: "1px solid #0a1f0a" }}>
        <div style={{ padding: "14px 14px 10px", borderBottom: "1px solid #0a1f0a" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
            <div><div style={{ color: "#16a34a", fontSize: 8, letterSpacing: 3, marginBottom: 3, fontFamily: "JetBrains Mono, monospace" }}>OPERATIONS</div><div style={{ color: "#f0fdf4", fontWeight: 700, fontSize: 15 }}>Missions</div></div>
            {canManage && <button onClick={() => setShowCreate(true)} style={{ padding: "5px 12px", background: "#16a34a", border: "none", color: "#000", fontWeight: 700, fontSize: 11, cursor: "pointer", letterSpacing: 1, display: "flex", alignItems: "center", gap: 4 }}><MdOutlineAdd size={14} /> NEW</button>}
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
            {(["all","active","briefing","draft","completed"] as const).map(s => (
              <button key={s} onClick={() => setFilter(s)} style={{ padding: "3px 8px", fontSize: 10, cursor: "pointer", border: "none", background: filter === s ? (s === "all" ? "#1f2937" : STATUS_META[s]?.bg ?? "#1f2937") : "transparent", color: filter === s ? (s === "all" ? "#d1fae5" : STATUS_META[s]?.color ?? "#d1fae5") : "#4b5563", fontFamily: "JetBrains Mono, monospace", letterSpacing: 1 }}>
                {s === "all" ? `ALL (${missions.length})` : `${(STATUS_META[s]?.label ?? s.toUpperCase()).slice(0,6)} (${missions.filter(m => m.status === s).length})`}
              </button>
            ))}
          </div>
        </div>
        <div style={{ flex: 1, overflowY: "auto" }}>
          {loading
            ? [...Array(4)].map((_, i) => <div key={i} style={{ margin: "8px 12px", height: 64, background: "#0a1a0a" }} />)
            : filteredMissions.length === 0
              ? <div style={{ padding: 32, textAlign: "center", color: "#374151", fontSize: 12 }}>No missions</div>
              : filteredMissions.map(m => {
                  const meta = STATUS_META[m.status] ?? STATUS_META.draft;
                  const priMeta = m.priority ? PRIORITY_META[m.priority] : null;
                  const isSel = selected?.id === m.id;
                  return (
                    <div key={m.id} onClick={() => { setSelected(m); setDetailTab("overview"); }} style={{ padding: "10px 14px", cursor: "pointer", borderBottom: "1px solid #040804", borderLeft: `2px solid ${isSel ? "#16a34a" : "transparent"}`, background: isSel ? "#0a1f0a" : "transparent" }}>
                      {m.mission_code && <div style={{ color: "#374151", fontSize: 9, fontFamily: "JetBrains Mono, monospace", marginBottom: 2 }}>{m.mission_code}</div>}
                      <div style={{ display: "flex", justifyContent: "space-between", gap: 8, marginBottom: 4 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 6, flex: 1, overflow: "hidden" }}>
                          {priMeta && <span style={{ fontSize: 8, padding: "1px 5px", background: priMeta.bg, color: priMeta.color, fontFamily: "JetBrains Mono, monospace", flexShrink: 0, fontWeight: 700 }}>{(m.priority ?? "").slice(0,4).toUpperCase()}</span>}
                          <div style={{ color: "#f0fdf4", fontSize: 12, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{m.name}</div>
                        </div>
                        <span style={{ fontSize: 9, padding: "2px 6px", background: meta.bg, color: meta.color, fontFamily: "JetBrains Mono, monospace", flexShrink: 0 }}>{meta.label.slice(0,8)}</span>
                      </div>
                      {m.area_of_operations && <div style={{ color: "#4b5563", fontSize: 10, marginBottom: 2 }}>{m.area_of_operations}</div>}
                      <div style={{ color: "#1f3d1f", fontSize: 10, fontFamily: "JetBrains Mono, monospace" }}>{m.assignments.length} teams · {m.objectives.length} obj · {fmtDate(m.created_at)}</div>
                    </div>
                  );
                })
          }
        </div>
      </div>

      {/* ── Detail panel ── */}
      <div style={{ flex: 1, overflowY: "auto", display: isMobile && !selected ? "none" : "block" }}>
        {!selected ? (
          <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 12, color: "#1f3d1f" }}>
            <MdOutlineFlag size={48} color="#1f3d1f" />
            <div style={{ fontFamily: "JetBrains Mono, monospace", fontSize: 10, letterSpacing: 3 }}>SELECT A MISSION</div>
          </div>
        ) : (
          <div style={{ padding: isMobile ? "14px 16px" : "24px 28px", maxWidth: 920 }}>
            {/* Mobile back button */}
            {isMobile && (
              <button onClick={() => setSelected(null)} style={{ background: "none", border: "none", color: "#22c55e", cursor: "pointer", display: "flex", alignItems: "center", gap: 4, fontSize: 12, padding: 0, marginBottom: 12 }}>
                ← BACK
              </button>
            )}
            {/* Header */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: 10, marginBottom: 16 }}>
              <div>
                <div style={{ color: "#16a34a", fontSize: 9, letterSpacing: 3, marginBottom: 4, fontFamily: "JetBrains Mono, monospace" }}>MISSION BRIEF</div>
                {selected.mission_code && <div style={{ color: "#374151", fontSize: 11, fontFamily: "JetBrains Mono, monospace", marginBottom: 2 }}>{selected.mission_code}</div>}
                <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 4 }}>
                  <div style={{ color: "#f0fdf4", fontSize: 22, fontWeight: 700 }}>{selected.name}</div>
                  {selected.priority && <span style={{ fontSize: 10, padding: "3px 8px", background: PRIORITY_META[selected.priority].bg, color: PRIORITY_META[selected.priority].color, fontFamily: "JetBrains Mono, monospace", fontWeight: 700 }}>{selected.priority.toUpperCase()}</span>}
                </div>
                {selected.area_of_operations && <div style={{ color: "#4b5563", fontSize: 12, display: "flex", alignItems: "center", gap: 4 }}><MdLocationOn size={12} /> {selected.area_of_operations}</div>}
              </div>
              <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 8 }}>
                <span style={{ fontSize: 10, padding: "4px 10px", background: STATUS_META[selected.status]?.bg ?? "#1f2937", color: STATUS_META[selected.status]?.color ?? "#9ca3af", fontFamily: "JetBrains Mono, monospace", letterSpacing: 1 }}>
                  {STATUS_META[selected.status]?.label ?? selected.status.toUpperCase()}
                </span>
                <div style={{ display: "flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
                  {canManage && <button onClick={() => setShowNotify(true)} style={{ padding: "4px 10px", background: "#d97706", border: "none", color: "#000", fontSize: 10, fontWeight: 700, cursor: "pointer", letterSpacing: 1, display: "flex", alignItems: "center", gap: 4 }}><MdOutlineRadio size={13} /> BRIEF</button>}
                  {isCoord && <button onClick={() => handleDelete(selected.id)} style={{ padding: "4px 10px", background: "#7f1d1d", border: "none", color: "#fca5a5", fontSize: 10, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}><MdOutlineDelete size={13} /> DEL</button>}
                  <button onClick={handleDownloadPackage} style={{ padding: "4px 10px", background: "#1f2937", border: "1px solid #374151", color: "#9ca3af", fontSize: 10, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}><MdOutlineDownload size={13} /> PKG</button>
                </div>
              </div>
            </div>

            {/* Lifecycle pipeline */}
            <LifecyclePipeline mission={selected} isCoord={isCoord} isLeader={isLeader} onTransition={handleLifecycleTransition} />

            {/* Stats */}
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(120px, 1fr))", gap: 8, marginBottom: 20 }}>
              {([["START", fmtDate(selected.start_date), MdOutlineSchedule], ["END", fmtDate(selected.end_date), MdOutlineSchedule], ["BRIEFING", fmtDateTime(selected.briefing_datetime), MdOutlineSchedule], ["TEAMS", `${selected.assignments.length}`, MdOutlinePeople], ["OBJECTIVES", `${selected.objectives.filter(o => o.is_completed).length}/${selected.objectives.length}`, MdOutlineFlag], ["INCIDENTS", `${incidents.length}`, MdOutlineWarning]] as [string, string, React.ElementType][]).map(([k, v, Icon]) => (
                <div key={k} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "8px 12px" }}>
                  <div style={{ ...secHdr, display: "flex", alignItems: "center", gap: 4 }}><Icon size={10} /> {k}</div>
                  <div style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{v}</div>
                </div>
              ))}
            </div>

            {/* Tabs */}
            <div style={{ display: "flex", borderBottom: "1px solid #0a1f0a", marginBottom: 20, gap: 0, overflowX: "auto" }}>
              {TABS.map(t => (
                <button key={t.key} onClick={() => setDetailTab(t.key)} style={{ padding: "8px 14px", fontSize: 10, cursor: "pointer", background: "none", border: "none", borderBottom: detailTab === t.key ? "2px solid #16a34a" : "2px solid transparent", color: detailTab === t.key ? "#22c55e" : "#4b5563", fontFamily: "JetBrains Mono, monospace", letterSpacing: 1, whiteSpace: "nowrap", flexShrink: 0 }}>
                  {t.label}{t.badge ? ` (${t.badge})` : ""}
                </button>
              ))}
            </div>

            {/* ── Overview ── */}
            {detailTab === "overview" && (() => {
              const sortedObjs = [...selected.objectives].sort((a, b) => (a.order_index ?? 0) - (b.order_index ?? 0));
              const currentObjIdx = sortedObjs.findIndex((o) => !o.is_completed);
              const currentObj = currentObjIdx >= 0 ? sortedObjs[currentObjIdx] : null;
              const isExecuting = ["active", "deploying", "extraction"].includes(selected.status);

              const parseObjTitle = (title: string) => {
                const isZone = title.startsWith("[ZONE]");
                const isReturn = title.includes("Return via");
                const isRoute = title.startsWith("[ROUTE]");
                const isFacility = title.startsWith("[FACILITY]");
                const display = title
                  .replace(/^\[ZONE\] Deploy to: |^\[ZONE\] /, "")
                  .replace(/^\[ROUTE\] Return via: |^\[ROUTE\] Follow: |^\[ROUTE\] /, "")
                  .replace(/^\[FACILITY\] Report to: |^\[FACILITY\] /, "");
                const typeLabel = isZone ? "ZONE" : isReturn ? "RETURN" : isRoute ? "ROUTE" : isFacility ? "FACILITY" : "";
                const typeColor = isZone ? "#a78bfa" : isRoute ? "#38bdf8" : isFacility ? "#f59e0b" : "#6b7280";
                const actionLabel = isZone ? "DEPLOY TO ZONE" : isReturn ? "RETURN VIA ROUTE" : isRoute ? "FOLLOW ROUTE" : isFacility ? "REPORT TO FACILITY" : "CURRENT OBJECTIVE";
                return { display, typeLabel, typeColor, actionLabel };
              };

              return (
                <>
                  {/* ── Current Objective (shown only when mission is executing) ── */}
                  {isExecuting && currentObj && (() => {
                    const { display, typeColor, actionLabel } = parseObjTitle(currentObj.title);
                    return (
                      <div style={{ background: "#030f03", border: `1px solid ${typeColor}30`, borderLeft: `3px solid ${typeColor}`, padding: "16px 18px", marginBottom: 14 }}>
                        <div style={{ fontSize: 9, color: typeColor, letterSpacing: 3, fontFamily: "JetBrains Mono, monospace", marginBottom: 8 }}>{actionLabel}</div>
                        <div style={{ color: "#f0fdf4", fontSize: 20, fontWeight: 700, marginBottom: 4 }}>{display}</div>
                        {currentObj.description && <div style={{ color: "#9ca3af", fontSize: 12, marginBottom: 12, lineHeight: 1.6 }}>{currentObj.description}</div>}
                        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                          {(isLeader || canManage) && (
                            <button
                              onClick={() => handleMarkObjectiveComplete(currentObj.id)}
                              style={{ padding: "7px 18px", background: "#16a34a", border: "none", color: "#000", fontSize: 11, fontWeight: 700, cursor: "pointer", letterSpacing: 1, display: "flex", alignItems: "center", gap: 4 }}
                            >
                              <MdOutlineCheckCircle size={13} /> MARK COMPLETE
                            </button>
                          )}
                          <div style={{ color: "#374151", fontSize: 10, fontFamily: "JetBrains Mono, monospace" }}>
                            Step {currentObjIdx + 1} of {sortedObjs.length} · {sortedObjs.filter((o) => o.is_completed).length} completed
                          </div>
                        </div>
                      </div>
                    );
                  })()}

                  {/* ── Objectives Timeline ── */}
                  {sortedObjs.length > 0 && (
                    <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 12 }}>
                      <div style={secHdr}>MISSION OBJECTIVES</div>
                      {sortedObjs.map((obj, i) => {
                        const isDone = obj.is_completed;
                        const isCurrent = i === currentObjIdx;
                        const { display, typeLabel, typeColor } = parseObjTitle(obj.title);
                        const dotColor = isDone ? "#16a34a" : isCurrent ? "#22c55e" : "#374151";
                        return (
                          <div key={obj.id}>
                            <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
                              <div style={{ width: 24, height: 24, borderRadius: "50%", border: `2px solid ${dotColor}`, background: isDone ? "#052e16" : isCurrent ? "#0a1f0a" : "transparent", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, color: dotColor, fontSize: 10, fontWeight: 700 }}>
                                {isDone ? <MdOutlineCheckCircle size={13} /> : isCurrent ? "➜" : i + 1}
                              </div>
                              <div style={{ flex: 1 }}>
                                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                                  <span style={{ fontSize: 12, color: isDone ? "#374151" : isCurrent ? "#f0fdf4" : "#6b7280", fontWeight: isCurrent ? 600 : 400, textDecoration: isDone ? "line-through" : "none" }}>{display}</span>
                                  {typeLabel && <span style={{ fontSize: 8, padding: "1px 5px", background: typeColor + "20", color: typeColor, fontFamily: "JetBrains Mono, monospace", borderRadius: 3 }}>{typeLabel}</span>}
                                </div>
                                {isDone && obj.completed_at && <div style={{ fontSize: 9, color: "#16a34a", fontFamily: "JetBrains Mono, monospace" }}>✓ {fmtDateTime(obj.completed_at)}</div>}
                                {isCurrent && <div style={{ fontSize: 9, color: "#22c55e", fontFamily: "JetBrains Mono, monospace" }}>▶ ACTIVE</div>}
                              </div>
                            </div>
                            {i < sortedObjs.length - 1 && (
                              <div style={{ marginLeft: 11, padding: "1px 0" }}>
                                <div style={{ width: 2, height: 14, background: isDone ? "#052e16" : "#1a2d1a", marginLeft: 1 }} />
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}

                  {/* ── Field Action Buttons (active missions) ── */}
                  {isExecuting && (isLeader || canManage) && (
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
                      <button onClick={() => setShowReportIncident(true)} style={{ padding: "6px 14px", background: "#7f1d1d", border: "1px solid #dc2626", color: "#fca5a5", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}>
                        <MdOutlineWarning size={13} /> REPORT INCIDENT
                      </button>
                      <button onClick={() => setShowCasualty(true)} style={{ padding: "6px 14px", background: "#1f2937", border: "1px solid #374151", color: "#9ca3af", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}>
                        <MdOutlinePersonOff size={13} /> CASUALTY REPORT
                      </button>
                      <button onClick={() => setShowSitrep(true)} style={{ padding: "6px 14px", background: "#0c1f2e", border: "1px solid #0e7490", color: "#38bdf8", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}>
                        <MdOutlineAssignment size={13} /> SUBMIT SITREP
                      </button>
                    </div>
                  )}

                  {/* ── Assigned Teams ── */}
                  {(() => {
                    const assignedTeamIds = new Set(selected.assignments.filter(a => a.team_id).map(a => a.team_id!));
                    const availableTeams = teams.filter(t => !assignedTeamIds.has(t.id));
                    return (
                      <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 12 }}>
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                          <div style={secHdr}>ASSIGNED TEAMS</div>
                          {canManage && availableTeams.length > 0 && (
                            <button onClick={() => setShowAddTeam(v => !v)} style={{ padding: "3px 10px", background: "#052e16", border: "1px solid #16a34a", color: "#22c55e", fontSize: 10, cursor: "pointer", fontFamily: "JetBrains Mono, monospace" }}>
                              + ADD TEAM
                            </button>
                          )}
                        </div>
                        {showAddTeam && canManage && (
                          <div style={{ marginBottom: 10, background: "#030903", border: "1px solid #0a1f0a", padding: 8 }}>
                            <div style={{ fontSize: 10, color: "#4b5563", fontFamily: "JetBrains Mono, monospace", marginBottom: 6 }}>SELECT TEAM TO ADD</div>
                            {availableTeams.map(t => (
                              <button key={t.id} onClick={() => handleAddTeam(t.id)} disabled={addingTeam} style={{ display: "block", width: "100%", textAlign: "left", padding: "5px 8px", background: "transparent", border: "none", color: "#d1fae5", fontSize: 12, cursor: "pointer", marginBottom: 2, fontFamily: "JetBrains Mono, monospace" }}>
                                {t.name}
                              </button>
                            ))}
                          </div>
                        )}
                        {selected.assignments.filter(a => a.team_id).length === 0 ? (
                          <div style={{ color: "#374151", fontSize: 11, fontFamily: "JetBrains Mono, monospace" }}>No teams assigned</div>
                        ) : (
                          selected.assignments.filter(a => a.team_id).map(a => {
                            const t = teams.find(t => t.id === a.team_id);
                            return (
                              <div key={a.id} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "5px 0", borderBottom: "1px solid #0a1f0a" }}>
                                <span style={{ color: "#d1fae5", fontSize: 12 }}>{t?.name ?? a.team_id?.slice(0, 8)}</span>
                                {canManage && (
                                  <button onClick={() => handleRemoveTeam(a.id!)} style={{ padding: "2px 8px", background: "#1f0a0a", border: "1px solid #7f1d1d", color: "#fca5a5", fontSize: 9, cursor: "pointer", fontFamily: "JetBrains Mono, monospace" }}>
                                    REMOVE
                                  </button>
                                )}
                              </div>
                            );
                          })
                        )}
                      </div>
                    );
                  })()}

                  {selected.description && <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 12 }}><div style={secHdr}>DESCRIPTION</div><div style={{ color: "#9ca3af", fontSize: 12, lineHeight: 1.6 }}>{selected.description}</div></div>}
                  {selected.supporting_assets && <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 12 }}><div style={secHdr}>SUPPORTING ASSETS</div><div style={{ color: "#9ca3af", fontSize: 12, lineHeight: 1.6 }}>{selected.supporting_assets}</div></div>}
                  {selected.briefing_notes && <div style={{ background: "#030903", border: "1px solid #1a2d1a", padding: "12px 14px", marginBottom: 12 }}><div style={{ ...secHdr, color: "#16a34a" }}>BRIEFING NOTES</div><pre style={{ color: "#d1fae5", fontSize: 12, lineHeight: 1.7, fontFamily: "JetBrains Mono, monospace", whiteSpace: "pre-wrap", margin: 0 }}>{selected.briefing_notes}</pre></div>}
                </>
              );
            })()}

            {/* ── Incidents ── */}
            {detailTab === "incidents" && (
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                  <div style={{ display: "flex", gap: 6 }}>
                    {(["all","incident","contact","intelligence"] as const).map(cat => (
                      <button key={cat} onClick={() => setIncidentFilter(cat as ReportCategory | "all")} style={{ padding: "4px 10px", fontSize: 10, cursor: "pointer", border: "none", background: incidentFilter === cat ? "#0a1f0a" : "transparent", color: incidentFilter === cat ? "#22c55e" : "#4b5563", fontFamily: "JetBrains Mono, monospace", borderBottom: incidentFilter === cat ? "1px solid #16a34a" : "1px solid transparent" }}>
                        {cat.toUpperCase()}
                      </button>
                    ))}
                  </div>
                  <button onClick={() => setShowReportIncident(true)} style={{ padding: "5px 12px", background: "#16a34a", border: "none", color: "#000", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}><MdOutlineAdd size={13} /> REPORT</button>
                </div>
                {incidents.filter(i => incidentFilter === "all" || i.report_category === incidentFilter).length === 0
                  ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No incidents</div>
                  : incidents.filter(i => incidentFilter === "all" || i.report_category === incidentFilter).map(inc => (
                    <div key={inc.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 8, display: "flex", gap: 12, alignItems: "flex-start" }}>
                      <div style={{ width: 10, height: 10, borderRadius: "50%", background: SEVERITY_META[inc.severity]?.color ?? "#6b7280", marginTop: 4, flexShrink: 0 }} />
                      <div style={{ flex: 1 }}>
                        <div style={{ display: "flex", gap: 8, alignItems: "center", marginBottom: 4 }}>
                          <span style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{inc.title}</span>
                          {inc.report_category && inc.report_category !== "incident" && <span style={{ fontSize: 9, padding: "2px 6px", background: inc.report_category === "contact" ? "#7f1d1d" : "#1e3a5f", color: inc.report_category === "contact" ? "#fca5a5" : "#93c5fd", fontFamily: "JetBrains Mono, monospace" }}>{inc.report_category.toUpperCase()}</span>}
                          <span style={{ fontSize: 9, padding: "2px 6px", background: inc.status === "resolved" ? "#052e16" : "#1f2937", color: inc.status === "resolved" ? "#22c55e" : "#9ca3af", fontFamily: "JetBrains Mono, monospace", marginLeft: "auto" }}>{inc.status.toUpperCase()}</span>
                        </div>
                        {inc.description && <div style={{ color: "#6b7280", fontSize: 12, marginBottom: 4 }}>{inc.description}</div>}
                        {inc.contact_size && <div style={{ fontSize: 11, color: "#fca5a5", fontFamily: "JetBrains Mono, monospace" }}>Size: {inc.contact_size} · Activity: {inc.contact_activity}</div>}
                        <div style={{ color: "#374151", fontSize: 10, fontFamily: "JetBrains Mono, monospace" }}>{inc.incident_type.replace("_", " ")} · {fmtDateTime(inc.created_at)}</div>
                      </div>
                      {canManage && inc.status !== "resolved" && <button onClick={() => handleResolveIncident(inc.id)} style={{ padding: "3px 8px", background: "#052e16", border: "1px solid #16a34a", color: "#22c55e", fontSize: 10, cursor: "pointer", flexShrink: 0, display: "flex", alignItems: "center", gap: 3 }}><MdOutlineCheckCircle size={11} /> RESOLVE</button>}
                    </div>
                  ))
                }
              </div>
            )}

            {/* ── Evidence ── */}
            {detailTab === "evidence" && (
              <div>
                <div style={{ marginBottom: 12 }}><div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>Field Evidence</div><div style={{ color: "#4b5563", fontSize: 11, marginTop: 2 }}>Approve or reject submitted evidence.</div></div>
                {evidence.length === 0 ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No evidence submitted</div>
                  : evidence.map(ev => (
                    <div key={ev.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 8, display: "flex", gap: 12, alignItems: "center" }}>
                      <MdOutlineShield size={16} color="#4b5563" style={{ flexShrink: 0 }} />
                      <div style={{ flex: 1 }}><div style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600, marginBottom: 2 }}>{ev.title}</div><div style={{ color: "#4b5563", fontSize: 11, fontFamily: "JetBrains Mono, monospace" }}>{ev.evidence_type} · {fmtDateTime(ev.created_at)}</div></div>
                      <span style={{ fontSize: 9, padding: "2px 8px", fontFamily: "JetBrains Mono, monospace", background: ev.approval_status === "approved" ? "#052e16" : ev.approval_status === "rejected" ? "#7f1d1d" : "#1f2937", color: ev.approval_status === "approved" ? "#22c55e" : ev.approval_status === "rejected" ? "#fca5a5" : "#9ca3af" }}>{ev.approval_status.toUpperCase()}</span>
                      {canManage && ev.approval_status === "pending" && <div style={{ display: "flex", gap: 6 }}><button onClick={() => handleApproveEvidence(ev.id, "approve")} style={{ padding: "3px 8px", background: "#052e16", border: "1px solid #16a34a", color: "#22c55e", fontSize: 10, cursor: "pointer" }}>APPROVE</button><button onClick={() => handleApproveEvidence(ev.id, "reject")} style={{ padding: "3px 8px", background: "#7f1d1d", border: "1px solid #dc2626", color: "#fca5a5", fontSize: 10, cursor: "pointer" }}>REJECT</button></div>}
                    </div>
                  ))
                }
              </div>
            )}

            {/* ── Casualties ── */}
            {detailTab === "casualties" && (
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                  <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>Casualty Reports</div>
                  <button onClick={() => setShowCasualty(true)} style={{ padding: "5px 12px", background: "#dc2626", border: "none", color: "#fff", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}><MdOutlinePersonOff size={13} /> REPORT</button>
                </div>
                {casualties.length === 0 ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No casualties reported</div>
                  : casualties.map(c => {
                    const typeColor = c.casualty_type === "KIA" ? "#dc2626" : c.casualty_type === "WIA" ? "#f59e0b" : c.casualty_type === "captured" ? "#a78bfa" : "#3b82f6";
                    const typeBg = c.casualty_type === "KIA" ? "#7f1d1d" : c.casualty_type === "WIA" ? "#2d1a00" : c.casualty_type === "captured" ? "#1e1b4b" : "#1e3a5f";
                    return (
                      <div key={c.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 8, display: "flex", gap: 12, alignItems: "flex-start" }}>
                        <span style={{ fontSize: 9, padding: "4px 8px", background: typeBg, color: typeColor, fontFamily: "JetBrains Mono, monospace", fontWeight: 700, flexShrink: 0, marginTop: 2 }}>{c.casualty_type}</span>
                        <div style={{ flex: 1 }}><div style={{ color: "#d1fae5", fontSize: 12, marginBottom: 2 }}>{c.user_id ? (allUsers.find(u => u.id === c.user_id)?.full_name ?? "Unknown") : "Unknown Personnel"}</div>{c.notes && <div style={{ color: "#6b7280", fontSize: 12 }}>{c.notes}</div>}<div style={{ color: "#374151", fontSize: 10, fontFamily: "JetBrains Mono, monospace", marginTop: 4 }}>{fmtDateTime(c.created_at)}</div></div>
                      </div>
                    );
                  })
                }
              </div>
            )}

            {/* ── Acknowledgements ── */}
            {detailTab === "acknowledgements" && (
              <div>
                <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600, marginBottom: 12 }}>Acknowledgements</div>
                {acks.length === 0 ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No acknowledgement records</div>
                  : acks.map(ack => (
                    <div key={ack.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "10px 14px", marginBottom: 6, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                      <div><div style={{ color: "#d1fae5", fontSize: 12 }}>{ack.user_name}</div>{ack.acknowledged_at && <div style={{ color: "#374151", fontSize: 10, fontFamily: "JetBrains Mono, monospace" }}>{fmtDateTime(ack.acknowledged_at)}</div>}</div>
                      <span style={{ fontSize: 9, padding: "3px 8px", background: ack.status === "acknowledged" ? "#052e16" : "#1f2937", color: ack.status === "acknowledged" ? "#22c55e" : "#9ca3af", fontFamily: "JetBrains Mono, monospace" }}>{ack.status.toUpperCase()}</span>
                    </div>
                  ))
                }
              </div>
            )}

            {/* ── Attendance ── */}
            {detailTab === "attendance" && (
              <div>
                <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600, marginBottom: 12 }}>Briefing Attendance</div>
                {attendance.length === 0 ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No attendance records</div>
                  : attendance.map(rec => (
                    <div key={rec.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "10px 14px", marginBottom: 6, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                      <div style={{ color: "#d1fae5", fontSize: 12 }}>{rec.user_name}</div>
                      <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
                        {(canManage || isLeader) && (["present","absent","excused"] as const).map(s => (
                          <button key={s} onClick={() => handleMarkAttendance(rec.user_id, s)} style={{ padding: "3px 8px", fontSize: 10, cursor: "pointer", background: rec.status === s ? (s === "present" ? "#052e16" : s === "absent" ? "#7f1d1d" : "#2d1a00") : "#0a140a", border: `1px solid ${rec.status === s ? (s === "present" ? "#16a34a" : s === "absent" ? "#dc2626" : "#f59e0b") : "#1f2d1f"}`, color: rec.status === s ? (s === "present" ? "#22c55e" : s === "absent" ? "#fca5a5" : "#fbbf24") : "#4b5563" }}>
                            {s.toUpperCase()}
                          </button>
                        ))}
                        {!canManage && !isLeader && <span style={{ fontSize: 9, padding: "3px 8px", background: "#1f2937", color: "#9ca3af", fontFamily: "JetBrains Mono, monospace" }}>{rec.status.toUpperCase()}</span>}
                      </div>
                    </div>
                  ))
                }
              </div>
            )}

            {/* ── SITREPs ── */}
            {detailTab === "sitreps" && (
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                  <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>Situation Reports</div>
                  {(canManage || isLeader) && <button onClick={() => setShowSitrep(true)} style={{ padding: "5px 12px", background: "#0e7490", border: "none", color: "#fff", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}><MdOutlineAssignment size={13} /> SUBMIT SITREP</button>}
                </div>
                {sitreps.length === 0 ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No SITREPs submitted</div>
                  : sitreps.map(s => (
                    <div key={s.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 8 }}>
                      <div style={{ color: "#374151", fontSize: 9, fontFamily: "JetBrains Mono, monospace", marginBottom: 8 }}>{fmtDateTime(s.submitted_at)}</div>
                      {s.team_status && <div style={{ marginBottom: 6 }}><div style={secHdr}>TEAM STATUS</div><div style={{ color: "#d1fae5", fontSize: 12 }}>{s.team_status}</div></div>}
                      {s.objective_progress && <div style={{ marginBottom: 6 }}><div style={secHdr}>PROGRESS</div><div style={{ color: "#d1fae5", fontSize: 12 }}>{s.objective_progress}</div></div>}
                      {s.risks && <div style={{ marginBottom: 6 }}><div style={secHdr}>RISKS</div><div style={{ color: "#fbbf24", fontSize: 12 }}>{s.risks}</div></div>}
                      {s.requests && <div><div style={secHdr}>REQUESTS</div><div style={{ color: "#d1fae5", fontSize: 12 }}>{s.requests}</div></div>}
                    </div>
                  ))
                }
              </div>
            )}

            {/* ── Completion Report ── */}
            {detailTab === "completion" && (
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                  <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>Completion Report</div>
                  {(canManage || isLeader) && !completionReport && (selected.status === "active" || selected.status === "extraction") && (
                    <button onClick={() => setShowCompletion(true)} style={{ padding: "5px 12px", background: "#16a34a", border: "none", color: "#000", fontSize: 11, fontWeight: 700, cursor: "pointer" }}>REQUEST CLOSURE</button>
                  )}
                </div>
                {!completionReport ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No completion report submitted</div>
                  : (
                    <div style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "14px 16px" }}>
                      <div style={{ color: "#374151", fontSize: 9, fontFamily: "JetBrains Mono, monospace", marginBottom: 12 }}>Submitted {fmtDateTime(completionReport.submitted_at)}</div>
                      {([["OBJECTIVE SUMMARY", completionReport.objective_summary], ["PERSONNEL STATUS", completionReport.personnel_status], ["INCIDENT SUMMARY", completionReport.incident_summary], ["EVIDENCE SUMMARY", completionReport.evidence_summary], ["RECOMMENDATIONS", completionReport.recommendations]] as [string, string | undefined][]).filter(([, v]) => v).map(([k, v]) => (
                        <div key={k} style={{ marginBottom: 10 }}><div style={secHdr}>{k}</div><div style={{ color: "#d1fae5", fontSize: 12, lineHeight: 1.5 }}>{v}</div></div>
                      ))}
                      {completionReport.review_decision && (
                        <div style={{ marginTop: 12, padding: "10px 12px", background: completionReport.review_decision === "complete" ? "#052e16" : "#1f2937", border: `1px solid ${completionReport.review_decision === "complete" ? "#16a34a" : "#374151"}` }}>
                          <div style={secHdr}>COMMAND REVIEW</div>
                          <div style={{ color: completionReport.review_decision === "complete" ? "#22c55e" : "#9ca3af", fontSize: 12, fontWeight: 700 }}>{completionReport.review_decision === "complete" ? "ACCEPTED → DEBRIEF" : "RETURNED TO ACTIVE"}</div>
                          {completionReport.review_notes && <div style={{ color: "#6b7280", fontSize: 12, marginTop: 4 }}>{completionReport.review_notes}</div>}
                        </div>
                      )}
                      {isCoord && selected.status === "awaiting_review" && !completionReport.review_decision && (
                        <div style={{ marginTop: 14, display: "flex", gap: 8 }}>
                          <button onClick={() => handleLifecycleTransition("review_complete")} style={{ flex: 1, padding: 9, background: "#16a34a", border: "none", color: "#000", cursor: "pointer", fontWeight: 700, fontSize: 12 }}>ACCEPT → DEBRIEF</button>
                          <button onClick={() => handleLifecycleTransition("review_return")} style={{ flex: 1, padding: 9, background: "#1f2937", border: "1px solid #374151", color: "#9ca3af", cursor: "pointer", fontSize: 12 }}>RETURN TO ACTIVE</button>
                        </div>
                      )}
                    </div>
                  )
                }
              </div>
            )}

            {/* ── Debrief ── */}
            {detailTab === "debrief" && (
              <div>
                {/* Live debrief call CTA */}
                {(canManage || isLeader) && selected.status === "debrief" && (
                  <div style={{ background: "#1a0030", border: "1px solid #7c3aed", padding: "14px 16px", marginBottom: 16, display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
                    <div>
                      <div style={{ color: "#c084fc", fontSize: 9, fontFamily: "JetBrains Mono, monospace", letterSpacing: 2, marginBottom: 4 }}>POST-MISSION DEBRIEF</div>
                      <div style={{ color: "#f0fdf4", fontSize: 13, fontWeight: 600 }}>Start a live debrief call</div>
                      <div style={{ color: "#6b7280", fontSize: 11, marginTop: 2 }}>All assigned teams and their members will be invited automatically</div>
                    </div>
                    <button
                      onClick={() => handleLifecycleTransition("start_debrief")}
                      disabled={startingDebrief}
                      style={{ padding: "10px 18px", background: startingDebrief ? "#374151" : "#7c3aed", border: "none", color: "#fff", fontSize: 12, fontWeight: 700, cursor: startingDebrief ? "not-allowed" : "pointer", display: "flex", alignItems: "center", gap: 6, flexShrink: 0, opacity: startingDebrief ? 0.7 : 1 }}>
                      <MdOutlineVideoCall size={16} />
                      {startingDebrief ? "STARTING…" : "START DEBRIEF CALL"}
                    </button>
                  </div>
                )}
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                  <div style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>Debrief Records</div>
                  {(canManage || isLeader) && selected.status === "debrief" && <button onClick={() => setShowDebrief(true)} style={{ padding: "5px 12px", background: "#7c3aed", border: "none", color: "#fff", fontSize: 11, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", gap: 4 }}><MdOutlineGavel size={13} /> SUBMIT</button>}
                </div>
                {debriefs.length === 0 ? <div style={{ padding: "24px 0", textAlign: "center", color: "#374151", fontSize: 12 }}>No debrief records</div>
                  : debriefs.map(d => (
                    <div key={d.id} style={{ background: "#060d06", border: "1px solid #0a1f0a", padding: "12px 14px", marginBottom: 8 }}>
                      <div style={{ color: "#374151", fontSize: 9, fontFamily: "JetBrains Mono, monospace", marginBottom: 8 }}>{fmtDateTime(d.created_at)}</div>
                      {([["LESSONS LEARNED", d.lessons_learned], ["INCIDENT REVIEW", d.incident_review], ["EVIDENCE REVIEW", d.evidence_review], ["TEAM FEEDBACK", d.team_feedback]] as [string, string | undefined][]).filter(([, v]) => v).map(([k, v]) => (
                        <div key={k} style={{ marginBottom: 8 }}><div style={secHdr}>{k}</div><div style={{ color: "#d1fae5", fontSize: 12, lineHeight: 1.5 }}>{v}</div></div>
                      ))}
                    </div>
                  ))
                }
              </div>
            )}
          </div>
        )}
      </div>

      {/* Modals */}
      {showCreate && <CreateModal onClose={() => setShowCreate(false)} onCreated={load} teams={teams} zones={zones} routes={routes} facilities={facilities} />}
      {showNotify && selected && <NotifyModal mission={selected} onClose={() => setShowNotify(false)} />}
      {showReportIncident && selected && <ReportIncidentModal missionId={selected.id} onClose={() => setShowReportIncident(false)} onDone={() => loadMissionDetail(selected.id)} />}
      {showCasualty && selected && <CasualtyModal missionId={selected.id} users={allUsers} onClose={() => setShowCasualty(false)} onDone={() => loadMissionDetail(selected.id)} />}
      {showSitrep && selected && <SitrepModal missionId={selected.id} onClose={() => setShowSitrep(false)} onDone={() => loadTabData("sitreps", selected.id)} />}
      {showCompletion && selected && <CompletionReportModal missionId={selected.id} onClose={() => setShowCompletion(false)} onDone={() => { loadTabData("completion", selected.id); setSelected(s => s ? { ...s, status: "awaiting_review" } : s); setMissions(p => p.map(m => m.id === selected.id ? { ...m, status: "awaiting_review" } : m)); }} />}
      {showDebrief && selected && <DebriefModal missionId={selected.id} onClose={() => setShowDebrief(false)} onDone={() => loadTabData("debrief", selected.id)} />}
    </div>
  );
}
