import React, { useState, useEffect, useRef, useCallback } from "react";
import { MapContainer, TileLayer, Marker, Polyline, Circle, Tooltip } from "react-leaflet";
import L from "leaflet";
import {
  FiNavigation, FiAlertCircle, FiCheckCircle, FiMapPin,
  FiRefreshCw, FiLogOut, FiWifiOff,
  FiCamera, FiUploadCloud, FiX,
} from "react-icons/fi";
import * as api from "../services/api";

// ── Types ──────────────────────────────────────────────────────────────────────
interface Waypoint {
  id: string;
  sequence_order: number;
  latitude: number;
  longitude: number;
  label: string | null;
  poi_type: string | null;
}

interface AssignedRoute {
  id: string;
  name: string;
  color: string;
  waypoints: Waypoint[];
}

interface GeoPos { lat: number; lng: number }

// ── Coordinate Format Cycling ──────────────────────────────────────────────────
function toDMS(deg: number, isLat: boolean): string {
  const abs = Math.abs(deg);
  const d = Math.floor(abs);
  const mFull = (abs - d) * 60;
  const m = Math.floor(mFull);
  const s = ((mFull - m) * 60).toFixed(1);
  const dir = isLat ? (deg >= 0 ? "N" : "S") : (deg >= 0 ? "E" : "W");
  return `${d}° ${m}' ${s}" ${dir}`;
}

function toUTMApprox(lat: number, lng: number): string {
  const zone = Math.floor((lng + 180) / 6) + 1;
  const hemi = lat >= 0 ? "N" : "S";
  const latR = lat * Math.PI / 180;
  const lngR = lng * Math.PI / 180;
  const a = 6378137;
  const k0 = 0.9996;
  const e2 = 0.00669438;
  const lngOrigin = ((zone - 1) * 6 - 180 + 3) * Math.PI / 180;
  const N = a / Math.sqrt(1 - e2 * Math.sin(latR) ** 2);
  const T = Math.tan(latR) ** 2;
  const C = e2 / (1 - e2) * Math.cos(latR) ** 2;
  const A = Math.cos(latR) * (lngR - lngOrigin);
  const easting = k0 * N * (A + (1 - T + C) * A ** 3 / 6) + 500000;
  const northing = k0 * (N * Math.sin(latR) * Math.cos(latR) * A ** 2 / 2);
  return `${zone}${hemi} ${Math.round(easting)}E ${Math.round(Math.abs(northing))}N`;
}

function formatCoordsAll(lat: number, lng: number) {
  return [
    { label: "DD",  value: `${lat.toFixed(6)}, ${lng.toFixed(6)}` },
    { label: "DMS", value: `${toDMS(lat, true)}  ${toDMS(lng, false)}` },
    { label: "UTM", value: toUTMApprox(lat, lng) },
  ];
}

