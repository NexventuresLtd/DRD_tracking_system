import { useState, useEffect, useRef, useCallback } from "react";
import { MapContainer, TileLayer, Marker, Polyline, useMap } from "react-leaflet";
import L from "leaflet";
import api from "../services/api";

delete (L.Icon.Default.prototype as unknown as Record<string, unknown>)._getIconUrl;
L.Icon.Default.mergeOptions({ iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png", shadowUrl: "" });

interface TrailPoint { lat: number; lng: number; ts: string; speed?: number; }
interface SnapshotPos { user_id: string; lat: number; lng: number; ts: string; }

const COLORS = ["#22c55e", "#22c55e", "#f59e0b", "#ef4444", "#8b5cf6", "#06b6d4", "#ec4899"];

function userColor(idx: number) { return COLORS[idx % COLORS.length]; }

function userIcon(color: string) {
  return L.divIcon({
    className: "",
    html: `<div style="width:14px;height:14px;background:${color};border:2px solid #fff;border-radius:50%;box-shadow:0 0 6px ${color}88"></div>`,
    iconSize: [14, 14], iconAnchor: [7, 7],
  });
}

function FitBounds({ points }: { points: [number, number][] }) {
  const map = useMap();
  useEffect(() => {
    if (points.length > 0) map.fitBounds(L.latLngBounds(points), { padding: [40, 40] });
  }, [map, points]);
  return null;
}

export default function PlaybackPage() {
  const [userIds, setUserIds] = useState<string[]>([]);
  const [selectedUser, setSelectedUser] = useState<string>("");
  const [trail, setTrail] = useState<TrailPoint[]>([]);
  const [startDate, setStartDate] = useState(() => {
    const d = new Date(); d.setDate(d.getDate() - 1); return d.toISOString().slice(0, 16);
  });
  const [endDate, setEndDate] = useState(() => new Date().toISOString().slice(0, 16));
  const [loading, setLoading] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [frame, setFrame] = useState(0);
  const playRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [speed, setSpeed] = useState(5);

  useEffect(() => {
    api.get("/playback/users").then(({ data }) => setUserIds(data.user_ids || [])).catch(() => {});
  }, []);

  const loadTrail = useCallback(async () => {
    if (!selectedUser) return;
    setLoading(true);
    try {
      const { data } = await api.get(`/playback/trail/${selectedUser}`, {
        params: { start: new Date(startDate).toISOString(), end: new Date(endDate).toISOString() },
      });
      setTrail(data.points || []);
      setFrame(0);
      setPlaying(false);
    } catch { /**/ } finally { setLoading(false); }
  }, [selectedUser, startDate, endDate]);

  const togglePlay = () => {
    if (playing) {
      clearInterval(playRef.current!);
      setPlaying(false);
    } else {
      setPlaying(true);
      playRef.current = setInterval(() => {
        setFrame((f) => {
          if (f >= trail.length - 1) {
            clearInterval(playRef.current!);
            setPlaying(false);
            return trail.length - 1;
          }
          return f + 1;
        });
      }, 1000 / speed);
    }
  };

  useEffect(() => () => { if (playRef.current) clearInterval(playRef.current); }, []);

  const currentPoint = trail[frame];
  const trailUpToNow = trail.slice(0, frame + 1).map((p) => [p.lat, p.lng] as [number, number]);
  const allPoints = trail.map((p) => [p.lat, p.lng] as [number, number]);

  const fmtTime = (ts: string) => new Date(ts).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit" });

  return (
    <div className="p-6">
      <div className="mb-4">
        <h1 className="text-white font-bold text-xl">Mission Playback</h1>
        <p className="text-gray-500 text-sm mt-0.5">Replay field movements on the map</p>
      </div>

      {/* Controls */}
      <div className="rounded-xl p-4 mb-4 flex flex-wrap gap-4 items-end" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
        <div>
          <label className="text-gray-400 text-xs block mb-1">Field User</label>
          <select value={selectedUser} onChange={(e) => setSelectedUser(e.target.value)}
            className="px-3 py-2 rounded-lg text-white text-sm min-w-40"
            style={{ background: "#040804", border: "1px solid #374151" }}>
            <option value="">— select user —</option>
            {userIds.map((uid) => <option key={uid} value={uid}>{uid.slice(0, 8)}…</option>)}
          </select>
        </div>
        <div>
          <label className="text-gray-400 text-xs block mb-1">Start</label>
          <input type="datetime-local" value={startDate} onChange={(e) => setStartDate(e.target.value)}
            className="px-3 py-2 rounded-lg text-white text-sm"
            style={{ background: "#040804", border: "1px solid #374151" }} />
        </div>
        <div>
          <label className="text-gray-400 text-xs block mb-1">End</label>
          <input type="datetime-local" value={endDate} onChange={(e) => setEndDate(e.target.value)}
            className="px-3 py-2 rounded-lg text-white text-sm"
            style={{ background: "#040804", border: "1px solid #374151" }} />
        </div>
        <button onClick={loadTrail} disabled={loading || !selectedUser}
          className="px-5 py-2 rounded-lg text-white text-sm font-semibold hover:opacity-90 disabled:opacity-40"
          style={{ background: "#16a34a" }}>
          {loading ? "Loading…" : "Load Trail"}
        </button>
      </div>

      {trail.length > 0 && (
        <>
          {/* Playback bar */}
          <div className="rounded-xl p-4 mb-4" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
            <div className="flex items-center gap-4 flex-wrap">
              <button onClick={togglePlay}
                className="w-10 h-10 rounded-full flex items-center justify-center text-white font-bold"
                style={{ background: playing ? "#dc2626" : "#16a34a" }}>
                {playing ? "⏸" : "▶"}
              </button>
              <button onClick={() => { setFrame(0); setPlaying(false); }}
                className="w-8 h-8 rounded-full flex items-center justify-center text-white text-xs"
                style={{ background: "#0a140a" }}>
                ⏮
              </button>
              <div className="flex-1 min-w-40">
                <input type="range" min={0} max={trail.length - 1} value={frame}
                  onChange={(e) => { setFrame(+e.target.value); setPlaying(false); }}
                  className="w-full h-1.5 rounded-full appearance-none cursor-pointer"
                  style={{ accentColor: "#22c55e" }} />
              </div>
              <span className="text-gray-400 text-xs font-mono whitespace-nowrap">
                {frame + 1}/{trail.length}
                {currentPoint && <span className="ml-2">{fmtTime(currentPoint.ts)}</span>}
              </span>
              <div className="flex items-center gap-2">
                <span className="text-gray-500 text-xs">Speed</span>
                <select value={speed} onChange={(e) => { setSpeed(+e.target.value); if (playing) { clearInterval(playRef.current!); setPlaying(false); } }}
                  className="px-2 py-1 rounded text-white text-xs"
                  style={{ background: "#0a140a", border: "1px solid #374151" }}>
                  {[1, 2, 5, 10, 20].map((s) => <option key={s} value={s}>{s}x</option>)}
                </select>
              </div>
            </div>
            {currentPoint && (
              <div className="mt-2 flex gap-4 text-xs text-gray-500">
                <span>📍 {currentPoint.lat.toFixed(5)}, {currentPoint.lng.toFixed(5)}</span>
                {currentPoint.speed != null && <span>💨 {currentPoint.speed.toFixed(1)} m/s</span>}
              </div>
            )}
          </div>

          {/* Map */}
          <div className="rounded-xl overflow-hidden" style={{ height: 480 }}>
            <MapContainer center={allPoints[0] ?? [-1.9441, 30.0619]} zoom={14} style={{ height: "100%", width: "100%" }}>
              <TileLayer url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png" subdomains={["a", "b", "c"]} />
              <FitBounds points={allPoints} />
              {/* Full trail (faded) */}
              <Polyline positions={allPoints} color="#374151" weight={2} opacity={0.4} />
              {/* Completed trail */}
              {trailUpToNow.length >= 2 && <Polyline positions={trailUpToNow} color={userColor(0)} weight={3} />}
              {/* Current position */}
              {currentPoint && (
                <Marker position={[currentPoint.lat, currentPoint.lng]} icon={userIcon(userColor(0))} />
              )}
            </MapContainer>
          </div>
        </>
      )}

      {!loading && trail.length === 0 && selectedUser && (
        <div className="text-center py-16 text-gray-500">No location history for this time range</div>
      )}
      {!selectedUser && (
        <div className="text-center py-16 text-gray-500">Select a user and time range to load their trail</div>
      )}
    </div>
  );
}
