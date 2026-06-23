import { useState, useEffect, useCallback } from "react";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";

interface PackageItem { type: string; id: string; name?: string; }
interface MissionPkg { id: string; name: string; description?: string; mission_id?: string; item_count: number; created_at: string; }

const BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:1104";

export default function PackagesPage() {
  const { user } = useAuthStore();
  const canCreate = user && ["operations_coordinator", "planning_officer"].includes(user.role);
  const [packages, setPackages] = useState<MissionPkg[]>([]);
  const [missions, setMissions] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [form, setForm] = useState({ name: "", description: "", mission_id: "", include_routes: true, include_evidence: true, include_contacts: true });
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [pkgRes, mRes] = await Promise.allSettled([api.get("/packages"), api.get("/missions")]);
      if (pkgRes.status === "fulfilled") setPackages(pkgRes.value.data);
      if (mRes.status === "fulfilled") setMissions(mRes.value.data.map((m: { id: string; name: string }) => ({ id: m.id, name: m.name })));
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const create = async () => {
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      await api.post("/packages", {
        name: form.name,
        description: form.description || undefined,
        mission_id: form.mission_id || undefined,
        include_routes: form.include_routes,
        include_evidence: form.include_evidence,
        include_contacts: form.include_contacts,
      });
      setShowModal(false);
      setForm({ name: "", description: "", mission_id: "", include_routes: true, include_evidence: true, include_contacts: true });
      await load();
    } catch { /**/ } finally { setSaving(false); }
  };

  const del = async (id: string) => {
    if (!confirm("Delete this package?")) return;
    try { await api.delete(`/packages/${id}`); setPackages((prev) => prev.filter((p) => p.id !== id)); } catch { /**/ }
  };

  const fmtDate = (s: string) => new Date(s).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "2-digit" });

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-white font-bold text-xl">Mission Packages</h1>
          <p className="text-gray-500 text-sm mt-0.5">Exportable bundles of mission data for offline use</p>
        </div>
        {canCreate && (
          <button onClick={() => setShowModal(true)} className="px-4 py-2 rounded-lg text-white text-sm font-semibold hover:opacity-90" style={{ background: "#16a34a" }}>
            + Create Package
          </button>
        )}
      </div>

      {loading ? (
        <div className="text-center py-16 text-gray-500">Loading…</div>
      ) : packages.length === 0 ? (
        <div className="text-center py-16">
          <p className="text-gray-500 text-4xl mb-3">📦</p>
          <p className="text-gray-400 text-sm">No packages created yet</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {packages.map((pkg) => (
            <div key={pkg.id} className="rounded-xl p-5" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
              <div className="flex items-start justify-between mb-3">
                <h3 className="text-white font-semibold text-sm line-clamp-2">{pkg.name}</h3>
                {canCreate && (
                  <button onClick={() => del(pkg.id)} className="text-gray-600 hover:text-red-400 text-xs ml-2 shrink-0">✕</button>
                )}
              </div>
              {pkg.description && <p className="text-gray-500 text-xs mb-3 line-clamp-2">{pkg.description}</p>}
              <div className="flex items-center gap-2 mb-4 flex-wrap">
                <span className="text-xs px-2 py-0.5 rounded" style={{ background: "#0a140a", color: "#9ca3af" }}>
                  📁 {pkg.item_count} items
                </span>
                <span className="text-gray-600 text-xs">{fmtDate(pkg.created_at)}</span>
              </div>
              <a href={`${BASE_URL}/api/v1/packages/${pkg.id}/download`}
                target="_blank" rel="noreferrer"
                className="flex items-center justify-center gap-2 w-full py-2 rounded-lg text-white text-xs font-semibold hover:opacity-90 transition-opacity"
                style={{ background: "#166534" }}>
                ⬇ Download ZIP
              </a>
            </div>
          ))}
        </div>
      )}

      {/* Create modal */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: "rgba(0,0,0,0.75)" }}>
          <div className="w-full max-w-md rounded-2xl p-6 space-y-4" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
            <div className="flex items-center justify-between">
              <h3 className="text-white font-bold text-lg">Create Package</h3>
              <button onClick={() => setShowModal(false)} className="text-gray-500 hover:text-white">✕</button>
            </div>

            <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })}
              placeholder="Package name *" className="w-full px-3 py-2 rounded-lg text-white text-sm"
              style={{ background: "#040804", border: "1px solid #374151" }} />

            <textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })}
              placeholder="Description" rows={2} className="w-full px-3 py-2 rounded-lg text-white text-sm resize-none"
              style={{ background: "#040804", border: "1px solid #374151" }} />

            <select value={form.mission_id} onChange={(e) => setForm({ ...form, mission_id: e.target.value })}
              className="w-full px-3 py-2 rounded-lg text-white text-sm"
              style={{ background: "#040804", border: "1px solid #374151" }}>
              <option value="">No specific mission</option>
              {missions.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
            </select>

            <div className="space-y-2">
              {[
                { key: "include_routes", label: "Include Routes" },
                { key: "include_evidence", label: "Include Evidence" },
                { key: "include_contacts", label: "Include Contacts" },
              ].map(({ key, label }) => (
                <label key={key} className="flex items-center gap-3 cursor-pointer">
                  <input type="checkbox" checked={form[key as keyof typeof form] as boolean}
                    onChange={(e) => setForm({ ...form, [key]: e.target.checked })}
                    className="w-4 h-4 rounded" style={{ accentColor: "#16a34a" }} />
                  <span className="text-gray-300 text-sm">{label}</span>
                </label>
              ))}
            </div>

            <div className="flex gap-3 pt-1">
              <button onClick={() => setShowModal(false)} className="flex-1 py-2 rounded-lg text-gray-400 text-sm font-semibold" style={{ background: "#0a140a" }}>
                Cancel
              </button>
              <button onClick={create} disabled={saving || !form.name.trim()}
                className="flex-1 py-2 rounded-lg text-white text-sm font-semibold hover:opacity-90 disabled:opacity-40" style={{ background: "#16a34a" }}>
                {saving ? "Creating…" : "Create"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
