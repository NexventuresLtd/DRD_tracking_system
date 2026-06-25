import { useEffect, useRef, useState, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { MapContainer, TileLayer, Marker, Popup, useMap, Polygon, Circle, Rectangle, Polyline } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { locationApi, postsApi, zonesApi, poiApi, missionApi, routeApi } from "../services/api";
import { useAuthStore } from "../stores/authStore";
import type { LiveLocation } from "../types";
import { MdMyLocation, MdLayers, MdRefresh, MdClose, MdDomain, MdCropFree, MdAltRoute, MdFlag, MdSchedule } from "react-icons/md";

const FACILITY_CACHE_KEY = "drd_facilities_cache";
const THREAT_COLORS: Record<string, string> = {
  green: "#22c55e", amber: "#f59e0b", red: "#ef4444", black: "#111827",
};

delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png",
  iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
});

// ── Tile layer definitions ──────────────────────────────────────────────────
const TILE_LAYERS = [
  { id: "dark",      label: "DARK OPS",  preview: "#0a0a0a", url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", attribution: "© CARTO", maxZoom: 19 },
  { id: "satellite", label: "SATELLITE", preview: "#2d4a1e", url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", attribution: "© Esri", maxZoom: 19 },
  { id: "terrain",   label: "TERRAIN",   preview: "#4a6741", url: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png", attribution: "© OpenTopoMap", maxZoom: 17 },
  { id: "street",    label: "STREET",    preview: "#1a2a3a", url: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", attribution: "© OpenStreetMap", maxZoom: 19 },
  { id: "topo",      label: "TOPO",      preview: "#3a4a2a", url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}", attribution: "© Esri", maxZoom: 19 },
  { id: "hybrid",    label: "HYBRID",    preview: "#1a3a2a", url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}", attribution: "© Esri", maxZoom: 19 },
] as const;
type TileId = (typeof TILE_LAYERS)[number]["id"];

const STATUS_COLORS: Record<string, string> = {
  active: "#22c55e", stale: "#f59e0b", offline: "#6b7280",
};

const FACILITY_META: Record<string, { icon: string; color: string }> = {
  forward_operating_base: { icon: "⬡", color: "#ef4444" },
  main_operating_base:    { icon: "★", color: "#dc2626" },
  combat_outpost:         { icon: "⬟", color: "#f97316" },
  checkpoint:             { icon: "⬢", color: "#eab308" },
  logistics_depot:        { icon: "▣", color: "#84cc16" },
  medical_center:         { icon: "✚", color: "#22c55e" },
  command_center:         { icon: "◈", color: "#14b8a6" },
  communications_hub:     { icon: "◎", color: "#06b6d4" },
  armory:                 { icon: "⚙", color: "#3b82f6" },
  training_facility:      { icon: "◇", color: "#6366f1" },
  detention_center:       { icon: "⊡", color: "#8b5cf6" },
  airfield:               { icon: "✈", color: "#a855f7" },
  naval_facility:         { icon: "⚓", color: "#ec4899" },
  office:                 { icon: "▦", color: "#6b7280" },
  border_post:            { icon: "⬛", color: "#78716c" },
  safe_house:             { icon: "⌂", color: "#059669" },
  intelligence_post:      { icon: "◉", color: "#7c3aed" },
  barracks:               { icon: "⊞", color: "#374151" },
  supply_point:           { icon: "◫", color: "#b45309" },
  other:                  { icon: "◌", color: "#4b5563" },
};

const PRIORITY_COLORS: Record<string, string> = {
  critical: "#dc2626", high: "#f59e0b", medium: "#3b82f6", low: "#22c55e",
};

const ACTIVE_MISSION_STATUSES = new Set([
  "approved","assigned","pending_acknowledgement","briefing",
  "active","deploying","extraction","awaiting_review","debrief",
]);

// ── Coordinate utilities ─────────────────────────────────────────────────────
function toDMS(deg: number, isLat: boolean): string {
  const dir = isLat ? (deg >= 0 ? "N" : "S") : (deg >= 0 ? "E" : "W");
  const abs = Math.abs(deg);
  const d = Math.floor(abs);
  const mFull = (abs - d) * 60;
  const m = Math.floor(mFull);
  const s = ((mFull - m) * 60).toFixed(1);
  return `${d}°${String(m).padStart(2, "0")}'${s.padStart(4, "0")}"${dir}`;
}

function toMGRS(lat: number, lon: number): string {
  if (lat < -80 || lat > 84) return "OUT OF RANGE";
  let zn = Math.floor((lon + 180) / 6) + 1;
  if (lat >= 56 && lat < 64 && lon >= 3 && lon < 12) zn = 32;
  if (lat >= 72 && lat < 84) {
    if (lon >= 0 && lon < 9) zn = 31;
    else if (lon >= 9 && lon < 21) zn = 33;
    else if (lon >= 21 && lon < 33) zn = 35;
    else if (lon >= 33 && lon < 42) zn = 37;
  }
  const ZL = "CDEFGHJKLMNPQRSTUVWX"[Math.min(Math.floor((lat + 80) / 8), 19)];
  const a = 6378137, f = 1 / 298.257223563;
  const b = a * (1 - f), e2 = 1 - (b * b) / (a * a);
  const k0 = 0.9996, lon0 = ((zn - 1) * 6 - 180 + 3) * Math.PI / 180;
  const latr = lat * Math.PI / 180, lonr = lon * Math.PI / 180;
  const N = a / Math.sqrt(1 - e2 * Math.sin(latr) ** 2);
  const T = Math.tan(latr) ** 2, C = (e2 / (1 - e2)) * Math.cos(latr) ** 2;
  const A = Math.cos(latr) * (lonr - lon0);
  const e4 = e2 * e2, e6 = e4 * e2;
  const M = a * ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * latr
    - (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * Math.sin(2 * latr)
    + (15 * e4 / 256 + 45 * e6 / 1024) * Math.sin(4 * latr)
    - (35 * e6 / 3072) * Math.sin(6 * latr));
  const x = k0 * N * (A + (1 - T + C) * A ** 3 / 6 + (5 - 18 * T + T * T + 72 * C - 58 * (e2 / (1 - e2))) * A ** 5 / 120) + 500000;
  let y = k0 * (M + N * Math.tan(latr) * (A ** 2 / 2 + (5 - T + 9 * C + 4 * C * C) * A ** 4 / 24 + (61 - 58 * T + T * T + 600 * C - 330 * (e2 / (1 - e2))) * A ** 6 / 720));
  if (lat < 0) y += 10000000;
  const set = (zn - 1) % 6;
  const colS = ["ABCDEFGH", "JKLMNPQR", "STUVWXYZ"][set % 3];
  const rowS = ["ABCDEFGHJKLMNPQRSTUV", "FGHJKLMNPQRSTUVABCDE"][set % 2];
  const col = colS[Math.floor(x / 100000) - 1] ?? "?";
  const row = rowS[Math.floor(y / 100000) % 20] ?? "?";
  const ex = String(Math.round(x % 100000)).padStart(5, "0");
  const nx = String(Math.round(y % 100000)).padStart(5, "0");
  return `${zn}${ZL} ${col}${row} ${ex} ${nx}`;
}

// ── GPS coordinate block (used in all popups) ────────────────────────────────
function GpsBlock({ lat, lng, speed, heading }: { lat: number; lng: number; speed?: number; heading?: number }) {
  const mono: React.CSSProperties = { fontFamily: "monospace", color: "#6ee7b7", fontSize: 10 };
  const label: React.CSSProperties = { color: "#4b5563", fontSize: 9, letterSpacing: 1, fontFamily: "'JetBrains Mono', monospace", minWidth: 38 };
  const row: React.CSSProperties = { display: "flex", gap: 8, alignItems: "flex-start", marginBottom: 2 };
  return (
    <div style={{ background: "#020802", border: "1px solid #0a1f0a", padding: "8px 10px", marginTop: 8 }}>
      <div style={row}>
        <span style={label}>GPS</span>
        <span style={mono}>{lat.toFixed(5)}, {lng.toFixed(5)}</span>
      </div>
      <div style={row}>
        <span style={label}>DMS</span>
        <span style={mono}>{toDMS(lat, true)} {toDMS(lng, false)}</span>
      </div>
      <div style={row}>
        <span style={label}>MGRS</span>
        <span style={mono}>{toMGRS(lat, lng)}</span>
      </div>
      {(speed != null || heading != null) && (
        <div style={{ display: "flex", gap: 12, marginTop: 4 }}>
          {speed != null && (
            <span style={{ color: "#374151", fontSize: 9, fontFamily: "'JetBrains Mono', monospace" }}>
              SPD <span style={{ color: "#9ca3af" }}>{(speed * 3.6).toFixed(1)} km/h</span>
            </span>
          )}
          {heading != null && (
            <span style={{ color: "#374151", fontSize: 9, fontFamily: "'JetBrains Mono', monospace" }}>
              HDG <span style={{ color: "#9ca3af" }}>{heading.toFixed(0)}°</span>
            </span>
          )}
        </div>
      )}
    </div>
  );
}

// ── Time filter helper ────────────────────────────────────────────────────────
type TimeFilter = "today" | "week" | "month" | "all";
function filterByTime<T extends { created_at?: string }>(items: T[], filter: TimeFilter): T[] {
  if (filter === "all") return items;
  const now = new Date();
  const cutoff =
    filter === "today" ? new Date(now.getFullYear(), now.getMonth(), now.getDate()) :
    filter === "week"  ? new Date(now.getTime() - 7 * 86400000) :
                         new Date(now.getTime() - 30 * 86400000);
  return items.filter((i) => !i.created_at || new Date(i.created_at) >= cutoff);
}

// ── Mission progress helper ───────────────────────────────────────────────────
function missionProgress(mission: any): { done: number; total: number; pct: number; currentObj: any | null } {
  const objs: any[] = (mission.objectives ?? []).slice().sort((a: any, b: any) =>
    (a.order_index ?? 0) - (b.order_index ?? 0));
  const done = objs.filter((o) => o.is_completed).length;
  const total = objs.length;
  const currentObj = objs.find((o) => !o.is_completed) ?? null;
  return { done, total, pct: total > 0 ? done / total : 0, currentObj };
}

function cleanObjTitle(title: string): string {
  return title.replace(/^\[(ZONE|ROUTE|FACILITY)\]\s*(\w[\w\s]*:\s*)?/, "").trim();
}

// ── Marker / facility icons ──────────────────────────────────────────────────
function makeFacilityIcon(type: string, threatLevel?: string, missionHighlight = false) {
  const meta = FACILITY_META[type] || FACILITY_META.other;
  const threat = threatLevel ?? "green";
  const threatColor = THREAT_COLORS[threat] ?? "#22c55e";
  const threatBadge = threat !== "green"
    ? `<div style="position:absolute;top:-4px;right:-4px;width:10px;height:10px;border-radius:50%;background:${threatColor};border:1px solid #000;"></div>`
    : "";
  const size = missionHighlight ? 38 : 32;
  const borderW = missionHighlight ? "3px" : "2px";
  const glow = missionHighlight ? `0 0 14px ${meta.color}cc` : `0 0 8px ${threatColor}55`;
  return L.divIcon({
    className: "",
    html: `<div style="position:relative;width:${size}px;height:${size}px;background:${meta.color}33;border:${borderW} solid ${missionHighlight ? meta.color : threatColor};display:flex;align-items:center;justify-content:center;font-size:${missionHighlight ? 16 : 14}px;color:${meta.color};box-shadow:${glow};">${meta.icon}${threatBadge}</div>`,
    iconSize: [size, size], iconAnchor: [size / 2, size / 2],
  });
}

function makeIcon(color: string, isMe: boolean, avatarUrl?: string, ini?: string) {
  const size = isMe ? 40 : 34;
  const inner = avatarUrl
    ? `<img src="${avatarUrl}" style="width:100%;height:100%;object-fit:cover;border-radius:50%;" onerror="this.style.display='none';this.nextSibling.style.display='flex';" /><span style="display:none;width:100%;height:100%;align-items:center;justify-content:center;font-size:${size * 0.35}px;font-weight:700;color:#fff;">${ini ?? "?"}</span>`
    : `<span style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;font-size:${size * 0.35}px;font-weight:700;color:#fff;">${ini ?? "?"}</span>`;
  return L.divIcon({
    className: "",
    html: `<div style="position:relative;width:${size}px;height:${size}px;background:${color}cc;border:${isMe ? 3 : 2}px solid ${isMe ? "#fff" : color};border-radius:50%;overflow:hidden;box-shadow:0 0 ${isMe ? 12 : 7}px ${color}90;display:flex;align-items:center;justify-content:center;">${inner}${isMe ? `<div style="position:absolute;inset:-7px;border-radius:50%;border:2px solid ${color}55;animation:ping 1.5s cubic-bezier(0,0,.2,1) infinite;pointer-events:none;"></div>` : ""}</div>`,
    iconSize: [size, size], iconAnchor: [size / 2, size / 2],
  });
}

// ── Inner map components ─────────────────────────────────────────────────────
function FitBoundsButton({ locations }: { locations: LiveLocation[] }) {
  const map = useMap();
  if (!locations.length) return null;
  return (
    <button
      onClick={() => map.fitBounds(L.latLngBounds(locations.map((l) => [l.latitude, l.longitude])), { padding: [60, 60] })}
      title="Fit all markers"
      style={{ position: "absolute", top: 12, right: 12, zIndex: 1000, background: "#0a140a", border: "1px solid #16a34a", color: "#22c55e", padding: "7px", cursor: "pointer", display: "flex", alignItems: "center" }}
    >
      <MdMyLocation size={18} />
    </button>
  );
}

function ActiveTileLayer({ tileId }: { tileId: TileId }) {
  const layer = TILE_LAYERS.find((t) => t.id === tileId)!;
  return <TileLayer key={tileId} url={layer.url} attribution={layer.attribution} maxZoom={layer.maxZoom} />;
}

function ZoomButtons() {
  const map = useMap();
  const btn: React.CSSProperties = { display: "block", width: 30, height: 30, background: "#0a140a", border: "1px solid #152015", color: "#22c55e", cursor: "pointer", fontSize: 18, fontFamily: "'JetBrains Mono', monospace", lineHeight: "28px", textAlign: "center" };
  return (
    <div style={{ position: "absolute", bottom: 12, right: 12, zIndex: 1000, display: "flex", flexDirection: "column", gap: 2 }}>
      <button style={btn} onClick={() => map.zoomIn()}>+</button>
      <button style={btn} onClick={() => map.zoomOut()}>−</button>
    </div>
  );
}

const ROLE_LABELS: Record<string, string> = {
  operations_coordinator: "OPS COORDINATOR",
  planning_officer: "PLANNING OFFICER",
  team_leader: "TEAM LEADER",
  field_user: "FIELD USER",
};

function initials(name?: string, username?: string): string {
  if (name) {
    const parts = name.trim().split(/\s+/);
    return parts.length >= 2 ? (parts[0][0] + parts[1][0]).toUpperCase() : parts[0].substring(0, 2).toUpperCase();
  }
  return (username ?? "?").substring(0, 2).toUpperCase();
}

// ── Toolbar chip ─────────────────────────────────────────────────────────────
function Chip({ label, active, onClick, color = "#22c55e" }: { label: string; active: boolean; onClick: () => void; color?: string }) {
  return (
    <button
      onClick={onClick}
      style={{
        background: active ? color + "22" : "#0a0f0a",
        border: `1px solid ${active ? color : "#1a2a1a"}`,
        color: active ? color : "#4b5563",
        padding: "4px 10px", cursor: "pointer",
        fontFamily: "'JetBrains Mono', monospace", fontSize: 9, letterSpacing: 1,
        whiteSpace: "nowrap",
      }}
    >
      {label}
    </button>
  );
}

// ── Main component ──────────────────────────────────────────────────────────
export default function LiveMap() {
  const { user } = useAuthStore();
  const navigate = useNavigate();

  // Base layer state
  const [locations, setLocations] = useState<LiveLocation[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTile, setActiveTile] = useState<TileId>("dark");
  const [showLayers, setShowLayers] = useState(false);
  const [facilities, setFacilities] = useState<any[]>([]);
  const [showFacilities, setShowFacilities] = useState(true);
  const [zones, setZones] = useState<any[]>([]);
  const [showZones, setShowZones] = useState(true);
  const [pois, setPois] = useState<any[]>([]);
  const [showPois, setShowPois] = useState(true);
  const [routes, setRoutes] = useState<any[]>([]);
  const [showRoutes, setShowRoutes] = useState(true);
  const [routingFacilities, setRoutingFacilities] = useState<any[]>([]);
  const [showRouting, setShowRouting] = useState(false);
  const [routingMode, setRoutingMode] = useState<"straight" | "road">("straight");
  const [roadRoutePoints, setRoadRoutePoints] = useState<[number, number][]>([]);
  const [fetchingRoute, setFetchingRoute] = useState(false);
  const [showRoutingMenu, setShowRoutingMenu] = useState(false);

  // Filters
  const [timeFilter, setTimeFilter] = useState<TimeFilter>("today");

  // Mission filter state
  const [missions, setMissions] = useState<any[]>([]);
  const [selectedMissionId, setSelectedMissionId] = useState<string | null>(null);
  const [missionResources, setMissionResources] = useState<{ zones: string[]; routes: string[]; facilities: string[] }>({ zones: [], routes: [], facilities: [] });
  const [showMissionPanel, setShowMissionPanel] = useState(false);
  const [loadingMissions, setLoadingMissions] = useState(false);

  const wsRef = useRef<WebSocket | null>(null);
  const eventsWsRef = useRef<WebSocket | null>(null);

  // ── Data loaders ────────────────────────────────────────────────────────────
  const load = () => {
    locationApi.getLive()
      .then(({ data }) => setLocations(data))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  const loadFacilities = useCallback(() => {
    const cached = localStorage.getItem(FACILITY_CACHE_KEY);
    if (cached && facilities.length === 0) {
      try { setFacilities(JSON.parse(cached)); } catch { /* ignore */ }
    }
    postsApi.mapPosts()
      .then(({ data }) => {
        setFacilities(data);
        try { localStorage.setItem(FACILITY_CACHE_KEY, JSON.stringify(data)); } catch { /* ignore */ }
      })
      .catch(() => {});
  }, []);

  const loadZones = useCallback(() => {
    zonesApi.list().then(({ data }) => setZones(data)).catch(() => {});
  }, []);

  const loadPois = useCallback(() => {
    poiApi.list().then(({ data }) => setPois(data)).catch(() => {});
  }, []);

  const loadRoutes = useCallback(() => {
    routeApi.list().then(({ data }) => setRoutes(data)).catch(() => {});
  }, []);

  const loadMissions = useCallback(() => {
    setLoadingMissions(true);
    missionApi.list({ my_missions: true })
      .then(({ data }) => {
        const list = Array.isArray(data) ? data : (data as any).data ?? [];
        // Sort: active first
        list.sort((a: any, b: any) => {
          const aActive = ACTIVE_MISSION_STATUSES.has(a.status) ? 0 : 1;
          const bActive = ACTIVE_MISSION_STATUSES.has(b.status) ? 0 : 1;
          return aActive - bActive;
        });
        setMissions(list);
      })
      .catch(() => {})
      .finally(() => setLoadingMissions(false));
  }, []);

  // When selectedMission changes, load its resources to know which zones/routes/facilities belong to it
  useEffect(() => {
    if (!selectedMissionId) {
      setMissionResources({ zones: [], routes: [], facilities: [] });
      return;
    }
    missionApi.getResources(selectedMissionId)
      .then(({ data }) => {
        setMissionResources({
          zones:      (data.zones      ?? []).map((z: any) => z.id as string),
          routes:     (data.routes     ?? []).map((r: any) => r.id as string),
          facilities: (data.facilities ?? []).map((f: any) => f.id as string),
        });
      })
      .catch(() => {});
  }, [selectedMissionId]);

  useEffect(() => {
    load();
    loadFacilities();
    loadZones();
    loadPois();
    loadRoutes();
    loadMissions();
    const interval         = setInterval(load, 10000);
    const facilityInterval = setInterval(loadFacilities, 60000);
    const zoneInterval     = setInterval(loadZones, 30000);
    const missionInterval  = setInterval(loadMissions, 30000);

    const token = localStorage.getItem("access_token");
    if (token && user) {
      const apiBase = import.meta.env.VITE_API_URL || "http://localhost:1104";
      const wsUrl = apiBase.replace(/^http/, "ws");
      const ws = new WebSocket(`${wsUrl}/ws/location/${user.id}?token=${token}`);
      wsRef.current = ws;
      ws.onmessage = (e) => {
        const msg = JSON.parse(e.data);
        if (msg.type === "location_update") {
          setLocations((prev) => {
            const idx = prev.findIndex((l) => l.user_id === msg.user_id);
            const updated = { ...msg, latitude: msg.lat ?? msg.latitude, longitude: msg.lng ?? msg.longitude };
            if (idx >= 0) { const next = [...prev]; next[idx] = updated; return next; }
            return [...prev, updated];
          });
        }
      };

      const eventsWs = new WebSocket(`${wsUrl}/ws/events?token=${token}`);
      eventsWsRef.current = eventsWs;
      eventsWs.onmessage = (e) => {
        const msg = JSON.parse(e.data);
        if (msg.type === "poi_created")  setPois((prev) => [...prev, msg.poi]);
        if (msg.type === "poi_updated")  setPois((prev) => prev.map((p) => p.id === msg.poi.id ? msg.poi : p));
        if (msg.type === "poi_deleted")  setPois((prev) => prev.filter((p) => p.id !== msg.poi_id));
        if (msg.type === "mission_updated" || msg.type === "objective_completed") loadMissions();
      };
    }

    return () => {
      clearInterval(interval); clearInterval(facilityInterval);
      clearInterval(zoneInterval); clearInterval(missionInterval);
      wsRef.current?.close(); eventsWsRef.current?.close();
    };
  }, [user, loadFacilities, loadZones, loadPois, loadRoutes, loadMissions]);

  // ── Derived data ─────────────────────────────────────────────────────────────
  const selectedMission = missions.find((m) => m.id === selectedMissionId) ?? null;

  // Zones, routes, facilities, user locations, and markers are ALWAYS shown in
  // full — past and present — regardless of time or mission filter.
  // Mission-linked resource IDs are kept only for visual highlighting (border
  // colour) not for hiding unlinked items.
  const missionZoneIds      = new Set(missionResources.zones);
  const missionRouteIds     = new Set(missionResources.routes);
  const missionFacilityIds  = new Set(missionResources.facilities);

  // These are always the complete arrays — never filtered away.
  const filteredZones      = zones;
  const filteredRoutes     = routes;
  const filteredFacilities = facilities;
  const filteredPois       = pois;           // all markers, all time

  // Time + mission filters only control which missions appear in the legend panel.
  // Completed missions only appear when "ALL TIME" filter is selected.
  const legendMissions = missions.filter((m) => {
    const isActive = ACTIVE_MISSION_STATUSES.has(m.status);
    const isCompleted = m.status === "completed";
    if (!isActive && !(timeFilter === "all" && isCompleted)) return false;
    if (selectedMissionId && m.id !== selectedMissionId) return false;
    return true;
  });

  // Status counts
  const statusCounts = Object.keys(STATUS_COLORS).map((s) => ({
    status: s, color: STATUS_COLORS[s], count: locations.filter((l) => l.status === s).length,
  }));

  const fetchRoadRoute = async (f1: any, f2: any) => {
    setFetchingRoute(true);
    setRoadRoutePoints([]);
    try {
      const url = `https://router.project-osrm.org/route/v1/driving/${f1.longitude},${f1.latitude};${f2.longitude},${f2.latitude}?overview=full&geometries=geojson`;
      const res = await fetch(url);
      const json = await res.json();
      if (json.code === "Ok" && json.routes?.[0]?.geometry?.coordinates) {
        // OSRM returns [lng, lat] — flip to [lat, lng] for Leaflet
        const pts: [number, number][] = json.routes[0].geometry.coordinates.map(
          ([lng, lat]: [number, number]) => [lat, lng]
        );
        setRoadRoutePoints(pts);
      }
    } catch {
      // Network error or OSRM unavailable — fall back silently
      setRoadRoutePoints([]);
    } finally {
      setFetchingRoute(false);
    }
  };

  const toggleFacilityRouting = (f: any) => {
    if (!showRouting) return;
    setRoutingFacilities((prev) => {
      let next: any[];
      if (prev.find((x) => x.id === f.id)) {
        next = prev.filter((x) => x.id !== f.id);
      } else if (prev.length >= 2) {
        next = [prev[1], f];
      } else {
        next = [...prev, f];
      }
      // When two points are chosen and road mode is active, fetch real route
      if (next.length === 2 && routingMode === "road") {
        fetchRoadRoute(next[0], next[1]);
      } else {
        setRoadRoutePoints([]);
      }
      return next;
    });
  };

  // Route waypoints helper
  const routeWaypoints = (r: any): [number, number][] => {
    const wps: any[] = r.waypoints ?? [];
    return wps
      .map((w) => [(w.latitude ?? w.lat) as number, (w.longitude ?? w.lng) as number] as [number, number])
      .filter(([lat, lng]) => lat != null && lng != null);
  };

  return (
    <div style={{ position: "relative", height: "calc(100vh - 52px)", width: "100%", background: "#000" }}>

      {/* ── Top-left status bar ── */}
      <div style={{
        position: "absolute", top: 12, left: 12, zIndex: 1000,
        background: "rgba(2,6,2,0.92)", border: "1px solid #0f1f0f",
        padding: "6px 14px", display: "flex", alignItems: "center", gap: 12,
      }}>
        <span style={{ width: 7, height: 7, borderRadius: "50%", background: "#22c55e", boxShadow: "0 0 6px #22c55e", display: "inline-block", animation: "pulse 2s infinite" }} />
        <span style={{ color: "#22c55e", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, letterSpacing: 2 }}>LIVE</span>
        <span style={{ color: "#4b5563", fontFamily: "'JetBrains Mono', monospace", fontSize: 11 }}>
          {loading ? "..." : `${locations.length} TRACKED`}
        </span>
        <button onClick={load} style={{ background: "none", border: "none", color: "#374151", cursor: "pointer", padding: 0, display: "flex" }} title="Refresh">
          <MdRefresh size={15} />
        </button>
      </div>

      {/* ── Second toolbar row: time filter + mission filter ── */}
      <div style={{
        position: "absolute", top: 48, left: 12, zIndex: 1000,
        display: "flex", alignItems: "center", gap: 4,
      }}>
        {/* Time filter chips */}
        <div style={{ display: "flex", gap: 2, background: "rgba(2,6,2,0.92)", border: "1px solid #0f1f0f", padding: "4px 6px" }}>
          <MdSchedule size={13} style={{ color: "#374151", margin: "auto 2px" }} />
          {(["today", "week", "month", "all"] as TimeFilter[]).map((f) => (
            <Chip key={f} label={f === "today" ? "TODAY" : f === "week" ? "7 DAYS" : f === "month" ? "30 DAYS" : "ALL TIME"} active={timeFilter === f} onClick={() => setTimeFilter(f)} />
          ))}
        </div>

        {/* Mission filter button */}
        <div style={{ position: "relative" }}>
          <button
            onClick={() => setShowMissionPanel((v) => !v)}
            style={{
              background: selectedMissionId ? "#1e3a5f" : "rgba(2,6,2,0.92)",
              border: `1px solid ${selectedMissionId ? "#3b82f6" : "#0f1f0f"}`,
              color: selectedMissionId ? "#60a5fa" : "#4b5563",
              padding: "5px 10px", cursor: "pointer",
              display: "flex", alignItems: "center", gap: 6,
              fontFamily: "'JetBrains Mono', monospace", fontSize: 9, letterSpacing: 1,
            }}
          >
            <MdFlag size={13} />
            {selectedMissionId ? (selectedMission?.name?.substring(0, 18) ?? "MISSION") : "ALL MISSIONS"}
            {selectedMissionId && (
              <span
                onClick={(e) => { e.stopPropagation(); setSelectedMissionId(null); }}
                style={{ marginLeft: 4, color: "#60a5fa", cursor: "pointer", fontSize: 10 }}
              >✕</span>
            )}
          </button>

          {/* Mission panel dropdown */}
          {showMissionPanel && (
            <div style={{
              position: "absolute", top: "100%", left: 0, marginTop: 4,
              background: "#020a02", border: "1px solid #0f1f0f",
              width: 320, maxHeight: 400, overflowY: "auto", zIndex: 1002,
            }}>
              <div style={{ padding: "8px 12px", borderBottom: "1px solid #0f2010", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <span style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 9, letterSpacing: 2 }}>
                  MISSION FILTER {loadingMissions && "…"}
                </span>
                <button onClick={() => setShowMissionPanel(false)} style={{ background: "none", border: "none", color: "#374151", cursor: "pointer", padding: 0 }}>
                  <MdClose size={14} />
                </button>
              </div>

              {/* "All" option */}
              <button
                onClick={() => { setSelectedMissionId(null); setShowMissionPanel(false); }}
                style={{
                  width: "100%", textAlign: "left", padding: "10px 12px",
                  background: !selectedMissionId ? "#052e16" : "transparent",
                  border: "none", borderLeft: `2px solid ${!selectedMissionId ? "#22c55e" : "transparent"}`,
                  cursor: "pointer",
                }}
              >
                <span style={{ color: !selectedMissionId ? "#22c55e" : "#6b7280", fontFamily: "'JetBrains Mono', monospace", fontSize: 10 }}>
                  SHOW ALL DATA
                </span>
              </button>

              {missions.map((m) => {
                const prog = missionProgress(m);
                const isActive = ACTIVE_MISSION_STATUSES.has(m.status);
                const pColor = PRIORITY_COLORS[m.priority] ?? "#6b7280";
                const isSelected = selectedMissionId === m.id;
                return (
                  <button
                    key={m.id}
                    onClick={() => { setSelectedMissionId(m.id); setShowMissionPanel(false); }}
                    style={{
                      width: "100%", textAlign: "left", padding: "10px 12px",
                      background: isSelected ? "#0c1e3d" : "transparent",
                      border: "none", borderLeft: `2px solid ${isSelected ? "#3b82f6" : "transparent"}`,
                      cursor: "pointer", borderBottom: "1px solid #0a150a",
                    }}
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 4 }}>
                      <span style={{ background: pColor + "22", color: pColor, fontSize: 8, padding: "1px 4px", letterSpacing: 1, fontFamily: "'JetBrains Mono', monospace" }}>
                        {m.priority?.toUpperCase()}
                      </span>
                      {isActive && <span style={{ width: 6, height: 6, borderRadius: "50%", background: "#22c55e", flexShrink: 0 }} />}
                      <span style={{ color: isSelected ? "#93c5fd" : "#d1fae5", fontSize: 11, fontWeight: 600, fontFamily: "'JetBrains Mono', monospace" }}>
                        {m.name}
                      </span>
                    </div>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      {/* Progress bar */}
                      <div style={{ flex: 1, height: 3, background: "#0f2010", borderRadius: 2 }}>
                        <div style={{ width: `${prog.pct * 100}%`, height: "100%", background: prog.pct === 1 ? "#22c55e" : "#3b82f6", borderRadius: 2 }} />
                      </div>
                      <span style={{ color: "#6b7280", fontSize: 9, fontFamily: "'JetBrains Mono', monospace", flexShrink: 0 }}>
                        {prog.done}/{prog.total} OBJ
                      </span>
                      <span style={{ color: "#374151", fontSize: 8, fontFamily: "'JetBrains Mono', monospace", textTransform: "uppercase" }}>
                        {m.status}
                      </span>
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* ── Toolbar layer buttons (top right) ── */}
      <div style={{ position: "absolute", top: 12, right: 200, zIndex: 1000, display: "flex", gap: 4 }}>
        <button
          onClick={() => setShowFacilities((v) => !v)}
          style={{ background: showFacilities ? "#052e16" : "#0a140a", border: `1px solid ${showFacilities ? "#16a34a" : "#152015"}`, color: showFacilities ? "#22c55e" : "#4b5563", padding: "7px 10px", cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1 }}
        >
          <MdDomain size={16} /> {filteredFacilities.length} FACILITIES
        </button>
        <button
          onClick={() => setShowZones((v) => !v)}
          style={{ background: showZones ? "#0c1f2e" : "#0a0a14", border: `1px solid ${showZones ? "#3b82f6" : "#151520"}`, color: showZones ? "#60a5fa" : "#4b5563", padding: "7px 10px", cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1 }}
        >
          <MdCropFree size={16} /> {filteredZones.length} ZONES
        </button>
        <button
          onClick={() => {
            const next = !showRoutes;
            setShowRoutes(next);
            if (next) {
              setShowFacilities(false);
              setShowZones(false);
              setShowPois(false);
            } else {
              setShowFacilities(true);
              setShowZones(true);
              setShowPois(true);
            }
          }}
          style={{ background: showRoutes ? "#0f1a0f" : "#0a0a0a", border: `1px solid ${showRoutes ? "#22c55e" : "#1a1a1a"}`, color: showRoutes ? "#4ade80" : "#4b5563", padding: "7px 10px", cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1 }}
        >
          <MdAltRoute size={16} /> {filteredRoutes.length} ROUTES
        </button>
        {/* Routing button + mode sub-menu */}
        <div style={{ position: "relative" }}>
          <button
            onClick={() => {
              if (!showRouting) {
                setShowRouting(true);
                setShowRoutingMenu(true);
              } else {
                setShowRouting(false);
                setShowRoutingMenu(false);
                setRoutingFacilities([]);
                setRoadRoutePoints([]);
              }
            }}
            style={{ background: showRouting ? "#1f0c0c" : "#0a0a0a", border: `1px solid ${showRouting ? "#ef4444" : "#1a1a1a"}`, color: showRouting ? "#f87171" : "#4b5563", padding: "7px 10px", cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1 }}
          >
            <MdAltRoute size={16} />
            {fetchingRoute ? "FETCHING…" : showRouting ? (routingFacilities.length === 2 ? `ROUTE ACTIVE · ${routingMode === "road" ? "ROAD" : "DIRECT"}` : `SELECT ${2 - routingFacilities.length}`) : "ROUTING"}
          </button>

          {/* Mode sub-menu — appears when routing is first activated */}
          {showRoutingMenu && (
            <div style={{
              position: "absolute", top: "100%", right: 0, marginTop: 2,
              background: "#0a0a0a", border: "1px solid #2a1a1a", zIndex: 1002, minWidth: 180,
            }}>
              <div style={{ padding: "6px 10px", borderBottom: "1px solid #1a0a0a" }}>
                <span style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 8, letterSpacing: 2 }}>ROUTE TYPE</span>
              </div>
              {(["straight", "road"] as const).map((mode) => {
                const isActive = routingMode === mode;
                return (
                  <button
                    key={mode}
                    onClick={() => {
                      setRoutingMode(mode);
                      setShowRoutingMenu(false);
                      setRoadRoutePoints([]);
                      // Re-fetch if we already have two points selected
                      if (mode === "road" && routingFacilities.length === 2) {
                        fetchRoadRoute(routingFacilities[0], routingFacilities[1]);
                      }
                    }}
                    style={{
                      width: "100%", textAlign: "left", padding: "9px 12px",
                      background: isActive ? "#1f0c0c" : "transparent",
                      border: "none", borderLeft: `2px solid ${isActive ? "#ef4444" : "transparent"}`,
                      cursor: "pointer", display: "flex", flexDirection: "column", gap: 2,
                    }}
                  >
                    <span style={{ color: isActive ? "#f87171" : "#6b7280", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1 }}>
                      {mode === "straight" ? "DIRECT LINE" : "ROAD ROUTE"}
                    </span>
                    <span style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 8 }}>
                      {mode === "straight" ? "Straight line between points" : "Real roads via OSRM"}
                    </span>
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* ── Layer switcher ── */}
      <div style={{ position: "absolute", top: 12, right: 46, zIndex: 1000 }}>
        <button
          onClick={() => setShowLayers((v) => !v)}
          style={{ background: showLayers ? "#052e16" : "#0a140a", border: `1px solid ${showLayers ? "#16a34a" : "#152015"}`, color: showLayers ? "#22c55e" : "#4b5563", padding: "7px 10px", cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1 }}
        >
          <MdLayers size={16} /> {TILE_LAYERS.find((t) => t.id === activeTile)?.label}
        </button>
        {showLayers && (
          <div style={{ position: "absolute", top: "100%", right: 0, marginTop: 4, background: "#020602", border: "1px solid #0f1f0f", minWidth: 200, zIndex: 1001 }}>
            <div style={{ padding: "8px 12px", borderBottom: "1px solid #0f1f0f", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 9, letterSpacing: 2 }}>SELECT MAP LAYER</span>
              <button onClick={() => setShowLayers(false)} style={{ background: "none", border: "none", color: "#374151", cursor: "pointer", padding: 0 }}><MdClose size={14} /></button>
            </div>
            {TILE_LAYERS.map((layer) => {
              const isActive = activeTile === layer.id;
              return (
                <button key={layer.id} onClick={() => { setActiveTile(layer.id); setShowLayers(false); }}
                  style={{ width: "100%", display: "flex", alignItems: "center", gap: 10, padding: "9px 12px", background: isActive ? "#052e16" : "transparent", border: "none", borderLeft: `2px solid ${isActive ? "#16a34a" : "transparent"}`, cursor: "pointer" }}>
                  <div style={{ width: 28, height: 20, background: layer.preview, border: `1px solid ${isActive ? "#16a34a" : "#1f2d1f"}`, flexShrink: 0 }} />
                  <span style={{ color: isActive ? "#22c55e" : "#6b7280", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1 }}>{layer.label}</span>
                  {isActive && <span style={{ marginLeft: "auto", color: "#16a34a", fontSize: 9, fontFamily: "'JetBrains Mono', monospace" }}>ACTIVE</span>}
                </button>
              );
            })}
          </div>
        )}
      </div>

      {/* ── Map ── */}
      <MapContainer
        center={[-1.9441, 30.0619]}
        zoom={12}
        style={{ height: "100%", width: "100%", background: "#010801" }}
        zoomControl={false}
      >
        <ActiveTileLayer tileId={activeTile} />
        <FitBoundsButton locations={locations} />
        <ZoomButtons />

        {/* Zone overlays — all zones always visible; mission-linked ones glow brighter */}
        {showZones && filteredZones.map((z) => {
          const pts = z.polygon_points?.points ?? [];
          const isMission = selectedMissionId ? missionZoneIds.has(z.id) : false;
          const weight = isMission ? 3 : 1.5;
          const opacity = isMission ? 1 : 0.7;
          const fillOpacity = isMission ? 0.22 : 0.12;
          const opts = { color: z.color, fillColor: z.fill_color ?? z.color + "33", weight, opacity, fillOpacity };
          if (z.is_circle && z.center_lat && z.center_lng && z.radius) return <Circle key={z.id} center={[z.center_lat, z.center_lng]} radius={z.radius} pathOptions={opts}><Popup className="drd-popup"><ZonePopup z={z} /></Popup></Circle>;
          if (z.shape === "rectangle" && pts.length === 2) return <Rectangle key={z.id} bounds={[pts[0], pts[1]]} pathOptions={opts}><Popup className="drd-popup"><ZonePopup z={z} /></Popup></Rectangle>;
          if (pts.length >= 3) return <Polygon key={z.id} positions={pts} pathOptions={opts}><Popup className="drd-popup"><ZonePopup z={z} /></Popup></Polygon>;
          return null;
        })}

        {/* Route polylines — all routes always visible; mission-linked ones thicker */}
        {showRoutes && filteredRoutes.map((r) => {
          const pts = routeWaypoints(r);
          if (pts.length < 2) return null;
          const isMission = selectedMissionId ? missionRouteIds.has(r.id) : false;
          const rColor = r.color ?? "#3b82f6";
          return (
            <Polyline key={r.id} positions={pts} pathOptions={{ color: rColor, weight: isMission ? 5 : 3, opacity: isMission ? 1 : 0.75 }}>
              <Popup className="drd-popup"><RoutePopup r={r} pts={pts} /></Popup>
            </Polyline>
          );
        })}

        {/* Inter-facility routing line */}
        {showRouting && routingFacilities.length === 2 && routingMode === "straight" && (
          <Polyline
            positions={routingFacilities.map((f) => [f.latitude, f.longitude] as [number, number])}
            pathOptions={{ color: "#ef4444", weight: 3, dashArray: "10,6", opacity: 0.8 }}
          />
        )}
        {showRouting && routingFacilities.length === 2 && routingMode === "road" && roadRoutePoints.length >= 2 && (
          <Polyline
            positions={roadRoutePoints}
            pathOptions={{ color: "#f97316", weight: 4, opacity: 0.9 }}
          />
        )}
        {/* Fallback straight line while road route is being fetched */}
        {showRouting && routingFacilities.length === 2 && routingMode === "road" && fetchingRoute && (
          <Polyline
            positions={routingFacilities.map((f) => [f.latitude, f.longitude] as [number, number])}
            pathOptions={{ color: "#f97316", weight: 2, dashArray: "6,6", opacity: 0.4 }}
          />
        )}

        {/* Facility markers */}
        {showFacilities && filteredFacilities.map((f) => {
          const isRoutingSelected = routingFacilities.find((r) => r.id === f.id);
          const isMission = selectedMissionId ? missionFacilityIds.has(f.id) : false;
          const facilityIcon = makeFacilityIcon(f.facility_type, f.threat_level, isMission);
          return (
            <Marker key={f.id} position={[f.latitude, f.longitude]} icon={facilityIcon} eventHandlers={{ click: () => toggleFacilityRouting(f) }}>
              <Popup className="drd-popup">
                <FacilityPopup f={f} isRoutingSelected={!!isRoutingSelected} showRouting={showRouting} routingFacilities={routingFacilities} roadRoutePoints={roadRoutePoints} routingMode={routingMode} />
              </Popup>
            </Marker>
          );
        })}

        {/* Field POI markers */}
        {showPois && filteredPois.map((poi) => {
          const poiColor = poi.color ?? "#8b5cf6";
          const poiIcon = L.divIcon({
            className: "",
            html: `<div style="width:28px;height:28px;border-radius:50%;background:${poiColor}cc;border:2px solid ${poiColor};box-shadow:0 0 8px ${poiColor}88;display:flex;align-items:center;justify-content:center;font-size:12px;color:#fff;font-weight:700;">◉</div>`,
            iconSize: [28, 28], iconAnchor: [14, 14],
          });
          return (
            <Marker key={poi.id} position={[poi.latitude, poi.longitude]} icon={poiIcon}>
              <Popup className="drd-popup"><PoiPopup poi={poi} /></Popup>
            </Marker>
          );
        })}

        {/* User location markers */}
        {locations.map((loc) => {
          const isMe = loc.user_id === user?.id;
          const color = STATUS_COLORS[loc.status] ?? "#6b7280";
          const avatar = loc.user?.avatar_url;
          const ini = initials(loc.user?.full_name, loc.user?.username);
          return (
            <Marker key={loc.user_id} position={[loc.latitude, loc.longitude]} icon={makeIcon(color, isMe, avatar, ini)}>
              <Popup className="drd-popup">
                <UserPopup loc={loc} isMe={isMe} color={color} ini={ini} navigate={navigate} />
              </Popup>
            </Marker>
          );
        })}
      </MapContainer>

      {/* ── Bottom-left legend ── */}
      <div style={{ position: "absolute", bottom: 12, left: 12, zIndex: 1000, display: "flex", flexDirection: "column", gap: 4 }}>

        {/* User status counts */}
        {statusCounts.map(({ status, color, count }) => (
          <div key={status} style={{ display: "flex", alignItems: "center", gap: 8, background: "rgba(2,6,2,0.92)", border: "1px solid #0f1f0f", padding: "4px 10px" }}>
            <div style={{ width: 8, height: 8, borderRadius: "50%", background: color }} />
            <span style={{ color: "#6b7280", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1, textTransform: "uppercase" }}>{status}</span>
            <span style={{ color, fontFamily: "'JetBrains Mono', monospace", fontSize: 10, marginLeft: 4 }}>{count}</span>
          </div>
        ))}

        {/* Mission progress legend */}
        {legendMissions.map((m) => {
          const prog = missionProgress(m);
          const pColor = PRIORITY_COLORS[m.priority] ?? "#6b7280";
          const isSelected = selectedMissionId === m.id;
          const remaining = prog.total - prog.done;
          return (
            <div
              key={m.id}
              onClick={() => setSelectedMissionId(isSelected ? null : m.id)}
              style={{
                background: isSelected ? "rgba(12,30,61,0.95)" : "rgba(2,6,2,0.92)",
                border: `1px solid ${isSelected ? "#3b82f6" : "#0f1f0f"}`,
                padding: "8px 10px", cursor: "pointer", minWidth: 200,
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 5 }}>
                <div style={{ width: 6, height: 6, borderRadius: "50%", background: pColor, flexShrink: 0 }} />
                <span style={{ color: "#d1fae5", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, fontWeight: 600, flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {m.name}
                </span>
                <span style={{ color: "#4b5563", fontFamily: "'JetBrains Mono', monospace", fontSize: 8 }}>
                  {prog.done}/{prog.total}
                </span>
              </div>

              {/* Progress bar */}
              {prog.total > 0 && (
                <div style={{ height: 3, background: "#0f2010", marginBottom: 4 }}>
                  <div style={{ width: `${prog.pct * 100}%`, height: "100%", background: prog.pct === 1 ? "#22c55e" : "#3b82f6" }} />
                </div>
              )}

              {/* Remaining label */}
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <span style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 8, letterSpacing: 1 }}>
                  {prog.pct === 1
                    ? "ALL COMPLETE"
                    : remaining === 0
                    ? "DONE"
                    : `${remaining} OBJ REMAINING`}
                </span>
                <span style={{
                  fontSize: 7, padding: "1px 4px", letterSpacing: 1,
                  fontFamily: "'JetBrains Mono', monospace",
                  background: m.status === "active" ? "#052e16" : "#1a1a2a",
                  color: m.status === "active" ? "#22c55e" : "#6b7280",
                }}>
                  {m.status.toUpperCase()}
                </span>
              </div>

              {/* Current objective */}
              {prog.currentObj && (
                <div style={{ marginTop: 4, color: "#4b5563", fontFamily: "'JetBrains Mono', monospace", fontSize: 8, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  ▶ {cleanObjTitle(prog.currentObj.title ?? "")}
                </div>
              )}
            </div>
          );
        })}
      </div>

    </div>
  );
}

// ── Popup sub-components (defined outside main to avoid re-creation) ──────────

function UserPopup({ loc, isMe, color, ini, navigate }: { loc: LiveLocation; isMe: boolean; color: string; ini: string; navigate: ReturnType<typeof useNavigate> }) {
  const teamName = loc.user?.team;
  const roleName = ROLE_LABELS[loc.user?.role ?? ""] ?? loc.user?.role ?? "";
  const displayName = loc.user?.full_name || loc.user?.username || loc.user_id.substring(0, 8);
  const avatar = loc.user?.avatar_url;
  return (
    <div style={{ background: "#040804", border: "1px solid #152015", padding: "12px 14px", minWidth: 240, fontFamily: "'JetBrains Mono', monospace" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
        <div style={{ width: 38, height: 38, borderRadius: "50%", overflow: "hidden", border: `2px solid ${color}`, flexShrink: 0, background: color + "33", display: "flex", alignItems: "center", justifyContent: "center" }}>
          {avatar
            ? <img src={avatar} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
            : <span style={{ fontSize: 14, fontWeight: 700, color }}>{ini}</span>}
        </div>
        <div>
          <div style={{ color: "#d1fae5", fontSize: 12, fontWeight: 700, lineHeight: 1.3 }}>
            {displayName} {isMe && <span style={{ color: "#16a34a" }}>(YOU)</span>}
          </div>
          <div style={{ display: "flex", gap: 4, marginTop: 3, flexWrap: "wrap" }}>
            <span style={{ background: color + "22", color, fontSize: 8, padding: "1px 5px", letterSpacing: 0.8 }}>{loc.status.toUpperCase()}</span>
            {roleName && <span style={{ background: "#0f2d3f", color: "#38bdf8", fontSize: 8, padding: "1px 5px", letterSpacing: 0.8 }}>{roleName}</span>}
            {teamName && <span style={{ background: "#1a1a2e", color: "#a78bfa", fontSize: 8, padding: "1px 5px", letterSpacing: 0.8 }}>TEAM: {teamName.toUpperCase()}</span>}
          </div>
        </div>
      </div>
      <div style={{ borderTop: "1px solid #0f2010", marginBottom: 8 }} />
      <GpsBlock lat={loc.latitude} lng={loc.longitude} speed={loc.speed} heading={loc.heading} />
      {!isMe && (
        <button
          onClick={() => navigate("/comms", { state: { dmUserId: loc.user_id, dmUserName: loc.user?.full_name ?? loc.user?.username } })}
          style={{ marginTop: 10, width: "100%", padding: "6px 0", background: "#052e16", border: "1px solid #166534", color: "#22c55e", fontSize: 10, letterSpacing: 1, cursor: "pointer", fontFamily: "'JetBrains Mono', monospace" }}
        >
          ✉ SEND MESSAGE
        </button>
      )}
    </div>
  );
}

function FacilityPopup({ f, isRoutingSelected, showRouting, routingFacilities, roadRoutePoints, routingMode }: { f: any; isRoutingSelected: boolean; showRouting: boolean; routingFacilities: any[]; roadRoutePoints: [number, number][]; routingMode: string }) {
  const meta = FACILITY_META[f.facility_type] || FACILITY_META.other;
  return (
    <div style={{ background: "#040804", border: "1px solid #152015", padding: "12px 14px", minWidth: 240, fontFamily: "'JetBrains Mono', monospace" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
        <span style={{ fontSize: 18, color: meta.color }}>{meta.icon}</span>
        <span style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{f.name}</span>
        {f.threat_level && f.threat_level !== "green" && (
          <span style={{ marginLeft: "auto", fontSize: 8, padding: "2px 5px", background: THREAT_COLORS[f.threat_level] + "22", color: THREAT_COLORS[f.threat_level], letterSpacing: 1 }}>
            {f.threat_level.toUpperCase()}
          </span>
        )}
      </div>
      <div style={{ color: "#4b5563", fontSize: 10, marginBottom: 4 }}>{f.facility_type?.replace(/_/g, " ").toUpperCase()}</div>
      {f.description && <p style={{ color: "#6b7280", fontSize: 11, margin: "4px 0", lineHeight: 1.5 }}>{f.description}</p>}
      {f.notes && <p style={{ color: "#374151", fontSize: 11, margin: "4px 0", lineHeight: 1.5 }}>{f.notes}</p>}

      <div style={{ display: "flex", gap: 6, marginBottom: 4 }}>
        <span style={{ background: f.status === "active" ? "#22c55e20" : "#6b728020", color: f.status === "active" ? "#22c55e" : "#6b7280", fontSize: 8, padding: "2px 6px", letterSpacing: 1 }}>
          {f.status?.toUpperCase()}
        </span>
        {f.mission && <span style={{ color: "#22c55e", fontSize: 9 }}>{f.mission}</span>}
        {showRouting && <span style={{ fontSize: 8, color: isRoutingSelected ? "#ef4444" : "#4b5563" }}>{isRoutingSelected ? "● ROUTING PT" : "Click to route"}</span>}
      </div>

      {showRouting && routingFacilities.length === 2 && routingFacilities[0].id === f.id && (() => {
        const straightDist = L.latLng(routingFacilities[0].latitude, routingFacilities[0].longitude)
          .distanceTo(L.latLng(routingFacilities[1].latitude, routingFacilities[1].longitude));
        const roadDist = roadRoutePoints.length >= 2
          ? roadRoutePoints.reduce((sum, pt, i) =>
              i === 0 ? 0 : sum + L.latLng(roadRoutePoints[i - 1]).distanceTo(L.latLng(pt)), 0)
          : null;
        return (
          <div style={{ color: "#f87171", fontSize: 9, marginBottom: 4 }}>
            {routingMode === "road" && roadDist != null
              ? <>ROAD: {(roadDist / 1000).toFixed(1)} km · DIRECT: {(straightDist / 1000).toFixed(1)} km</>
              : <>~{(straightDist / 1000).toFixed(1)} km to {routingFacilities[1].name}</>}
            {" "}→ {routingFacilities[1].name}
          </div>
        );
      })()}

      {/* Raised by */}
      {(f.creator_name || f.creator_username) && (
        <div style={{ display: "flex", alignItems: "center", gap: 5, marginBottom: 4 }}>
          <span style={{ color: "#374151", fontSize: 8, letterSpacing: 1 }}>RAISED BY</span>
          <span style={{ color: "#a78bfa", fontSize: 9, fontWeight: 600 }}>{f.creator_name || f.creator_username}</span>
        </div>
      )}

      {f.created_at && (
        <div style={{ color: "#1f4d1f", fontSize: 8, marginBottom: 2 }}>
          ADDED {new Date(f.created_at).toLocaleDateString()}
        </div>
      )}

      <GpsBlock lat={Number(f.latitude)} lng={Number(f.longitude)} />
    </div>
  );
}

function PoiPopup({ poi }: { poi: any }) {
  const poiColor = poi.color ?? "#8b5cf6";
  const [evidence, setEvidence] = useState<any[]>([]);

  useEffect(() => {
    poiApi.getEvidence(poi.id)
      .then(({ data }) => setEvidence(Array.isArray(data) ? data : []))
      .catch(() => {});
  }, [poi.id]);

  const imageEvidence = useMemo(() => evidence.filter((e) => e.evidence_type === "image" && e.file_url), [evidence]);
  const creatorLabel = poi.creator_name || poi.creator_username;

  return (
    <div style={{ background: "#040804", border: "1px solid #152015", padding: "12px 14px", minWidth: 240, fontFamily: "'JetBrains Mono', monospace" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 7, marginBottom: 6 }}>
        <div style={{ width: 10, height: 10, borderRadius: "50%", background: poiColor, boxShadow: `0 0 5px ${poiColor}`, flexShrink: 0 }} />
        <span style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{poi.name}</span>
      </div>
      <span style={{ background: poiColor + "22", color: poiColor, fontSize: 8, padding: "1px 5px", letterSpacing: 0.8 }}>
        {(poi.poi_type ?? "general").toUpperCase()}
      </span>
      {poi.description && <p style={{ color: "#6b7280", fontSize: 11, margin: "8px 0 0", lineHeight: 1.5 }}>{poi.description}</p>}
      {poi.mission_id && (
        <div style={{ marginTop: 4, color: "#3b82f6", fontSize: 9, letterSpacing: 1 }}>LINKED TO MISSION</div>
      )}

      {/* Raised by */}
      {creatorLabel && (
        <div style={{ marginTop: 6, display: "flex", alignItems: "center", gap: 5 }}>
          <span style={{ color: "#374151", fontSize: 8, letterSpacing: 1 }}>RAISED BY</span>
          <span style={{ color: "#a78bfa", fontSize: 9, fontWeight: 600 }}>{creatorLabel}</span>
        </div>
      )}

      {poi.created_at && (
        <div style={{ color: "#1f4d1f", fontSize: 8, marginTop: 4 }}>
          MARKED {new Date(poi.created_at).toLocaleString()}
        </div>
      )}

      {/* Evidence */}
      {imageEvidence.length > 0 && (
        <div style={{ marginTop: 8 }}>
          <div style={{ color: "#374151", fontSize: 8, letterSpacing: 1, marginBottom: 4 }}>
            EVIDENCE ({imageEvidence.length})
          </div>
          {imageEvidence.map((ev) => (
            <div key={ev.id} style={{ marginBottom: 6 }}>
              <img
                src={ev.file_url}
                alt={ev.title ?? "Evidence"}
                style={{ width: "100%", maxHeight: 160, objectFit: "cover", border: "1px solid #0f2010" }}
                onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
              />
              {ev.title && <div style={{ color: "#4b5563", fontSize: 8, marginTop: 2 }}>{ev.title}</div>}
            </div>
          ))}
        </div>
      )}
      {evidence.filter((e) => e.evidence_type !== "image").length > 0 && (
        <div style={{ marginTop: 6 }}>
          {evidence.filter((e) => e.evidence_type !== "image").map((ev) => (
            <div key={ev.id} style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 3 }}>
              <span style={{ color: "#8b5cf6", fontSize: 8, background: "#1a1a2e", padding: "1px 4px" }}>{ev.evidence_type?.toUpperCase()}</span>
              <span style={{ color: "#6b7280", fontSize: 9 }}>{ev.title}</span>
            </div>
          ))}
        </div>
      )}

      <GpsBlock lat={Number(poi.latitude)} lng={Number(poi.longitude)} />
    </div>
  );
}

function ZonePopup({ z }: { z: any }) {
  const pts: [number, number][] = z.polygon_points?.points ?? [];
  const centerLat = pts.length > 0 ? pts.reduce((s, p) => s + p[0], 0) / pts.length : z.center_lat;
  const centerLng = pts.length > 0 ? pts.reduce((s, p) => s + p[1], 0) / pts.length : z.center_lng;
  return (
    <div style={{ background: "#040814", border: "1px solid #0f0f2f", padding: "12px 14px", minWidth: 220, fontFamily: "'JetBrains Mono', monospace" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
        <div style={{ width: 10, height: 10, background: z.color ?? "#6366f1", flexShrink: 0 }} />
        <span style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{z.name}</span>
      </div>
      {z.description && <p style={{ color: "#6b7280", fontSize: 11, margin: "4px 0", lineHeight: 1.5 }}>{z.description}</p>}
      <div style={{ display: "flex", gap: 6, marginBottom: 4 }}>
        <span style={{ fontSize: 8, padding: "1px 5px", letterSpacing: 1, background: z.is_active ? "#052e16" : "#1a1a1a", color: z.is_active ? "#22c55e" : "#6b7280" }}>
          {z.is_active ? "ACTIVE" : "INACTIVE"}
        </span>
        {z.is_circle && <span style={{ fontSize: 8, color: "#6b7280" }}>RADIUS {z.radius}m</span>}
        {z.zone_type && <span style={{ fontSize: 8, color: "#6366f1", background: "#1a1a2e", padding: "1px 4px" }}>{z.zone_type.toUpperCase()}</span>}
      </div>
      {centerLat != null && centerLng != null && <GpsBlock lat={Number(centerLat)} lng={Number(centerLng)} />}
    </div>
  );
}

function RoutePopup({ r, pts }: { r: any; pts: [number, number][] }) {
  const midPt = pts[Math.floor(pts.length / 2)];
  return (
    <div style={{ background: "#040814", border: "1px solid #0f0f2f", padding: "12px 14px", minWidth: 220, fontFamily: "'JetBrains Mono', monospace" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
        <div style={{ width: 24, height: 3, background: r.color ?? "#3b82f6", flexShrink: 0 }} />
        <span style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{r.name}</span>
      </div>
      {r.description && <p style={{ color: "#6b7280", fontSize: 11, margin: "4px 0", lineHeight: 1.5 }}>{r.description}</p>}
      <div style={{ color: "#4b5563", fontSize: 9, marginBottom: 4 }}>{pts.length} WAYPOINTS</div>
      {midPt && <GpsBlock lat={midPt[0]} lng={midPt[1]} />}
    </div>
  );
}
