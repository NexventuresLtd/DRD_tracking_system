import { useEffect, useRef, useState } from "react";
import { MapContainer, TileLayer, Marker, Popup, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { locationApi, postsApi } from "../services/api";
import { useAuthStore } from "../stores/authStore";
import type { LiveLocation } from "../types";
import { MdMyLocation, MdLayers, MdRefresh, MdClose, MdDomain } from "react-icons/md";

delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png",
  iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
});

// ── Tile layer definitions ──────────────────────────────────────────────────
const TILE_LAYERS = [
  {
    id: "dark",
    label: "DARK OPS",
    preview: "#0a0a0a",
    url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
    attribution: "© CARTO",
    maxZoom: 19,
  },
  {
    id: "satellite",
    label: "SATELLITE",
    preview: "#2d4a1e",
    url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
    attribution: "© Esri",
    maxZoom: 19,
  },
  {
    id: "terrain",
    label: "TERRAIN",
    preview: "#4a6741",
    url: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
    attribution: "© OpenTopoMap",
    maxZoom: 17,
  },
  {
    id: "street",
    label: "STREET",
    preview: "#1a2a3a",
    url: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
    attribution: "© OpenStreetMap",
    maxZoom: 19,
  },
  {
    id: "topo",
    label: "TOPO",
    preview: "#3a4a2a",
    url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}",
    attribution: "© Esri",
    maxZoom: 19,
  },
  {
    id: "hybrid",
    label: "HYBRID",
    preview: "#1a3a2a",
    url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}",
    attribution: "© Esri",
    maxZoom: 19,
  },
] as const;

type TileId = (typeof TILE_LAYERS)[number]["id"];

// ── Status colours ──────────────────────────────────────────────────────────
const STATUS_COLORS: Record<string, string> = {
  active: "#22c55e",
  stale:  "#f59e0b",
  offline: "#6b7280",
};

// ── Facility type metadata ──────────────────────────────────────────────────
const FACILITY_META: Record<string, { icon: string; color: string }> = {
  forward_operating_base:  { icon: "⬡", color: "#ef4444" },
  main_operating_base:     { icon: "★", color: "#dc2626" },
  combat_outpost:          { icon: "⬟", color: "#f97316" },
  checkpoint:              { icon: "⬢", color: "#eab308" },
  logistics_depot:         { icon: "▣", color: "#84cc16" },
  medical_center:          { icon: "✚", color: "#22c55e" },
  command_center:          { icon: "◈", color: "#14b8a6" },
  communications_hub:      { icon: "◎", color: "#06b6d4" },
  armory:                  { icon: "⚙", color: "#3b82f6" },
  training_facility:       { icon: "◇", color: "#6366f1" },
  detention_center:        { icon: "⊡", color: "#8b5cf6" },
  airfield:                { icon: "✈", color: "#a855f7" },
  naval_facility:          { icon: "⚓", color: "#ec4899" },
  office:                  { icon: "▦", color: "#6b7280" },
  border_post:             { icon: "⬛", color: "#78716c" },
  safe_house:              { icon: "⌂", color: "#059669" },
  intelligence_post:       { icon: "◉", color: "#7c3aed" },
  barracks:                { icon: "⊞", color: "#374151" },
  supply_point:            { icon: "◫", color: "#b45309" },
  other:                   { icon: "◌", color: "#4b5563" },
};

function makeFacilityIcon(type: string) {
  const meta = FACILITY_META[type] || FACILITY_META.other;
  return L.divIcon({
    className: "",
    html: `<div style="
      width:32px;height:32px;
      background:${meta.color}22;
      border:2px solid ${meta.color};
      display:flex;align-items:center;justify-content:center;
      font-size:14px;color:${meta.color};
      box-shadow:0 0 8px ${meta.color}55;
    ">${meta.icon}</div>`,
    iconSize: [32, 32],
    iconAnchor: [16, 16],
  });
}

