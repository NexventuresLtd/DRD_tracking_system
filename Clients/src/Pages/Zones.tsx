import { useState, useEffect, useRef, useCallback } from "react";
import {
  MapContainer, TileLayer, Polygon, Circle, Rectangle,
  useMapEvents, Marker, Popup,
} from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { MdHexagon } from "react-icons/md";
import { zonesApi } from "../services/api";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";

// ── Types ────────────────────────────────────────────────────────────────────

interface Zone {
  id: string;
  name: string;
  description?: string;
  zone_type: string;
  shape: string;
  color: string;
  fill_color?: string;
  polygon_points?: { points: [number, number][] };
  center_lat?: number;
  center_lng?: number;
  radius?: number;
  is_circle: boolean;
  team_id?: string;
  assignment_status: string;
  is_active: boolean;
  created_at: string;
}

interface ZoneAssignment {
  id: string;
  zone_id: string;
  user_id: string;
  point_index?: number;
  point_lat: number;
  point_lon: number;
  label?: string;
  status: string;
  notes?: string;
  user?: { id: string; full_name: string; username: string; avatar_url?: string; role: string };
}

interface Team { id: string; name: string; }
interface TeamMember { id: string; full_name: string; username: string; avatar_url?: string; role: string; }

// ── Constants ────────────────────────────────────────────────────────────────

const SHAPE_OPTIONS = [
  { key: "polygon", label: "Polygon", icon: "P" },
  { key: "rectangle", label: "Rectangle", icon: "▭" },
  { key: "circle", label: "Circle", icon: "◯" },
];

const STATUS_COLORS: Record<string, string> = {
  draft: "#6b7280",
  assigned: "#3b82f6",
  active: "#22c55e",
  completed: "#9ca3af",
};

const ASSIGNMENT_STATUS_COLORS: Record<string, string> = {
  pending: "#6b7280",
  en_route: "#f59e0b",
  arrived: "#3b82f6",
  on_patrol: "#22c55e",
  completed: "#9ca3af",
};

const DEFAULT_CENTER: [number, number] = [-1.9403, 29.8739];

