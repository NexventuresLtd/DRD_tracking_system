import { useState, useEffect, useRef, useCallback } from "react";
import { MapContainer, TileLayer, Marker, useMapEvents } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";

delete (L.Icon.Default.prototype as unknown as Record<string, unknown>)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
  shadowUrl: "",
});

function MapClickLayer({ onPick }: { onPick: (lat: number, lng: number) => void }) {
  useMapEvents({ click: (e) => onPick(e.latlng.lat, e.latlng.lng) });
  return null;
}

function MapPicker({ value, onChange }: {
  value: { lat: string; lng: string };
  onChange: (lat: string, lng: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [pin, setPin] = useState<[number, number] | null>(
    value.lat && value.lng ? [parseFloat(value.lat), parseFloat(value.lng)] : null
  );

  const handlePick = (lat: number, lng: number) => {
    setPin([lat, lng]);
    onChange(lat.toFixed(6), lng.toFixed(6));
  };

  const handleConfirm = () => setOpen(false);

  const center: [number, number] = pin ?? [-1.9441, 30.0619];

  const hasValue = !!(value.lat && value.lng);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        style={{
          width: "100%", padding: "9px 12px",
          background: "#040804", border: `1px solid ${hasValue ? "rgba(22,163,74,0.4)" : "#374151"}`,
          color: hasValue ? "#22c55e" : "#6b7280",
          borderRadius: 8, cursor: "pointer", fontSize: 13,
          display: "flex", alignItems: "center", gap: 8, textAlign: "left",
        }}
      >
        <span>📍</span>
        <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
          {hasValue ? `${parseFloat(value.lat).toFixed(5)}, ${parseFloat(value.lng).toFixed(5)}` : "Click to pick location on map"}
        </span>
        {hasValue && (
          <span
            onClick={(e) => { e.stopPropagation(); onChange("", ""); setPin(null); }}
            style={{ color: "#6b7280", fontSize: 11, padding: "0 2px" }}
          >✕</span>
        )}
      </button>

      {open && (
        <div style={{
          position: "fixed", inset: 0, zIndex: 9999,
          background: "rgba(0,0,0,0.85)",
          display: "flex", flexDirection: "column",
        }}>
          <div style={{
            display: "flex", alignItems: "center", justifyContent: "space-between",
            padding: "12px 16px", background: "#060d06",
            borderBottom: "1px solid #0a140a",
          }}>
            <div>
              <div style={{ color: "#fff", fontWeight: 600, fontSize: 14 }}>Pick Location</div>
              <div style={{ color: "#6b7280", fontSize: 12 }}>
                {pin ? `${pin[0].toFixed(5)}, ${pin[1].toFixed(5)}` : "Tap anywhere on the map"}
              </div>
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <button onClick={() => setOpen(false)}
                style={{ padding: "6px 14px", background: "#0a140a", border: "1px solid #374151", color: "#9ca3af", borderRadius: 8, cursor: "pointer", fontSize: 13 }}>
                Cancel
              </button>
              <button onClick={handleConfirm} disabled={!pin}
                style={{ padding: "6px 14px", background: pin ? "#16a34a" : "#374151", color: "#fff", border: "none", borderRadius: 8, cursor: pin ? "pointer" : "default", fontSize: 13, fontWeight: 600 }}>
                Confirm
              </button>
            </div>
          </div>
          <div style={{ flex: 1 }}>
            <MapContainer center={center} zoom={pin ? 14 : 10} style={{ height: "100%", width: "100%" }}>
              <TileLayer url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png" subdomains={["a","b","c"]} />
              <MapClickLayer onPick={handlePick} />
              {pin && <Marker position={pin} />}
            </MapContainer>
          </div>
        </div>
      )}
    </>
  );
}

interface Evidence {
  id: string;
  title: string;
  evidence_type: string;
  description?: string;
  file_url?: string;
  latitude?: number;
  longitude?: number;
  mission_id?: string;
  created_at: string;
  uploaded_by: string;
}

const TYPE_ICONS: Record<string, string> = {
  image: "🖼",
  video: "🎬",
  audio: "🎙",
  document: "📄",
  note: "📝",
};

const TYPE_COLORS: Record<string, string> = {
  image: "#16a34a",
  video: "#7c3aed",
  audio: "#0891b2",
  document: "#d97706",
  note: "#16a34a",
};

export default function EvidencePage() {
  const { user } = useAuthStore();
  const [evidence, setEvidence] = useState<Evidence[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [filter, setFilter] = useState("all");
  const [preview, setPreview] = useState<Evidence | null>(null);
  const [form, setForm] = useState({
    title: "", evidence_type: "image", description: "", latitude: "", longitude: "", mission_id: "",
  });
  const [file, setFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    try {
      const { data } = await api.get("/evidence");
      setEvidence(data);
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const filtered = filter === "all" ? evidence : evidence.filter((e) => e.evidence_type === filter);

  const upload = async () => {
    if (!form.title.trim()) return;
    setSaving(true);
    try {
      const fd = new FormData();
      Object.entries(form).forEach(([k, v]) => { if (v) fd.append(k, v); });
      if (file) fd.append("file", file);
      await api.post("/evidence", fd, { headers: { "Content-Type": "multipart/form-data" } });
      setShowModal(false);
      setForm({ title: "", evidence_type: "image", description: "", latitude: "", longitude: "", mission_id: "" });
      setFile(null);
      await load();
    } catch { /**/ } finally { setSaving(false); }
  };

  const deleteItem = async (id: string) => {
    if (!confirm("Delete this evidence?")) return;
    try { await api.delete(`/evidence/${id}`); setEvidence((prev) => prev.filter((e) => e.id !== id)); } catch { /**/ }
  };

  const fmtDate = (s: string) => new Date(s).toLocaleDateString("en-GB", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });

  const BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:1104";

  return (
    <div className="p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-white font-bold text-xl">Evidence</h1>
          <p className="text-gray-500 text-sm mt-0.5">{evidence.length} items collected</p>
        </div>
        <button onClick={() => setShowModal(true)}
          className="px-4 py-2 rounded-lg text-white text-sm font-semibold hover:opacity-90"
          style={{ background: "#16a34a" }}>
          + Upload
        </button>
      </div>

      {/* Type filter */}
      <div className="flex gap-2 mb-6 flex-wrap">
        {["all", "image", "video", "audio", "document", "note"].map((t) => (
          <button key={t} onClick={() => setFilter(t)}
            className="px-3 py-1.5 rounded-full text-xs font-semibold capitalize transition-all"
            style={{
              background: filter === t ? "#166534" : "#0a140a",
              color: filter === t ? "#fff" : "#9ca3af",
              border: "1px solid transparent",
            }}>
            {t === "all" ? `All (${evidence.length})` : `${TYPE_ICONS[t]} ${t} (${evidence.filter((e) => e.evidence_type === t).length})`}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="text-center py-16 text-gray-500">Loading…</div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 text-gray-500">No evidence yet</div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {filtered.map((ev) => {
            const color = TYPE_COLORS[ev.evidence_type] ?? "#6b7280";
            const isImage = ev.evidence_type === "image" && ev.file_url;
            return (
              <div key={ev.id} className="rounded-xl overflow-hidden cursor-pointer group"
                style={{ background: "#060d06", border: "1px solid #0a140a" }}
                onClick={() => setPreview(ev)}>
                {isImage ? (
                  <div className="h-36 overflow-hidden">
                    <img src={`${BASE_URL}${ev.file_url}`} alt={ev.title}
                      className="w-full h-full object-cover group-hover:scale-105 transition-transform" />
                  </div>
                ) : (
                  <div className="h-36 flex items-center justify-center text-5xl"
                    style={{ background: `${color}15` }}>
                    {TYPE_ICONS[ev.evidence_type] ?? "📁"}
                  </div>
                )}
                <div className="p-3">
                  <div className="flex items-start justify-between gap-2">
                    <h3 className="text-white text-sm font-semibold line-clamp-1">{ev.title}</h3>
                    <button onClick={(e) => { e.stopPropagation(); deleteItem(ev.id); }}
                      className="text-gray-600 hover:text-red-400 text-xs shrink-0">✕</button>
                  </div>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-xs px-2 py-0.5 rounded-full capitalize"
                      style={{ background: `${color}20`, color }}>
                      {ev.evidence_type}
                    </span>
                    {ev.latitude && <span className="text-gray-600 text-xs">📍</span>}
                  </div>
                  <p className="text-gray-500 text-xs mt-1">{fmtDate(ev.created_at)}</p>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Upload modal */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: "rgba(0,0,0,0.75)" }}>
          <div className="w-full max-w-md rounded-2xl p-6 space-y-4" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
            <div className="flex items-center justify-between">
              <h3 className="text-white font-bold text-lg">Upload Evidence</h3>
              <button onClick={() => setShowModal(false)} className="text-gray-500 hover:text-white">✕</button>
            </div>

            <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })}
              placeholder="Title *" className="w-full px-3 py-2 rounded-lg text-white text-sm"
              style={{ background: "#040804", border: "1px solid #374151" }} />

            <select value={form.evidence_type} onChange={(e) => setForm({ ...form, evidence_type: e.target.value })}
              className="w-full px-3 py-2 rounded-lg text-white text-sm"
              style={{ background: "#040804", border: "1px solid #374151" }}>
              {["image", "video", "audio", "document", "note"].map((t) => (
                <option key={t} value={t}>{TYPE_ICONS[t]} {t}</option>
              ))}
            </select>

            <textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })}
              placeholder="Description" rows={3}
              className="w-full px-3 py-2 rounded-lg text-white text-sm resize-none"
              style={{ background: "#040804", border: "1px solid #374151" }} />

            <div>
              <p className="text-gray-500 text-xs mb-1.5">Location (optional)</p>
              <MapPicker
                value={{ lat: form.latitude, lng: form.longitude }}
                onChange={(lat, lng) => setForm((f) => ({ ...f, latitude: lat, longitude: lng }))}
              />
            </div>

            <div onClick={() => fileRef.current?.click()}
              className="w-full py-3 rounded-lg text-center text-sm cursor-pointer border-dashed transition-colors"
              style={{ background: "#040804", border: "1px dashed #374151", color: file ? "#4ade80" : "#6b7280" }}>
              {file ? file.name : "Click to attach file (optional)"}
            </div>
            <input ref={fileRef} type="file" className="hidden"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)} />

            <div className="flex gap-3 pt-1">
              <button onClick={() => setShowModal(false)}
                className="flex-1 py-2 rounded-lg text-gray-400 text-sm font-semibold"
                style={{ background: "#0a140a" }}>
                Cancel
              </button>
              <button onClick={upload} disabled={saving || !form.title.trim()}
                className="flex-1 py-2 rounded-lg text-white text-sm font-semibold hover:opacity-90 disabled:opacity-40"
                style={{ background: "#16a34a" }}>
                {saving ? "Uploading…" : "Upload"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Preview modal */}
      {preview && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: "rgba(0,0,0,0.85)" }}
          onClick={() => setPreview(null)}>
          <div className="w-full max-w-lg rounded-2xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #0a140a" }}
            onClick={(e) => e.stopPropagation()}>
            {preview.evidence_type === "image" && preview.file_url && (
              <img src={`${BASE_URL}${preview.file_url}`} alt={preview.title} className="w-full max-h-64 object-cover" />
            )}
            <div className="p-5">
              <h3 className="text-white font-bold text-lg">{preview.title}</h3>
              <p className="text-gray-400 text-sm mt-1 capitalize">{TYPE_ICONS[preview.evidence_type]} {preview.evidence_type}</p>
              {preview.description && <p className="text-gray-300 text-sm mt-3">{preview.description}</p>}
              {preview.latitude && (
                <p className="text-gray-500 text-xs mt-3">📍 {preview.latitude.toFixed(5)}, {preview.longitude?.toFixed(5)}</p>
              )}
              {preview.file_url && preview.evidence_type !== "image" && (
                <a href={`${BASE_URL}${preview.file_url}`} target="_blank" rel="noreferrer"
                  className="inline-block mt-3 px-4 py-2 rounded-lg text-sm font-semibold text-white hover:opacity-90"
                  style={{ background: "#16a34a" }}>
                  Open File
                </a>
              )}
            </div>
            <div className="px-5 pb-4">
              <button onClick={() => setPreview(null)} className="text-gray-500 text-sm hover:text-white">Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