// ── Haversine ──────────────────────────────────────────────────────────────────
function distanceM(a: GeoPos, b: GeoPos): number {
  const R = 6371000;
  const dLat = (b.lat - a.lat) * Math.PI / 180;
  const dLng = (b.lng - a.lng) * Math.PI / 180;
  const x = Math.sin(dLat / 2) ** 2 +
    Math.cos(a.lat * Math.PI / 180) * Math.cos(b.lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

// ── Custom marker icon ─────────────────────────────────────────────────────────
const myIcon = L.divIcon({
  className: "",
  html: `<div style="width:18px;height:18px;border-radius:50%;background:#3b82f6;border:3px solid white;box-shadow:0 0 0 2px #3b82f6,0 0 12px rgba(59,130,246,0.6)"></div>`,
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});

const waypointIcon = (reached: boolean, color: string) => L.divIcon({
  className: "",
  html: `<div style="width:14px;height:14px;border-radius:50%;background:${reached ? "#22c55e" : color};border:2px solid white;opacity:${reached ? 0.5 : 1}"></div>`,
  iconSize: [14, 14],
  iconAnchor: [7, 7],
});

// ── SOS Countdown ─────────────────────────────────────────────────────────────
function SOSCountdown({ onCancel, onConfirm }: { onCancel: () => void; onConfirm: () => void }) {
  const [secs, setSecs] = useState(5);
  useEffect(() => {
    if (secs <= 0) { onConfirm(); return; }
    const t = setTimeout(() => setSecs(s => s - 1), 1000);
    return () => clearTimeout(t);
  }, [secs, onConfirm]);
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70">
      <div className="w-72 rounded-2xl overflow-hidden" style={{ background: "#0a0f1e", border: "2px solid #dc2626" }}>
        <div className="bg-red-600 px-6 py-4 text-center">
          <div className="text-white font-black text-xl tracking-widest">SOS ALERT</div>
          <div className="text-red-100 text-xs mt-1">Sending in {secs}s…</div>
        </div>
        <div className="p-6 text-center">
          <div className="text-7xl font-black text-red-500 leading-none mb-4">{secs}</div>
          <div className="text-slate-400 text-sm mb-6">Emergency signal will be broadcast to all commanders</div>
          <button
            onClick={onCancel}
            className="w-full py-3 rounded-xl font-bold text-white tracking-widest border-none cursor-pointer"
            style={{ background: "#1e293b" }}
          >
            CANCEL
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Main Component ─────────────────────────────────────────────────────────────
export default function FieldUserView() {
  const [pos, setPos] = useState<GeoPos | null>(null);
  const [copiedCoord, setCopiedCoord] = useState<string | null>(null);
  const [route, setRoute] = useState<AssignedRoute | null>(null);
  const [reached, setReached] = useState<Set<string>>(new Set());
  const [sosActive, setSosActive] = useState(false);
  const [sosConfirmed, setSosConfirmed] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);
  const [evidenceUploading, setEvidenceUploading] = useState(false);
  const [evidenceStatus, setEvidenceStatus] = useState<"idle" | "success" | "error">("idle");
  const [evidenceCaption, setEvidenceCaption] = useState("");
  const [showEvidenceCaption, setShowEvidenceCaption] = useState(false);
  const [pendingFile, setPendingFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const watchRef = useRef<number | null>(null);

  const copyCoord = (value: string, label: string) => {
    navigator.clipboard.writeText(value).catch(() => {});
    setCopiedCoord(label);
    setTimeout(() => setCopiedCoord(null), 1500);
  };

  // GPS watch
  useEffect(() => {
    if (!navigator.geolocation) return;
    watchRef.current = navigator.geolocation.watchPosition(
      geo => {
        const p = { lat: geo.coords.latitude, lng: geo.coords.longitude };
        setPos(p);
        setLastUpdate(new Date());
        // push location to backend
        api.updateLocation({ latitude: p.lat, longitude: p.lng, accuracy: geo.coords.accuracy }).catch(() => {});
      },
      () => {},
      { enableHighAccuracy: true, maximumAge: 5000 },
    );
    return () => { if (watchRef.current != null) navigator.geolocation.clearWatch(watchRef.current); };
  }, []);

  // Load assigned route
  const loadRoute = useCallback(async () => {
    setIsLoading(true);
    try {
      const mySession = await api.getMyRouteFollowSession();
      if (mySession?.data?.route_id) {
        const r = await api.getRoute(mySession.data.route_id);
        if (r?.data) setRoute(r.data as AssignedRoute);
      }
    } catch { /* no route */ }
    setIsLoading(false);
  }, []);

  useEffect(() => { loadRoute(); }, [loadRoute]);

  const handleReached = async (wp: Waypoint) => {
    setReached(prev => new Set([...prev, wp.id]));
    // mark via API if session exists
    try {
      const sess = await api.getMyRouteFollowSession();
      if (sess?.data?.id) {
        await api.post?.(`/api/v1/route-follow-sessions/${sess.data.id}/checkpoint`, { waypoint_id: wp.id, latitude: pos?.lat ?? wp.latitude, longitude: pos?.lng ?? wp.longitude });
      }
    } catch { /* silent */ }
  };

  const handleSOSConfirm = async () => {
    setSosActive(false);
    setSosConfirmed(true);
    try {
      await api.updateLocation({ latitude: pos?.lat ?? 0, longitude: pos?.lng ?? 0, flag_type: "help" });
    } catch { /* silent */ }
  };

  const handleLogout = () => {
    localStorage.removeItem("access_token");
    localStorage.removeItem("refresh_token");
    window.location.href = "/login";
  };

  const handleEvidenceFileSelected = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPendingFile(file);
    setShowEvidenceCaption(true);
    // reset input so same file can be re-selected
    e.target.value = "";
  };

  const handleEvidenceUpload = async () => {
    if (!pendingFile) return;
    setEvidenceUploading(true);
    setEvidenceStatus("idle");
    try {
      await api.uploadEvidence(pendingFile, evidenceCaption || undefined);
      setEvidenceStatus("success");
      setPendingFile(null);
      setEvidenceCaption("");
      setShowEvidenceCaption(false);
      setTimeout(() => setEvidenceStatus("idle"), 3000);
    } catch {
      setEvidenceStatus("error");
      setTimeout(() => setEvidenceStatus("idle"), 3000);
    } finally {
      setEvidenceUploading(false);
    }
  };

  const cancelEvidence = () => {
    setPendingFile(null);
    setEvidenceCaption("");
    setShowEvidenceCaption(false);
  };

  const nextWaypoint = route?.waypoints.find(wp => !reached.has(wp.id));
  const distToNext = (pos && nextWaypoint)
    ? distanceM(pos, { lat: nextWaypoint.latitude, lng: nextWaypoint.longitude })
    : null;

  const mapCenter: [number, number] = pos ? [pos.lat, pos.lng] : [-1.9441, 30.0619];

  return (
    <div className="h-screen w-screen flex flex-col" style={{ background: "#050C1A", color: "#fff", fontFamily: "'Poppins', sans-serif" }}>
      {/* SOS countdown overlay */}
      {sosActive && <SOSCountdown onCancel={() => setSosActive(false)} onConfirm={handleSOSConfirm} />}

      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-white/10 shrink-0"
        style={{ background: "#0A1628" }}>
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full animate-pulse" style={{ background: pos ? "#22c55e" : "#ef4444" }} />
          <span className="text-[11px] font-bold tracking-widest text-slate-300">FIELD UNIT</span>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={loadRoute} className="p-1.5 rounded bg-transparent border-none cursor-pointer text-slate-400 hover:text-white transition-colors">
            <FiRefreshCw size={14} />
          </button>
          <button onClick={handleLogout} className="p-1.5 rounded bg-transparent border-none cursor-pointer text-slate-400 hover:text-white transition-colors">
            <FiLogOut size={14} />
          </button>
        </div>
      </div>

      {/* Map */}
      <div className="flex-1 relative">
        <MapContainer center={mapCenter} zoom={15} className="w-full h-full" zoomControl={false}>
          <TileLayer
            url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png"
            subdomains={["a", "b", "c", "d"]}
            attribution="CartoDB"
          />
          {pos && (
            <>
              <Marker position={[pos.lat, pos.lng]} icon={myIcon}>
                <Tooltip permanent direction="top" offset={[0, -12]}>
                  <span style={{ fontSize: "9px", fontWeight: 700, color: "#3b82f6" }}>YOU</span>
                </Tooltip>
              </Marker>
              <Circle center={[pos.lat, pos.lng]} radius={20}
                pathOptions={{ color: "#3b82f6", fillColor: "#3b82f6", fillOpacity: 0.15, weight: 1 }} />
            </>
          )}
          {route && (
            <>
              <Polyline
                positions={route.waypoints.map(w => [w.latitude, w.longitude] as [number, number])}
                color={route.color}
                weight={3}
                opacity={0.7}
              />
              {route.waypoints.map(wp => (
                <Marker key={wp.id} position={[wp.latitude, wp.longitude]}
                  icon={waypointIcon(reached.has(wp.id), route.color)}>
                  <Tooltip direction="top" offset={[0, -8]}>
                    <span style={{ fontSize: "9px" }}>{wp.label ?? `WP${wp.sequence_order + 1}`}</span>
                  </Tooltip>
                </Marker>
              ))}
            </>
          )}
        </MapContainer>

        {/* GPS overlay */}
        {!pos && (
          <div className="absolute top-3 left-1/2 -translate-x-1/2 z-[1000] px-3 py-1.5 rounded-full flex items-center gap-1.5"
            style={{ background: "rgba(239,68,68,0.15)", border: "1px solid rgba(239,68,68,0.4)" }}>
            <FiWifiOff size={10} className="text-red-400" />
            <span className="text-[9px] font-bold text-red-400">NO GPS</span>
          </div>
        )}
      </div>

      {/* Bottom panel */}
      <div className="shrink-0 border-t border-white/10" style={{ background: "#0A1628" }}>
        {/* Coordinate block — all 3 formats always visible */}
        <div className="px-4 pt-3 pb-2 border-b border-white/8">
          <div className="flex items-center gap-1.5 mb-1.5">
            <FiMapPin size={10} className="text-slate-500 shrink-0" />
            <span className="text-[8px] font-bold tracking-widest text-slate-500 uppercase">
              {pos ? "Position" : "Acquiring GPS…"}
            </span>
          </div>
          {pos ? (
            <div className="space-y-1 font-mono" style={{ fontFamily: "monospace" }}>
              {formatCoordsAll(pos.lat, pos.lng).map(({ label, value }) => (
                <div key={label} className="flex items-center gap-1.5">
                  <span className="text-[8px] font-bold text-slate-500 w-7 shrink-0">{label}</span>
                  <span className="text-[10px] text-slate-200 flex-1 truncate">{value}</span>
                  <button
                    onClick={() => copyCoord(value, label)}
                    className="shrink-0 text-slate-600 hover:text-blue-400 bg-transparent border-none cursor-pointer text-[10px] px-1"
                    title={`Copy ${label}`}
                  >
                    {copiedCoord === label ? "✓" : "⎘"}
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-[10px] text-slate-600 italic">Waiting for GPS lock…</div>
          )}
        </div>

        {/* Route / waypoint status */}
        {isLoading ? (
          <div className="flex items-center justify-center gap-2 py-4">
            <div className="w-3 h-3 border-2 border-blue-400/30 border-t-blue-400 rounded-full animate-spin" />
            <span className="text-[10px] text-slate-500">Loading route…</span>
          </div>
        ) : route ? (
          <div className="px-4 py-3">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-1.5">
                <FiNavigation size={11} className="text-blue-400" />
                <span className="text-[11px] font-bold text-foreground truncate max-w-[180px]">{route.name}</span>
              </div>
              <span className="text-[8px] text-slate-500">
                {reached.size}/{route.waypoints.length} wp
              </span>
            </div>
            {/* Progress bar */}
            <div className="w-full h-1 rounded-full mb-3" style={{ background: "rgba(255,255,255,0.08)" }}>
              <div className="h-1 rounded-full transition-all duration-500"
                style={{ width: `${route.waypoints.length ? (reached.size / route.waypoints.length) * 100 : 0}%`, background: route.color }} />
            </div>
            {/* Next waypoint */}
            {nextWaypoint ? (
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-[9px] text-slate-500 uppercase tracking-wider">Next waypoint</div>
                  <div className="text-[11px] font-semibold text-foreground">
                    {nextWaypoint.label ?? `WP${nextWaypoint.sequence_order + 1}`}
                    {distToNext != null && (
                      <span className="text-slate-400 font-normal ml-1.5">
                        {distToNext < 1000 ? `${Math.round(distToNext)}m` : `${(distToNext / 1000).toFixed(1)}km`}
                      </span>
                    )}
                  </div>
                </div>
                <button
                  onClick={() => handleReached(nextWaypoint)}
                  className="flex items-center gap-1 px-3 py-1.5 rounded-lg font-bold text-[10px] cursor-pointer border-none transition-all"
                  style={{ background: "rgba(34,197,94,0.2)", color: "#22c55e", border: "1px solid rgba(34,197,94,0.4)" }}
                >
                  <FiCheckCircle size={11} /> REACHED
                </button>
              </div>
            ) : (
              <div className="flex items-center gap-2 text-green-400">
                <FiCheckCircle size={13} />
                <span className="text-[11px] font-bold">All waypoints reached!</span>
              </div>
            )}
            {/* Last update */}
            {lastUpdate && (
              <div className="text-[8px] text-slate-600 mt-2">
                Updated {lastUpdate.toLocaleTimeString()}
              </div>
            )}
          </div>
        ) : (
          <div className="flex items-center justify-center gap-2 py-4 text-slate-600">
            <FiNavigation size={13} className="opacity-40" />
            <span className="text-[10px]">No route assigned by command</span>
          </div>
        )}

        {/* Evidence section */}
        <div className="px-4 pt-2 pb-1">
          {/* Hidden file input */}
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            capture="environment"
            className="hidden"
            onChange={handleEvidenceFileSelected}
          />

          {/* Caption + upload panel — shown after file is selected */}
          {showEvidenceCaption && pendingFile && (
            <div className="mb-2 rounded-xl overflow-hidden" style={{ background: "rgba(59,130,246,0.08)", border: "1px solid rgba(59,130,246,0.25)" }}>
              <div className="flex items-center justify-between px-3 py-2 border-b border-white/5">
                <span className="text-[10px] font-bold text-blue-400 tracking-wider">ATTACH EVIDENCE</span>
                <button onClick={cancelEvidence} className="text-slate-500 hover:text-white border-none bg-transparent cursor-pointer p-0">
                  <FiX size={13} />
                </button>
              </div>
              <div className="px-3 py-2 space-y-2">
                <div className="text-[9px] text-slate-400 truncate">{pendingFile.name}</div>
                <input
                  type="text"
                  placeholder="Caption (optional)"
                  value={evidenceCaption}
                  onChange={e => setEvidenceCaption(e.target.value)}
                  className="w-full rounded-lg px-2.5 py-1.5 text-[11px] text-white outline-none"
                  style={{ background: "rgba(255,255,255,0.06)", border: "1px solid rgba(255,255,255,0.1)" }}
                />
                <button
                  onClick={handleEvidenceUpload}
                  disabled={evidenceUploading}
                  className="w-full py-1.5 rounded-lg font-bold text-[10px] tracking-wider border-none cursor-pointer transition-all flex items-center justify-center gap-1.5"
                  style={{ background: evidenceUploading ? "rgba(59,130,246,0.3)" : "#2563eb", color: "#fff", opacity: evidenceUploading ? 0.7 : 1 }}
                >
                  {evidenceUploading
                    ? <><div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" /> UPLOADING…</>
                    : <><FiUploadCloud size={11} /> SUBMIT EVIDENCE</>
                  }
                </button>
              </div>
            </div>
          )}

          {/* Status messages */}
          {evidenceStatus === "success" && (
            <div className="mb-2 py-2 px-3 rounded-lg text-[10px] font-bold text-green-400 flex items-center gap-1.5"
              style={{ background: "rgba(34,197,94,0.1)", border: "1px solid rgba(34,197,94,0.3)" }}>
              <FiCheckCircle size={11} /> Evidence submitted to command
            </div>
          )}
          {evidenceStatus === "error" && (
            <div className="mb-2 py-2 px-3 rounded-lg text-[10px] font-bold text-red-400 flex items-center gap-1.5"
              style={{ background: "rgba(239,68,68,0.1)", border: "1px solid rgba(239,68,68,0.3)" }}>
              <FiX size={11} /> Upload failed — check connection
            </div>
          )}

          {/* Evidence trigger button */}
          {!showEvidenceCaption && (
            <button
              onClick={() => fileInputRef.current?.click()}
              className="w-full py-2.5 rounded-xl font-bold text-[11px] tracking-wider cursor-pointer border-none transition-all active:scale-[0.98] flex items-center justify-center gap-2 mb-2"
              style={{ background: "rgba(59,130,246,0.15)", color: "#60a5fa", border: "1px solid rgba(59,130,246,0.3)" }}
            >
              <FiCamera size={13} />
              SUBMIT EVIDENCE
            </button>
          )}
        </div>

        {/* SOS button */}
        {sosConfirmed ? (
          <div className="mx-4 mb-4 py-3 rounded-xl text-center animate-pulse"
            style={{ background: "rgba(220,38,38,0.2)", border: "1px solid rgba(220,38,38,0.5)" }}>
            <FiAlertCircle size={14} className="inline mr-2 text-red-400" />
            <span className="text-[11px] font-bold text-red-400">SOS ACTIVE — Command notified</span>
          </div>
        ) : (
          <button
            onClick={() => setSosActive(true)}
            className="mx-4 mb-4 w-[calc(100%-2rem)] py-3 rounded-xl font-black text-sm tracking-widest cursor-pointer border-none transition-all active:scale-[0.98]"
            style={{ background: "#dc2626", color: "#fff", boxShadow: "0 0 16px rgba(220,38,38,0.4)" }}
          >
            <FiAlertCircle size={14} className="inline mr-2" />
            SOS EMERGENCY
          </button>
        )}
      </div>
    </div>
  );
}