// ── Convex hull (Graham scan) ─────────────────────────────────────────────────
function convexHull(pts: [number, number][]): [number, number][] {
  if (pts.length < 3) return pts;
  const sorted = [...pts].sort((a, b) => a[0] !== b[0] ? a[0] - b[0] : a[1] - b[1]);
  const cross = (o: [number,number], a: [number,number], b: [number,number]) =>
    (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lower: [number,number][] = [];
  for (const p of sorted) {
    while (lower.length >= 2 && cross(lower[lower.length-2], lower[lower.length-1], p) <= 0) lower.pop();
    lower.push(p);
  }
  const upper: [number,number][] = [];
  for (let i = sorted.length - 1; i >= 0; i--) {
    const p = sorted[i];
    while (upper.length >= 2 && cross(upper[upper.length-2], upper[upper.length-1], p) <= 0) upper.pop();
    upper.push(p);
  }
  upper.pop(); lower.pop();
  return [...lower, ...upper];
}

// ── Drawing sub-component ────────────────────────────────────────────────────

function DrawingLayer({
  shape,
  drawingPoints,
  onPointAdd,
  circleDraft,
  onCircleDraft,
}: {
  shape: string;
  drawingPoints: [number, number][];
  onPointAdd: (pt: [number, number]) => void;
  circleDraft: { center: [number, number]; radius: number } | null;
  onCircleDraft: (draft: { center: [number, number]; radius: number } | null) => void;
}) {
  const [circleStep, setCircleStep] = useState<"center" | "edge">("center");
  const [circleCenter, setCircleCenter] = useState<[number, number] | null>(null);

  useMapEvents({
    click(e) {
      const pt: [number, number] = [e.latlng.lat, e.latlng.lng];
      if (shape === "polygon" || shape === "rectangle") {
        onPointAdd(pt);
      } else if (shape === "circle") {
        if (circleStep === "center") {
          setCircleCenter(pt);
          setCircleStep("edge");
          onCircleDraft({ center: pt, radius: 300 });
        } else if (circleCenter) {
          const r = L.latLng(circleCenter).distanceTo(L.latLng(pt));
          onCircleDraft({ center: circleCenter, radius: r });
          setCircleStep("center");
          setCircleCenter(null);
        }
      }
    },
    mousemove(e) {
      if (shape === "circle" && circleStep === "edge" && circleCenter) {
        const r = L.latLng(circleCenter).distanceTo(e.latlng);
        onCircleDraft({ center: circleCenter, radius: r });
      }
    },
  });

  return null;
}

// ── Member avatar icon ───────────────────────────────────────────────────────

function makeAvatarIcon(user: TeamMember, status: string) {
  const color = ASSIGNMENT_STATUS_COLORS[status] ?? "#6b7280";
  return L.divIcon({
    className: "",
    html: `<div style="width:36px;height:36px;border-radius:50%;border:3px solid ${color};overflow:hidden;background:#1a2e1a;display:flex;align-items:center;justify-content:center;">
      ${user.avatar_url
        ? `<img src="${user.avatar_url}" style="width:100%;height:100%;object-fit:cover;"/>`
        : `<span style="color:#22c55e;font-weight:700;font-size:13px;">${user.full_name.charAt(0)}</span>`
      }
    </div>`,
    iconSize: [36, 36],
    iconAnchor: [18, 18],
  });
}

// ── Main component ────────────────────────────────────────────────────────────

export default function ZonesPage() {
  const { user } = useAuthStore();
  const isManager = user?.role === "operations_coordinator" || user?.role === "planning_officer";
  const isLeader = user?.role === "team_leader" || isManager;

  const [zones, setZones] = useState<Zone[]>([]);
  const [teams, setTeams] = useState<Team[]>([]);
  const [teamMembers, setTeamMembers] = useState<TeamMember[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedZone, setSelectedZone] = useState<Zone | null>(null);
  const [assignments, setAssignments] = useState<ZoneAssignment[]>([]);
  const [loadingAssignments, setLoadingAssignments] = useState(false);

  // Drawing state
  const [drawMode, setDrawMode] = useState(false);
  const [drawShape, setDrawShape] = useState<"polygon" | "rectangle" | "circle">("polygon");
  const [drawPoints, setDrawPoints] = useState<[number, number][]>([]);
  const [circleDraft, setCircleDraft] = useState<{ center: [number, number]; radius: number } | null>(null);
  const [zoneName, setZoneName] = useState("");
  const [zoneDesc, setZoneDesc] = useState("");
  const [zoneColor, setZoneColor] = useState("#16a34a");
  const [zoneType, setZoneType] = useState("operational");
  const [saving, setSaving] = useState(false);

  // Assignment modal
  const [showAssign, setShowAssign] = useState(false);
  const [assignTeamId, setAssignTeamId] = useState("");
  const [memberAssignments, setMemberAssignments] = useState<Record<string, { lat: number; lon: number; label: string }>>({});

  // Patrol report
  const [showPatrol, setShowPatrol] = useState(false);
  const [patrolForm, setPatrolForm] = useState({
    report_type: "suspicious_activity",
    description: "",
    latitude: DEFAULT_CENTER[0],
    longitude: DEFAULT_CENTER[1],
    severity: "medium",
  });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [zRes, tRes] = await Promise.all([
        zonesApi.list(),
        api.get("/teams"),
      ]);
      setZones(zRes.data);
      setTeams(tRes.data);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const loadAssignments = async (zone: Zone) => {
    setSelectedZone(zone);
    setLoadingAssignments(true);
    try {
      const res = await zonesApi.getAssignments(zone.id);
      setAssignments(res.data);
    } finally {
      setLoadingAssignments(false);
    }
  };

  const loadTeamMembers = async (teamId: string) => {
    if (!teamId) { setTeamMembers([]); return; }
    const res = await api.get(`/teams/${teamId}/members`);
    setTeamMembers(res.data);
  };

  // ── Drawing ────────────────────────────────────────────────────────────────

  const addPoint = (pt: [number, number]) => {
    if (drawShape === "rectangle" && drawPoints.length >= 2) return;
    setDrawPoints((prev) => [...prev, pt]);
  };

  const clearDraw = () => {
    setDrawPoints([]);
    setCircleDraft(null);
  };

  const canSaveZone = () => {
    if (!zoneName.trim()) return false;
    if (drawShape === "circle") return circleDraft != null;
    if (drawShape === "rectangle") return drawPoints.length === 2;
    return drawPoints.length >= 3;
  };

  const saveZone = async () => {
    if (!canSaveZone()) return;
    setSaving(true);
    try {
      let payload: Record<string, unknown> = {
        name: zoneName,
        description: zoneDesc,
        zone_type: zoneType,
        shape: drawShape,
        color: zoneColor,
        fill_color: zoneColor + "33",
      };

      if (drawShape === "circle" && circleDraft) {
        payload = { ...payload, center_lat: circleDraft.center[0], center_lng: circleDraft.center[1], radius: circleDraft.radius, is_circle: true };
      } else if (drawShape === "rectangle") {
        payload = { ...payload, polygon_points: { points: drawPoints } };
      } else {
        const hull = drawPoints.length >= 3 ? convexHull(drawPoints) : drawPoints;
        payload = { ...payload, polygon_points: { points: hull } };
      }

      await zonesApi.create(payload);
      clearDraw();
      setZoneName("");
      setZoneDesc("");
      setDrawMode(false);
      await load();
    } finally {
      setSaving(false);
    }
  };

  const deleteZone = async (id: string) => {
    if (!confirm("Delete this zone?")) return;
    await zonesApi.delete(id);
    if (selectedZone?.id === id) setSelectedZone(null);
    await load();
  };

  // ── Team assignment ────────────────────────────────────────────────────────

  const openAssignModal = async (zone: Zone) => {
    setSelectedZone(zone);
    setAssignTeamId(zone.team_id ?? "");
    if (zone.team_id) await loadTeamMembers(zone.team_id);
    const res = await zonesApi.getAssignments(zone.id);
    setAssignments(res.data);
    const init: Record<string, { lat: number; lon: number; label: string }> = {};
    for (const a of res.data) {
      init[a.user_id] = { lat: a.point_lat, lon: a.point_lon, label: a.label ?? "" };
    }
    setMemberAssignments(init);
    setShowAssign(true);
  };

  const saveAssignments = async () => {
    if (!selectedZone) return;
    setSaving(true);
    try {
      if (assignTeamId !== (selectedZone.team_id ?? "")) {
        await zonesApi.assignTeam(selectedZone.id, assignTeamId || null);
      }
      for (const [uid, data] of Object.entries(memberAssignments)) {
        if (data.lat && data.lon) {
          const points = selectedZone.polygon_points?.points ?? [];
          const idx = points.findIndex((p) => Math.abs(p[0] - data.lat) < 0.0001 && Math.abs(p[1] - data.lon) < 0.0001);
          await zonesApi.createAssignment(selectedZone.id, {
            user_id: uid,
            point_lat: data.lat,
            point_lon: data.lon,
            point_index: idx >= 0 ? idx : undefined,
            label: data.label || undefined,
          });
        }
      }
      setShowAssign(false);
      await load();
      await loadAssignments(selectedZone);
    } finally {
      setSaving(false);
    }
  };

  const removeAssignment = async (userId: string) => {
    if (!selectedZone) return;
    await zonesApi.removeAssignment(selectedZone.id, userId);
    const res = await zonesApi.getAssignments(selectedZone.id);
    setAssignments(res.data);
    const copy = { ...memberAssignments };
    delete copy[userId];
    setMemberAssignments(copy);
  };

  // ── Patrol report ──────────────────────────────────────────────────────────

  const submitPatrolReport = async () => {
    if (!selectedZone) return;
    await zonesApi.patrolReport(selectedZone.id, patrolForm);
    setShowPatrol(false);
    setPatrolForm({ report_type: "suspicious_activity", description: "", latitude: DEFAULT_CENTER[0], longitude: DEFAULT_CENTER[1], severity: "medium" });
  };

  // ── Polygon corners for assignment ─────────────────────────────────────────

  const zonePoints: [number, number][] = selectedZone?.polygon_points?.points ?? [];

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <div className="flex h-full overflow-hidden" style={{ background: "#060e06", color: "#e2f0e2" }}>
      {/* Left panel */}
      <div className="w-80 flex-shrink-0 flex flex-col border-r border-green-900/40 overflow-hidden">
        <div className="p-4 border-b border-green-900/40">
          <div className="flex items-center justify-between mb-3">
            <h1 className="font-bold text-green-400 tracking-widest text-sm uppercase">TACTICAL ZONES</h1>
            {isManager && (
              <button
                onClick={() => { setDrawMode(!drawMode); clearDraw(); }}
                className={`px-3 py-1 text-xs font-bold rounded tracking-wider transition-all ${drawMode ? "bg-red-800 text-red-200" : "bg-green-800/60 text-green-300 hover:bg-green-700/60"}`}
              >
                {drawMode ? "CANCEL" : "+ NEW ZONE"}
              </button>
            )}
          </div>
          {loading && <p className="text-green-700 text-xs">Loading zones…</p>}
        </div>

        {/* Draw form */}
        {drawMode && isManager && (
          <div className="p-3 border-b border-green-900/40 bg-green-900/10 space-y-2">
            <p className="text-green-500 text-xs uppercase font-bold tracking-widest mb-2">Draw Mode</p>
            <div className="flex gap-1">
              {SHAPE_OPTIONS.map((s) => (
                <button
                  key={s.key}
                  onClick={() => { setDrawShape(s.key as typeof drawShape); clearDraw(); }}
                  className={`flex-1 py-1.5 text-xs rounded font-bold transition-all ${drawShape === s.key ? "bg-green-700 text-white" : "bg-green-900/30 text-green-500 hover:bg-green-800/40"}`}
                >
                  {s.icon} {s.label}
                </button>
              ))}
            </div>
            <input
              value={zoneName}
              onChange={(e) => setZoneName(e.target.value)}
              placeholder="Zone name *"
              className="w-full px-3 py-2 rounded text-sm bg-black/40 border border-green-900/50 text-green-100 placeholder-green-800 focus:outline-none focus:border-green-600"
            />
            <input
              value={zoneDesc}
              onChange={(e) => setZoneDesc(e.target.value)}
              placeholder="Description (optional)"
              className="w-full px-3 py-2 rounded text-sm bg-black/40 border border-green-900/50 text-green-100 placeholder-green-800 focus:outline-none focus:border-green-600"
            />
            <div className="flex gap-2 items-center">
              <select
                value={zoneType}
                onChange={(e) => setZoneType(e.target.value)}
                className="flex-1 px-2 py-1.5 rounded text-xs bg-black/40 border border-green-900/50 text-green-100"
              >
                {["operational", "patrol", "exclusion", "support", "danger"].map((t) => (
                  <option key={t} value={t}>{t.toUpperCase()}</option>
                ))}
              </select>
              <label className="text-xs text-green-600">Color:</label>
              <input
                type="color"
                value={zoneColor}
                onChange={(e) => setZoneColor(e.target.value)}
                className="w-8 h-8 rounded cursor-pointer border-0 bg-transparent"
              />
            </div>
            <p className="text-green-700 text-xs">
              {drawShape === "circle"
                ? "Click to set center, then click edge to set radius"
                : drawShape === "rectangle"
                ? `Click 2 corners (${drawPoints.length}/2)`
                : `Click to add polygon points (${drawPoints.length} so far, need ≥3)`}
            </p>
            <div className="flex gap-2">
              <button
                onClick={saveZone}
                disabled={!canSaveZone() || saving}
                className="flex-1 py-1.5 text-xs font-bold rounded bg-green-700 text-white disabled:opacity-40 hover:bg-green-600 transition-colors"
              >
                {saving ? "SAVING…" : "SAVE ZONE"}
              </button>
              <button onClick={clearDraw} className="px-3 py-1.5 text-xs rounded bg-red-900/40 text-red-400 hover:bg-red-900/60">CLEAR</button>
            </div>
          </div>
        )}

        {/* Zone list */}
        <div className="flex-1 overflow-y-auto">
          {zones.length === 0 && !loading && (
            <p className="p-4 text-green-800 text-sm">No zones defined yet.</p>
          )}
          {zones.map((z) => (
            <div
              key={z.id}
              onClick={() => loadAssignments(z)}
              className={`p-3 border-b border-green-900/20 cursor-pointer transition-all hover:bg-green-900/10 ${selectedZone?.id === z.id ? "bg-green-900/20 border-l-2 border-l-green-500" : ""}`}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="w-3 h-3 rounded-sm flex-shrink-0" style={{ background: z.color }} />
                  <span className="text-sm font-semibold text-green-100">{z.name}</span>
                </div>
                <span
                  className="text-xs px-2 py-0.5 rounded font-bold uppercase"
                  style={{ background: STATUS_COLORS[z.assignment_status] + "22", color: STATUS_COLORS[z.assignment_status] }}
                >
                  {z.assignment_status}
                </span>
              </div>
              <div className="mt-1 flex gap-2 text-xs text-green-700">
                <span className="uppercase">{z.shape}</span>
                <span>·</span>
                <span className="uppercase">{z.zone_type}</span>
              </div>
              {isManager && (
                <div className="flex gap-1 mt-2">
                  <button
                    onClick={(e) => { e.stopPropagation(); openAssignModal(z); }}
                    className="px-2 py-0.5 text-xs rounded bg-blue-900/40 text-blue-400 hover:bg-blue-900/60"
                  >
                    Assign
                  </button>
                  <button
                    onClick={(e) => { e.stopPropagation(); deleteZone(z.id); }}
                    className="px-2 py-0.5 text-xs rounded bg-red-900/30 text-red-400 hover:bg-red-900/50"
                  >
                    Delete
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Map + right panel */}
      <div className="flex-1 flex flex-col overflow-hidden">
        <div className="flex-1 relative">
          <MapContainer
            center={DEFAULT_CENTER}
            zoom={10}
            style={{ height: "100%", width: "100%", background: "#0a0a0a" }}
            className="zone-map"
          >
            <TileLayer
              url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
              attribution="©OpenStreetMap ©CartoDB"
              maxZoom={19}
            />

            {drawMode && (
              <DrawingLayer
                shape={drawShape}
                drawingPoints={drawPoints}
                onPointAdd={addPoint}
                circleDraft={circleDraft}
                onCircleDraft={setCircleDraft}
              />
            )}

            {/* Draft polygon/rectangle */}
            {drawMode && drawPoints.length >= 2 && drawShape !== "circle" && (
              <Polygon
                positions={drawPoints}
                pathOptions={{ color: zoneColor, fillColor: zoneColor + "44", weight: 2, dashArray: "6,4" }}
              />
            )}

            {/* Draft circle */}
            {drawMode && circleDraft && drawShape === "circle" && (
              <Circle
                center={circleDraft.center}
                radius={circleDraft.radius}
                pathOptions={{ color: zoneColor, fillColor: zoneColor + "44", weight: 2, dashArray: "6,4" }}
              />
            )}

            {/* Saved zones */}
            {zones.map((z) => {
              const isSelected = selectedZone?.id === z.id;
              const pts = z.polygon_points?.points ?? [];
              if (z.is_circle && z.center_lat && z.center_lng && z.radius) {
                return (
                  <Circle
                    key={z.id}
                    center={[z.center_lat, z.center_lng]}
                    radius={z.radius}
                    pathOptions={{ color: z.color, fillColor: (z.fill_color ?? z.color + "33"), weight: isSelected ? 3 : 1.5, opacity: isSelected ? 1 : 0.7 }}
                    eventHandlers={{ click: () => loadAssignments(z) }}
                  />
                );
              }
              if (z.shape === "rectangle" && pts.length === 2) {
                return (
                  <Rectangle
                    key={z.id}
                    bounds={[pts[0], pts[1]]}
                    pathOptions={{ color: z.color, fillColor: (z.fill_color ?? z.color + "33"), weight: isSelected ? 3 : 1.5, opacity: isSelected ? 1 : 0.7 }}
                    eventHandlers={{ click: () => loadAssignments(z) }}
                  />
                );
              }
              if (pts.length >= 3) {
                return (
                  <Polygon
                    key={z.id}
                    positions={pts}
                    pathOptions={{ color: z.color, fillColor: (z.fill_color ?? z.color + "33"), weight: isSelected ? 3 : 1.5, opacity: isSelected ? 1 : 0.7 }}
                    eventHandlers={{ click: () => loadAssignments(z) }}
                  />
                );
              }
              return null;
            })}

            {/* Assignment markers */}
            {selectedZone && assignments.map((a) => {
              if (!a.user) return null;
              return (
                <Marker
                  key={a.id}
                  position={[a.point_lat, a.point_lon]}
                  icon={makeAvatarIcon(a.user, a.status)}
                >
                  <Popup>
                    <div style={{ minWidth: 140, color: "#111" }}>
                      <p className="font-bold">{a.user.full_name}</p>
                      <p className="text-xs">{a.label ?? `Point ${(a.point_index ?? 0) + 1}`}</p>
                      <p className="text-xs capitalize font-semibold" style={{ color: ASSIGNMENT_STATUS_COLORS[a.status] }}>
                        {a.status.replace("_", " ")}
                      </p>
                    </div>
                  </Popup>
                </Marker>
              );
            })}

            {/* Drawing point markers */}
            {drawMode && drawPoints.map((pt, i) => (
              <Marker
                key={i}
                position={pt}
                icon={L.divIcon({
                  className: "",
                  html: `<div style="width:10px;height:10px;background:${zoneColor};border:2px solid white;border-radius:50%;"></div>`,
                  iconSize: [10, 10],
                  iconAnchor: [5, 5],
                })}
              />
            ))}
          </MapContainer>
        </div>

        {/* Zone detail / assignments panel */}
        {selectedZone && !drawMode && (
          <div className="border-t border-green-900/40 bg-black/60" style={{ maxHeight: 240, overflowY: "auto" }}>
            <div className="p-3 flex items-center justify-between">
              <div>
                <h2 className="font-bold text-green-300 text-sm">{selectedZone.name}</h2>
                <p className="text-green-700 text-xs capitalize">{selectedZone.zone_type} · {selectedZone.shape}</p>
              </div>
              <div className="flex gap-2">
                {user?.role === "field_user" && (
                  <button
                    onClick={() => setShowPatrol(true)}
                    className="px-3 py-1 text-xs font-bold rounded bg-red-800/60 text-red-300 hover:bg-red-700/60 uppercase tracking-wider"
                  >
                    Patrol Report
                  </button>
                )}
                {isLeader && (
                  <button
                    onClick={() => openAssignModal(selectedZone)}
                    className="px-3 py-1 text-xs font-bold rounded bg-blue-800/60 text-blue-300 hover:bg-blue-700/60 uppercase tracking-wider"
                  >
                    Assign Members
                  </button>
                )}
              </div>
            </div>
            {loadingAssignments ? (
              <p className="px-3 pb-3 text-green-800 text-xs">Loading assignments…</p>
            ) : assignments.length === 0 ? (
              <p className="px-3 pb-3 text-green-800 text-xs">No member assignments yet.</p>
            ) : (
              <div className="px-3 pb-3 flex flex-wrap gap-2">
                {assignments.map((a) => (
                  <div
                    key={a.id}
                    className="flex items-center gap-2 px-2 py-1.5 rounded border border-green-900/30 bg-green-900/10"
                  >
                    <div className="w-6 h-6 rounded-full bg-green-900 flex items-center justify-center text-xs font-bold text-green-300 overflow-hidden">
                      {a.user?.avatar_url
                        ? <img src={a.user.avatar_url} className="w-full h-full object-cover" />
                        : a.user?.full_name?.charAt(0) ?? "?"}
                    </div>
                    <div>
                      <p className="text-xs font-semibold text-green-200">{a.user?.full_name ?? "Unknown"}</p>
                      <p className="text-xs" style={{ color: ASSIGNMENT_STATUS_COLORS[a.status] }}>{a.status.replace("_", " ")}</p>
                    </div>
                    <span className="text-xs text-green-700">{a.label}</span>
                    {isLeader && (
                      <button onClick={() => removeAssignment(a.user_id)} className="text-red-500 text-xs ml-1">✕</button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Assignment Modal */}
      {showAssign && selectedZone && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm">
          <div className="w-full max-w-lg mx-4 rounded-xl border border-green-900/50 overflow-hidden" style={{ background: "#0c150c" }}>
            <div className="p-4 border-b border-green-900/40 flex items-center justify-between">
              <h2 className="font-bold text-green-300 uppercase tracking-wider text-sm">Assign Zone: {selectedZone.name}</h2>
              <button onClick={() => setShowAssign(false)} className="text-green-700 hover:text-green-400">✕</button>
            </div>
            <div className="p-4 space-y-4 max-h-[70vh] overflow-y-auto">
              {/* Team picker */}
              <div>
                <label className="text-xs text-green-600 uppercase font-bold block mb-1">Assign to Team</label>
                <select
                  value={assignTeamId}
                  onChange={async (e) => { setAssignTeamId(e.target.value); await loadTeamMembers(e.target.value); }}
                  className="w-full px-3 py-2 rounded bg-black/40 border border-green-900/50 text-green-100 text-sm"
                >
                  <option value="">— No team —</option>
                  {teams.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
                </select>
              </div>

              {/* Member → Point assignments */}
              {teamMembers.length > 0 && (
                <div>
                  <label className="text-xs text-green-600 uppercase font-bold block mb-2">Assign Members to Points</label>
                  <div className="space-y-2">
                    {teamMembers.map((m) => {
                      const current = memberAssignments[m.id];
                      return (
                        <div key={m.id} className="flex items-center gap-2 p-2 rounded border border-green-900/30 bg-green-900/10">
                          <div className="w-8 h-8 rounded-full bg-green-900 flex items-center justify-center text-sm font-bold text-green-300 flex-shrink-0 overflow-hidden">
                            {m.avatar_url ? <img src={m.avatar_url} className="w-full h-full object-cover" /> : m.full_name.charAt(0)}
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-xs font-semibold text-green-200 truncate">{m.full_name}</p>
                            <p className="text-xs text-green-700">{m.role.replace("_", " ")}</p>
                          </div>
                          {zonePoints.length > 0 ? (
                            <select
                              value={current ? `${current.lat},${current.lon}` : ""}
                              onChange={(e) => {
                                if (!e.target.value) {
                                  const copy = { ...memberAssignments };
                                  delete copy[m.id];
                                  setMemberAssignments(copy);
                                  return;
                                }
                                const [lat, lon] = e.target.value.split(",").map(Number);
                                setMemberAssignments((prev) => ({
                                  ...prev,
                                  [m.id]: { lat, lon, label: current?.label ?? `Point ${zonePoints.findIndex((p) => Math.abs(p[0] - lat) < 0.0001) + 1}` },
                                }));
                              }}
                              className="px-2 py-1 rounded bg-black/40 border border-green-900/40 text-xs text-green-100"
                            >
                              <option value="">— Unassigned —</option>
                              {zonePoints.map((pt, i) => (
                                <option key={i} value={`${pt[0]},${pt[1]}`}>Point {i + 1} ({pt[0].toFixed(4)}, {pt[1].toFixed(4)})</option>
                              ))}
                            </select>
                          ) : (
                            <div className="flex gap-1">
                              <input
                                type="number"
                                step="0.0001"
                                placeholder="Lat"
                                value={current?.lat ?? ""}
                                onChange={(e) => setMemberAssignments((prev) => ({ ...prev, [m.id]: { ...prev[m.id], lat: parseFloat(e.target.value), lon: prev[m.id]?.lon ?? 0, label: prev[m.id]?.label ?? "" } }))}
                                className="w-20 px-2 py-1 rounded bg-black/40 border border-green-900/40 text-xs text-green-100"
                              />
                              <input
                                type="number"
                                step="0.0001"
                                placeholder="Lon"
                                value={current?.lon ?? ""}
                                onChange={(e) => setMemberAssignments((prev) => ({ ...prev, [m.id]: { ...prev[m.id], lon: parseFloat(e.target.value), lat: prev[m.id]?.lat ?? 0, label: prev[m.id]?.label ?? "" } }))}
                                className="w-20 px-2 py-1 rounded bg-black/40 border border-green-900/40 text-xs text-green-100"
                              />
                            </div>
                          )}
                          {current && (
                            <input
                              placeholder="Label (opt)"
                              value={current.label}
                              onChange={(e) => setMemberAssignments((prev) => ({ ...prev, [m.id]: { ...prev[m.id], label: e.target.value } }))}
                              className="w-24 px-2 py-1 rounded bg-black/40 border border-green-900/40 text-xs text-green-100"
                            />
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
            <div className="p-4 border-t border-green-900/40 flex gap-2 justify-end">
              <button onClick={() => setShowAssign(false)} className="px-4 py-2 rounded text-sm text-green-600 hover:text-green-400">Cancel</button>
              <button
                onClick={saveAssignments}
                disabled={saving}
                className="px-5 py-2 rounded text-sm font-bold bg-green-700 text-white hover:bg-green-600 disabled:opacity-40"
              >
                {saving ? "Saving…" : "Save Assignments"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Patrol Report Modal */}
      {showPatrol && selectedZone && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm">
          <div className="w-full max-w-md mx-4 rounded-xl border border-red-900/50 overflow-hidden" style={{ background: "#150808" }}>
            <div className="p-4 border-b border-red-900/40 flex items-center justify-between">
              <h2 className="font-bold text-red-400 uppercase tracking-wider text-sm">Patrol Report — {selectedZone.name}</h2>
              <button onClick={() => setShowPatrol(false)} className="text-red-700 hover:text-red-400">✕</button>
            </div>
            <div className="p-4 space-y-3">
              <div>
                <label className="text-xs text-red-600 uppercase font-bold block mb-1">Report Type</label>
                <select
                  value={patrolForm.report_type}
                  onChange={(e) => setPatrolForm((p) => ({ ...p, report_type: e.target.value }))}
                  className="w-full px-3 py-2 rounded bg-black/40 border border-red-900/50 text-red-100 text-sm"
                >
                  {["enemy_sighted", "suspicious_activity", "incident", "all_clear", "medical", "request_support"].map((t) => (
                    <option key={t} value={t}>{t.replace(/_/g, " ").toUpperCase()}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs text-red-600 uppercase font-bold block mb-1">Severity</label>
                <select
                  value={patrolForm.severity}
                  onChange={(e) => setPatrolForm((p) => ({ ...p, severity: e.target.value }))}
                  className="w-full px-3 py-2 rounded bg-black/40 border border-red-900/50 text-red-100 text-sm"
                >
                  {["low", "medium", "high", "critical"].map((s) => (
                    <option key={s} value={s}>{s.toUpperCase()}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs text-red-600 uppercase font-bold block mb-1">Description</label>
                <textarea
                  value={patrolForm.description}
                  onChange={(e) => setPatrolForm((p) => ({ ...p, description: e.target.value }))}
                  placeholder="Describe what you observed…"
                  rows={3}
                  className="w-full px-3 py-2 rounded bg-black/40 border border-red-900/50 text-red-100 text-sm placeholder-red-900 resize-none"
                />
              </div>
            </div>
            <div className="p-4 border-t border-red-900/40 flex gap-2 justify-end">
              <button onClick={() => setShowPatrol(false)} className="px-4 py-2 rounded text-sm text-red-700 hover:text-red-400">Cancel</button>
              <button
                onClick={submitPatrolReport}
                disabled={!patrolForm.description.trim()}
                className="px-5 py-2 rounded text-sm font-bold bg-red-700 text-white hover:bg-red-600 disabled:opacity-40"
              >
                SEND REPORT
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