// ── Marker icon factory ─────────────────────────────────────────────────────
function makeIcon(color: string, isMe: boolean) {
  const size = isMe ? 22 : 16;
  return L.divIcon({
    className: "",
    html: `
      <div style="
        position:relative;
        width:${size}px;height:${size}px;
        background:${color};
        border:${isMe ? 3 : 2}px solid ${isMe ? "#fff" : "rgba(255,255,255,0.6)"};
        border-radius:50%;
        box-shadow:0 0 ${isMe ? 10 : 6}px ${color}80;
      ">
        ${isMe ? `<div style="position:absolute;inset:-6px;border-radius:50%;border:2px solid ${color}60;animation:ping 1.5s cubic-bezier(0,0,.2,1) infinite"></div>` : ""}
      </div>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
  });
}

// ── Inner components ────────────────────────────────────────────────────────
function FitBoundsButton({ locations }: { locations: LiveLocation[] }) {
  const map = useMap();
  if (!locations.length) return null;
  return (
    <button
      onClick={() => {
        const bounds = L.latLngBounds(locations.map((l) => [l.latitude, l.longitude]));
        map.fitBounds(bounds, { padding: [60, 60] });
      }}
      title="Fit all markers"
      style={{
        position: "absolute", top: 12, right: 12, zIndex: 1000,
        background: "#0a140a", border: "1px solid #16a34a",
        color: "#22c55e", padding: "7px", cursor: "pointer",
        display: "flex", alignItems: "center",
      }}
    >
      <MdMyLocation size={18} />
    </button>
  );
}

function ActiveTileLayer({ tileId }: { tileId: TileId }) {
  const layer = TILE_LAYERS.find((t) => t.id === tileId)!;
  return (
    <TileLayer
      key={tileId}
      url={layer.url}
      attribution={layer.attribution}
      maxZoom={layer.maxZoom}
    />
  );
}

// ── Main component ──────────────────────────────────────────────────────────
export default function LiveMap() {
  const { user } = useAuthStore();
  const [locations, setLocations] = useState<LiveLocation[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTile, setActiveTile] = useState<TileId>("dark");
  const [showLayers, setShowLayers] = useState(false);
  const [facilities, setFacilities] = useState<any[]>([]);
  const [showFacilities, setShowFacilities] = useState(true);
  const wsRef = useRef<WebSocket | null>(null);

  const load = () => {
    locationApi.getLive()
      .then(({ data }) => setLocations(data))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  const loadFacilities = () => {
    postsApi.mapPosts()
      .then(({ data }) => setFacilities(data))
      .catch(() => {});
  };

  useEffect(() => {
    load();
    loadFacilities();
    const interval = setInterval(load, 10000);
    const facilityInterval = setInterval(loadFacilities, 60000);

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
    }

    return () => { clearInterval(interval); clearInterval(facilityInterval); wsRef.current?.close(); };
  }, [user]);

  const statusCounts = Object.keys(STATUS_COLORS).map((s) => ({
    status: s,
    color: STATUS_COLORS[s],
    count: locations.filter((l) => l.status === s).length,
  }));

  return (
    <div style={{ position: "relative", height: "calc(100vh - 52px)", width: "100%", background: "#000" }}>

      {/* ── Top-left status bar ── */}
      <div style={{
        position: "absolute", top: 12, left: 12, zIndex: 1000,
        background: "rgba(2,6,2,0.92)", border: "1px solid #0f1f0f",
        padding: "6px 14px", display: "flex", alignItems: "center", gap: 12,
      }}>
        <span style={{ width: 7, height: 7, borderRadius: "50%", background: "#22c55e", boxShadow: "0 0 6px #22c55e", display: "inline-block", animation: "pulse 2s infinite" }} />
        <span style={{ color: "#22c55e", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, letterSpacing: 2 }}>
          LIVE
        </span>
        <span style={{ color: "#4b5563", fontFamily: "'JetBrains Mono', monospace", fontSize: 11 }}>
          {loading ? "..." : `${locations.length} TRACKED`}
        </span>
        <button
          onClick={load}
          style={{ background: "none", border: "none", color: "#374151", cursor: "pointer", padding: 0, display: "flex" }}
          title="Refresh"
        >
          <MdRefresh size={15} />
        </button>
      </div>

      {/* ── Facilities toggle ── */}
      <div style={{ position: "absolute", top: 12, right: 160, zIndex: 1000 }}>
        <button
          onClick={() => setShowFacilities((v) => !v)}
          title="Toggle facility markers"
          style={{
            background: showFacilities ? "#052e16" : "#0a140a",
            border: `1px solid ${showFacilities ? "#16a34a" : "#152015"}`,
            color: showFacilities ? "#22c55e" : "#4b5563",
            padding: "7px 10px", cursor: "pointer",
            display: "flex", alignItems: "center", gap: 6,
            fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1,
          }}
        >
          <MdDomain size={16} />
          {facilities.length} FACILITIES
        </button>
      </div>

      {/* ── Layer switcher button ── */}
      <div style={{ position: "absolute", top: 12, right: 46, zIndex: 1000 }}>
        <button
          onClick={() => setShowLayers((v) => !v)}
          style={{
            background: showLayers ? "#052e16" : "#0a140a",
            border: `1px solid ${showLayers ? "#16a34a" : "#152015"}`,
            color: showLayers ? "#22c55e" : "#4b5563",
            padding: "7px 10px", cursor: "pointer",
            display: "flex", alignItems: "center", gap: 6,
            fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1,
          }}
          title="Map layers"
        >
          <MdLayers size={16} />
          {TILE_LAYERS.find((t) => t.id === activeTile)?.label}
        </button>

        {/* Layer picker panel */}
        {showLayers && (
          <div style={{
            position: "absolute", top: "100%", right: 0, marginTop: 4,
            background: "#020602", border: "1px solid #0f1f0f",
            minWidth: 200, zIndex: 1001,
          }}>
            <div style={{
              padding: "8px 12px", borderBottom: "1px solid #0f1f0f",
              display: "flex", justifyContent: "space-between", alignItems: "center",
            }}>
              <span style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 9, letterSpacing: 2 }}>
                SELECT MAP LAYER
              </span>
              <button onClick={() => setShowLayers(false)} style={{ background: "none", border: "none", color: "#374151", cursor: "pointer", padding: 0 }}>
                <MdClose size={14} />
              </button>
            </div>
            {TILE_LAYERS.map((layer) => {
              const isActive = activeTile === layer.id;
              return (
                <button
                  key={layer.id}
                  onClick={() => { setActiveTile(layer.id); setShowLayers(false); }}
                  style={{
                    width: "100%", display: "flex", alignItems: "center", gap: 10,
                    padding: "9px 12px", background: isActive ? "#052e16" : "transparent",
                    border: "none", borderLeft: `2px solid ${isActive ? "#16a34a" : "transparent"}`,
                    cursor: "pointer", textAlign: "left",
                  }}
                >
                  <div style={{
                    width: 28, height: 20, background: layer.preview,
                    border: `1px solid ${isActive ? "#16a34a" : "#1f2d1f"}`, flexShrink: 0,
                  }} />
                  <span style={{
                    color: isActive ? "#22c55e" : "#6b7280",
                    fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1,
                  }}>
                    {layer.label}
                  </span>
                  {isActive && (
                    <span style={{ marginLeft: "auto", color: "#16a34a", fontSize: 9, fontFamily: "'JetBrains Mono', monospace" }}>
                      ACTIVE
                    </span>
                  )}
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

        {/* ── Facility markers ── */}
        {showFacilities && facilities.map((f) => (
          <Marker key={f.id} position={[f.latitude, f.longitude]} icon={makeFacilityIcon(f.facility_type)}>
            <Popup className="drd-popup">
              <div style={{
                background: "#040804", border: "1px solid #152015",
                padding: "10px 12px", minWidth: 200, fontFamily: "'JetBrains Mono', monospace",
              }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
                  <span style={{ fontSize: 16, color: (FACILITY_META[f.facility_type] || FACILITY_META.other).color }}>
                    {(FACILITY_META[f.facility_type] || FACILITY_META.other).icon}
                  </span>
                  <span style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>{f.name}</span>
                </div>
                <p style={{ color: "#4b5563", fontSize: 10, margin: "2px 0" }}>
                  {f.facility_type.replace(/_/g, " ").toUpperCase()}
                </p>
                {f.description && (
                  <p style={{ color: "#374151", fontSize: 11, margin: "6px 0 0", lineHeight: 1.5 }}>{f.description}</p>
                )}
                {f.mission && (
                  <p style={{ color: "#22c55e", fontSize: 10, margin: "4px 0 0", lineHeight: 1.5 }}>{f.mission}</p>
                )}
                <div style={{ marginTop: 6, color: "#1f4d1f", fontSize: 9, letterSpacing: 1 }}>
                  {f.latitude.toFixed(5)}, {f.longitude.toFixed(5)}
                </div>
                <div style={{
                  marginTop: 6, display: "inline-block",
                  background: f.status === "active" ? "#22c55e20" : "#6b728020",
                  color: f.status === "active" ? "#22c55e" : "#6b7280",
                  fontSize: 8, padding: "2px 6px", letterSpacing: 1,
                }}>
                  {f.status.toUpperCase()}
                </div>
              </div>
            </Popup>
          </Marker>
        ))}

        {locations.map((loc) => {
          const isMe = loc.user_id === user?.id;
          const color = STATUS_COLORS[loc.status] ?? "#6b7280";
          return (
            <Marker key={loc.user_id} position={[loc.latitude, loc.longitude]} icon={makeIcon(color, isMe)}>
              <Popup className="drd-popup">
                <div style={{
                  background: "#040804", border: "1px solid #152015",
                  padding: "10px 12px", minWidth: 170, fontFamily: "'JetBrains Mono', monospace",
                }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 7, marginBottom: 8 }}>
                    <div style={{ width: 8, height: 8, borderRadius: "50%", background: color, boxShadow: `0 0 5px ${color}` }} />
                    <span style={{ color: "#d1fae5", fontSize: 12, fontWeight: 600 }}>
                      {loc.user?.full_name || loc.user_id.substring(0, 8)}
                    </span>
                    {isMe && <span style={{ color: "#16a34a", fontSize: 10 }}>(YOU)</span>}
                  </div>
                  <p style={{ color: "#4b5563", fontSize: 10, margin: "3px 0" }}>
                    {loc.latitude.toFixed(5)}, {loc.longitude.toFixed(5)}
                  </p>
                  {loc.speed != null && (
                    <p style={{ color: "#4b5563", fontSize: 10, margin: "3px 0" }}>
                      {(loc.speed * 3.6).toFixed(1)} km/h
                    </p>
                  )}
                  {loc.heading != null && (
                    <p style={{ color: "#4b5563", fontSize: 10, margin: "3px 0" }}>
                      HDG {loc.heading.toFixed(0)}°
                    </p>
                  )}
                  <div style={{
                    marginTop: 8, paddingTop: 6, borderTop: "1px solid #0f1f0f",
                    display: "inline-block", background: color + "20",
                    color, fontSize: 9, padding: "2px 6px", letterSpacing: 1,
                  }}>
                    {loc.status.toUpperCase()}
                  </div>
                </div>
              </Popup>
            </Marker>
          );
        })}
      </MapContainer>

      {/* ── Bottom-left legend (outside map so no z-index fight) ── */}
      <div style={{
        position: "absolute", bottom: 12, left: 12, zIndex: 1000,
        display: "flex", flexDirection: "column", gap: 4,
      }}>
        {statusCounts.map(({ status, color, count }) => (
          <div key={status} style={{
            display: "flex", alignItems: "center", gap: 8,
            background: "rgba(2,6,2,0.92)", border: "1px solid #0f1f0f",
            padding: "4px 10px",
          }}>
            <div style={{ width: 8, height: 8, borderRadius: "50%", background: color }} />
            <span style={{ color: "#6b7280", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1, textTransform: "uppercase" }}>
              {status}
            </span>
            <span style={{ color: color, fontFamily: "'JetBrains Mono', monospace", fontSize: 10, marginLeft: 4 }}>
              {count}
            </span>
          </div>
        ))}
      </div>

    </div>
  );
}

function ZoomButtons() {
  const map = useMap();
  const btnStyle: React.CSSProperties = {
    display: "block", width: 30, height: 30,
    background: "#0a140a", border: "1px solid #152015",
    color: "#22c55e", cursor: "pointer", fontSize: 18,
    fontFamily: "'JetBrains Mono', monospace", lineHeight: "28px", textAlign: "center",
  };
  return (
    <div style={{ position: "absolute", bottom: 12, right: 12, zIndex: 1000, display: "flex", flexDirection: "column", gap: 2 }}>
      <button style={btnStyle} onClick={() => map.zoomIn()}>+</button>
      <button style={btnStyle} onClick={() => map.zoomOut()}>−</button>
    </div>
  );
}
