import { useState, useEffect, useCallback } from "react";
import { MapContainer, TileLayer, Circle, Polygon, useMapEvents } from "react-leaflet";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";

interface Fence { id: string; name: string; description?: string; zone_type: string; center_lat?: number; center_lng?: number; radius?: number; color: string; is_active: boolean; created_at: string; }

function CirclePlacer({ onPlace }: { onPlace: (lat: number, lng: number) => void }) {
  useMapEvents({ click: (e) => onPlace(e.latlng.lat, e.latlng.lng) });
  return null;
}

const ZONE_COLORS = ["#6366f1", "#16a34a", "#dc2626", "#16a34a", "#d97706", "#0891b2"];

export default function GeofencesTab() {
  const { user } = useAuthStore();
  const canEdit = user && ["operations_coordinator", "planning_officer", "team_leader"].includes(user.role);
  const [fences, setFences] = useState<Fence[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Fence | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [placing, setPlacing] = useState(false);
  const [pendingCenter, setPendingCenter] = useState<{ lat: number; lng: number } | null>(null);
  const [form, setForm] = useState({ name: "", description: "", radius: "500", color: "#6366f1" });
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      const { data } = await api.get("/geofences");
      setFences(data);
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const handleMapClick = (lat: number, lng: number) => {
    if (!placing) return;
    setPendingCenter({ lat, lng });
    setPlacing(false);
  };

  const save = async () => {
    if (!form.name.trim() || !pendingCenter) return;
    setSaving(true);
    try {
      await api.post("/geofences", {
        name: form.name,
        description: form.description,
        zone_type: "circle",
        center_lat: pendingCenter.lat,
        center_lng: pendingCenter.lng,
        radius: parseFloat(form.radius),
        color: form.color,
      });
      setShowCreate(false);
      setPendingCenter(null);
      setForm({ name: "", description: "", radius: "500", color: "#6366f1" });
      await load();
    } catch { /**/ } finally { setSaving(false); }
  };

  const deleteFence = async (id: string) => {
    if (!confirm("Delete this geofence?")) return;
    try {
      await api.delete(`/geofences/${id}`);
      setFences((prev) => prev.filter((f) => f.id !== id));
      if (selected?.id === id) setSelected(null);
    } catch { /**/ }
  };

  return (
    <div className="h-full flex" style={{ minHeight: "calc(100vh - 64px)" }}>
      {/* Left panel */}
      <div className="w-72 shrink-0 flex flex-col" style={{ background: "#060d06", borderRight: "1px solid #0a140a" }}>
        <div className="p-4 flex items-center justify-between" style={{ borderBottom: "1px solid #0a140a" }}>
          <div>
            <h2 className="text-white font-bold text-sm">Geofences</h2>
            <p className="text-gray-500 text-xs mt-0.5">{fences.length} zones</p>
          </div>
          {canEdit && (
            <button onClick={() => { setShowCreate(!showCreate); setPendingCenter(null); }}
              className="px-3 py-1.5 rounded-lg text-xs font-semibold text-white"
              style={{ background: showCreate ? "#dc2626" : "#16a34a" }}>
              {showCreate ? "Cancel" : "+ New"}
            </button>
          )}
        </div>

        {showCreate && (
          <div className="p-3 space-y-2" style={{ borderBottom: "1px solid #0a140a" }}>
            <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })}
              placeholder="Zone name *" className="w-full px-3 py-2 rounded-lg text-white text-sm"
              style={{ background: "#040804", border: "1px solid #374151" }} />
            <input value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })}
              placeholder="Description" className="w-full px-3 py-2 rounded-lg text-white text-sm"
              style={{ background: "#040804", border: "1px solid #374151" }} />
            <div className="flex gap-2 items-center">
              <input value={form.radius} onChange={(e) => setForm({ ...form, radius: e.target.value })}
                placeholder="Radius (m)" type="number" min="50"
                className="flex-1 px-3 py-2 rounded-lg text-white text-sm"
                style={{ background: "#040804", border: "1px solid #374151" }} />
              <div className="flex gap-1">
                {ZONE_COLORS.map((c) => (
                  <button key={c} onClick={() => setForm({ ...form, color: c })}
                    className="w-5 h-5 rounded-full border-2 transition-all"
                    style={{ background: c, borderColor: form.color === c ? "#fff" : "transparent" }} />
                ))}
              </div>
            </div>
            {!pendingCenter ? (
              <button onClick={() => setPlacing(true)}
                className="w-full py-2 rounded-lg text-white text-xs font-semibold"
                style={{ background: placing ? "#166534" : "#374151" }}>
                {placing ? "Click map to place center…" : "📍 Click to place on map"}
              </button>
            ) : (
              <div className="text-xs text-green-400 px-1">
                Center: {pendingCenter.lat.toFixed(4)}, {pendingCenter.lng.toFixed(4)}
                <button onClick={() => { setPendingCenter(null); setPlacing(false); }} className="ml-2 text-red-400">✕</button>
              </div>
            )}
            <button onClick={save} disabled={saving || !form.name.trim() || !pendingCenter}
              className="w-full py-2 rounded-lg text-white text-sm font-semibold disabled:opacity-40"
              style={{ background: "#16a34a" }}>
              {saving ? "Saving…" : "Create Geofence"}
            </button>
          </div>
        )}

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-4 text-center text-gray-500 text-sm">Loading…</div>
          ) : fences.length === 0 ? (
            <div className="p-4 text-center text-gray-500 text-sm">No geofences</div>
          ) : (
            fences.map((f) => (
              <div key={f.id} onClick={() => setSelected(selected?.id === f.id ? null : f)}
                className="flex items-center gap-3 p-3 cursor-pointer"
                style={{ background: selected?.id === f.id ? "#1d2d4a" : "transparent", borderBottom: "1px solid #040804" }}>
                <div className="w-3 h-3 rounded-full shrink-0 border-2" style={{ background: `${f.color}40`, borderColor: f.color }} />
                <div className="flex-1 min-w-0">
                  <p className="text-white text-sm font-medium truncate">{f.name}</p>
                  <p className="text-gray-500 text-xs">{f.zone_type} · {f.radius ? `r=${f.radius}m` : "polygon"}</p>
                </div>
                {canEdit && (
                  <button onClick={(e) => { e.stopPropagation(); deleteFence(f.id); }}
                    className="text-gray-600 hover:text-red-400 text-xs shrink-0">✕</button>
                )}
              </div>
            ))
          )}
        </div>
      </div>

      {/* Map */}
      <div className="flex-1 relative">
        <MapContainer center={[-1.9441, 30.0619]} zoom={12} style={{ height: "100%", width: "100%" }}>
          <TileLayer
            url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
            subdomains={["a", "b", "c"]}
          />
          {(showCreate || placing) && <CirclePlacer onPlace={handleMapClick} />}
          {pendingCenter && (
            <Circle center={[pendingCenter.lat, pendingCenter.lng]}
              radius={parseFloat(form.radius) || 500}
              color={form.color} fillColor={form.color} fillOpacity={0.15} dashArray="6 4" />
          )}
          {fences.map((f) => f.center_lat && f.center_lng ? (
            <Circle key={f.id}
              center={[f.center_lat, f.center_lng]}
              radius={f.radius ?? 500}
              color={f.color} fillColor={f.color}
              fillOpacity={selected?.id === f.id ? 0.25 : 0.1}
              weight={selected?.id === f.id ? 2 : 1}
            />
          ) : null)}
        </MapContainer>
        {placing && (
          <div className="absolute top-3 left-1/2 -translate-x-1/2 z-10 px-4 py-2 rounded-full text-xs font-semibold text-white"
            style={{ background: "rgba(15,23,42,0.92)", border: "1px solid #6366f1" }}>
            Click on map to place geofence center
          </div>
        )}
      </div>
    </div>
  );
}
