import { useState, useEffect, useCallback } from "react";
import { MapContainer, TileLayer, Polyline, Marker, useMapEvents } from "react-leaflet";
import L from "leaflet";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";

// Fix default icon issue
delete (L.Icon.Default.prototype as unknown as Record<string, unknown>)._getIconUrl;
L.Icon.Default.mergeOptions({ iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png", shadowUrl: "" });

interface Waypoint { lat: number; lng: number; name?: string; }
interface Route { id: string; name: string; description?: string; route_type: string; color: string; waypoint_count: number; created_at: string; }

const WP_ICON = L.divIcon({
  className: "",
  html: '<div style="width:12px;height:12px;background:#22c55e;border:2px solid #fff;border-radius:50%;box-shadow:0 0 6px rgba(34,197,94,0.6)"></div>',
  iconSize: [12, 12], iconAnchor: [6, 6],
});

const ROUTE_TYPES = ["patrol", "supply", "evacuation", "recon", "custom"];

function WaypointPlacer({ onPlace }: { onPlace: (lat: number, lng: number) => void }) {
  useMapEvents({ click: (e) => onPlace(e.latlng.lat, e.latlng.lng) });
  return null;
}

export default function RoutesPage() {
  const { user } = useAuthStore();
  const canEdit = user && ["operations_coordinator", "planning_officer", "team_leader"].includes(user.role);
  const [routes, setRoutes] = useState<Route[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Route | null>(null);
  const [selectedWaypoints, setSelectedWaypoints] = useState<Waypoint[]>([]);
  const [showCreate, setShowCreate] = useState(false);
  const [waypoints, setWaypoints] = useState<Waypoint[]>([]);
  const [form, setForm] = useState({ name: "", description: "", route_type: "patrol", color: "#22c55e" });
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      const { data } = await api.get("/routes");
      setRoutes(data);
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const loadRoute = async (route: Route) => {
    setSelected(route);
    try {
      const { data } = await api.get(`/routes/${route.id}`);
      setSelectedWaypoints((data.waypoints || []).map((w: { latitude: number; longitude: number; name?: string }) => ({ lat: w.latitude, lng: w.longitude, name: w.name })));
    } catch { setSelectedWaypoints([]); }
  };

  const addWaypoint = (lat: number, lng: number) => {
    if (!showCreate) return;
    setWaypoints((prev) => [...prev, { lat, lng }]);
  };

  const removeWaypoint = (i: number) => setWaypoints((prev) => prev.filter((_, j) => j !== i));

  const save = async () => {
    if (!form.name.trim() || waypoints.length < 2) return;
    setSaving(true);
    try {
      await api.post("/routes", {
        ...form,
        waypoints: waypoints.map((w) => ({ latitude: w.lat, longitude: w.lng })),
      });
      setShowCreate(false);
      setWaypoints([]);
      setForm({ name: "", description: "", route_type: "patrol", color: "#22c55e" });
      await load();
    } catch { /**/ } finally { setSaving(false); }
  };

  const deleteRoute = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!confirm("Delete this route?")) return;
    try { await api.delete(`/routes/${id}`); setRoutes((prev) => prev.filter((r) => r.id !== id)); if (selected?.id === id) setSelected(null); } catch { /**/ }
  };

  const activeWps = showCreate ? waypoints : selectedWaypoints;
  const polyPositions = activeWps.map((w) => [w.lat, w.lng] as [number, number]);

  return (
    <div className="h-full flex" style={{ minHeight: "calc(100vh - 64px)" }}>
      {/* Left panel */}
      <div className="w-72 shrink-0 flex flex-col" style={{ background: "#060d06", borderRight: "1px solid #0a140a" }}>
        <div className="p-4 flex items-center justify-between" style={{ borderBottom: "1px solid #0a140a" }}>
          <div>
            <h2 className="text-white font-bold text-sm">Routes</h2>
            <p className="text-gray-500 text-xs mt-0.5">{routes.length} routes</p>
          </div>
          {canEdit && (
            <button onClick={() => { setShowCreate(!showCreate); setSelected(null); setWaypoints([]); }}
              className="px-3 py-1.5 rounded-lg text-xs font-semibold text-white transition-all hover:opacity-90"
              style={{ background: showCreate ? "#dc2626" : "#16a34a" }}>
              {showCreate ? "Cancel" : "+ New"}
            </button>
          )}
        </div>

        {showCreate && (
          <div className="p-3 space-y-2" style={{ borderBottom: "1px solid #0a140a" }}>
            <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })}
              placeholder="Route name *" className="w-full px-3 py-2 rounded-lg text-white text-sm"
              style={{ background: "#040804", border: "1px solid #374151" }} />
            <input value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })}
              placeholder="Description" className="w-full px-3 py-2 rounded-lg text-white text-sm"
              style={{ background: "#040804", border: "1px solid #374151" }} />
            <div className="flex gap-2">
              <select value={form.route_type} onChange={(e) => setForm({ ...form, route_type: e.target.value })}
                className="flex-1 px-3 py-2 rounded-lg text-white text-sm capitalize"
                style={{ background: "#040804", border: "1px solid #374151" }}>
                {ROUTE_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
              <input type="color" value={form.color} onChange={(e) => setForm({ ...form, color: e.target.value })}
                className="w-10 h-10 rounded-lg cursor-pointer border-0"
                style={{ background: "#040804", border: "1px solid #374151" }} />
            </div>
            <div className="text-xs text-gray-500 px-1">
              {waypoints.length < 2 ? `Click map to add waypoints (${waypoints.length} added, need ≥2)` : `${waypoints.length} waypoints — ready to save`}
            </div>
            {waypoints.length > 0 && (
              <div className="space-y-1 max-h-32 overflow-y-auto">
                {waypoints.map((w, i) => (
                  <div key={i} className="flex items-center justify-between px-2 py-1 rounded text-xs" style={{ background: "#0a140a" }}>
                    <span className="text-gray-300">WP{i + 1} {w.lat.toFixed(4)}, {w.lng.toFixed(4)}</span>
                    <button onClick={() => removeWaypoint(i)} className="text-red-400 hover:text-red-300 ml-2">✕</button>
                  </div>
                ))}
              </div>
            )}
            <button onClick={save} disabled={saving || !form.name.trim() || waypoints.length < 2}
              className="w-full py-2 rounded-lg text-white text-sm font-semibold transition-all hover:opacity-90 disabled:opacity-40"
              style={{ background: "#16a34a" }}>
              {saving ? "Saving…" : "Save Route"}
            </button>
          </div>
        )}

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-4 text-center text-gray-500 text-sm">Loading…</div>
          ) : routes.length === 0 ? (
            <div className="p-4 text-center text-gray-500 text-sm">No routes yet</div>
          ) : (
            routes.map((r) => (
              <div key={r.id} onClick={() => loadRoute(r)}
                className="flex items-start gap-3 p-3 cursor-pointer transition-colors"
                style={{
                  background: selected?.id === r.id ? "#1d2d4a" : "transparent",
                  borderBottom: "1px solid #040804",
                }}>
                <div className="w-3 h-3 rounded-full mt-1 shrink-0" style={{ background: r.color }} />
                <div className="flex-1 min-w-0">
                  <p className="text-white text-sm font-medium truncate">{r.name}</p>
                  <p className="text-gray-500 text-xs capitalize">{r.route_type} · {r.waypoint_count} waypoints</p>
                </div>
                {canEdit && (
                  <button onClick={(e) => deleteRoute(r.id, e)} className="text-gray-600 hover:text-red-400 text-xs shrink-0">✕</button>
                )}
              </div>
            ))
          )}
        </div>
      </div>

      {/* Map */}
      <div className="flex-1 relative">
        <MapContainer
          center={[-1.9441, 30.0619]} zoom={12}
          style={{ height: "100%", width: "100%" }}
          className="z-0"
        >
          <TileLayer
            url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
            attribution='&copy; <a href="https://carto.com">CARTO</a>'
            subdomains={["a", "b", "c"]}
          />
          {showCreate && <WaypointPlacer onPlace={addWaypoint} />}
          {polyPositions.length >= 2 && (
            <Polyline positions={polyPositions} color={showCreate ? form.color : (selected?.color ?? "#22c55e")} weight={3} dashArray={showCreate ? "6 4" : undefined} />
          )}
          {activeWps.map((w, i) => (
            <Marker key={i} position={[w.lat, w.lng]} icon={WP_ICON} />
          ))}
        </MapContainer>

        {showCreate && (
          <div className="absolute top-3 left-1/2 -translate-x-1/2 z-10 px-4 py-2 rounded-full text-xs font-semibold text-white"
            style={{ background: "rgba(15,23,42,0.92)", border: "1px solid #16a34a" }}>
            Click on map to place waypoints
          </div>
        )}
        {selected && !showCreate && (
          <div className="absolute top-3 left-3 z-10 px-4 py-2 rounded-lg text-sm"
            style={{ background: "rgba(15,23,42,0.92)", border: "1px solid #0a140a" }}>
            <span className="text-white font-semibold">{selected.name}</span>
            <span className="text-gray-400 text-xs ml-2 capitalize">{selected.route_type}</span>
            <span className="text-gray-500 text-xs ml-2">{selectedWaypoints.length} waypoints</span>
          </div>
        )}
      </div>
    </div>
  );
}
