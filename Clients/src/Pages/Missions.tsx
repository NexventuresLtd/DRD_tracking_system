import { useEffect, useState } from "react";
import { missionApi } from "../services/api";
import type { Mission, MissionStatusType } from "../types";
import { useAuthStore } from "../stores/authStore";
import { MdAdd, MdAssignment, MdCheckCircle, MdRadioButtonUnchecked } from "react-icons/md";

const STATUS_META: Record<MissionStatusType, { label: string; color: string; bg: string }> = {
  draft:     { label: "Draft",     color: "text-gray-300",  bg: "bg-gray-700" },
  planned:   { label: "Planned",   color: "text-green-300",  bg: "bg-blue-900/50" },
  active:    { label: "Active",    color: "text-green-300", bg: "bg-green-900/50" },
  suspended: { label: "Suspended", color: "text-yellow-300",bg: "bg-yellow-900/50" },
  completed: { label: "Completed", color: "text-purple-300",bg: "bg-purple-900/50" },
  archived:  { label: "Archived",  color: "text-gray-500",  bg: "bg-gray-800" },
};

const STATUSES: MissionStatusType[] = ["draft", "planned", "active", "suspended", "completed", "archived"];

export default function Missions() {
  const { user } = useAuthStore();
  const [missions, setMissions] = useState<Mission[]>([]);
  const [selected, setSelected] = useState<Mission | null>(null);
  const [filter, setFilter] = useState<MissionStatusType | "all">("all");
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({ name: "", description: "", status: "draft" as MissionStatusType, area_of_operations: "", briefing_notes: "" });
  const [creating, setCreating] = useState(false);

  const canManage = user?.role === "operations_coordinator" || user?.role === "planning_officer";

  useEffect(() => { load(); }, []);

  const load = () => {
    setLoading(true);
    missionApi.list()
      .then(({ data }) => setMissions(data))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    try {
      await missionApi.create(form);
      setShowCreate(false);
      setForm({ name: "", description: "", status: "draft", area_of_operations: "", briefing_notes: "" });
      load();
    } catch {} finally { setCreating(false); }
  };

  const handleStatusChange = async (id: string, status: MissionStatusType) => {
    await missionApi.update(id, { status }).catch(() => {});
    load();
    if (selected?.id === id) setSelected({ ...selected, status });
  };

  const filtered = filter === "all" ? missions : missions.filter((m) => m.status === filter);

  return (
    <div className="flex h-full">
      <div className="w-80 border-r border-gray-800 flex flex-col">
        <div className="p-4 border-b border-gray-800">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-white font-bold">Missions</h2>
            {canManage && (
              <button onClick={() => setShowCreate(true)} className="p-1.5 bg-green-700 rounded-lg hover:bg-green-600">
                <MdAdd size={16} className="text-white" />
              </button>
            )}
          </div>
          <div className="flex flex-wrap gap-1">
            <button
              onClick={() => setFilter("all")}
              className={`text-xs px-2 py-1 rounded-full transition-colors ${filter === "all" ? "bg-gray-700 text-white" : "text-gray-500 hover:text-gray-300"}`}
            >
              All ({missions.length})
            </button>
            {(["active", "planned", "draft"] as MissionStatusType[]).map((s) => (
              <button
                key={s}
                onClick={() => setFilter(s)}
                className={`text-xs px-2 py-1 rounded-full transition-colors ${filter === s ? `${STATUS_META[s].bg} ${STATUS_META[s].color}` : "text-gray-500 hover:text-gray-300"}`}
              >
                {STATUS_META[s].label} ({missions.filter((m) => m.status === s).length})
              </button>
            ))}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-3 space-y-2">
          {loading ? (
            [...Array(4)].map((_, i) => <div key={i} className="h-20 bg-gray-900 rounded-xl animate-pulse" />)
          ) : filtered.map((m) => (
            <div
              key={m.id}
              onClick={() => setSelected(m)}
              className={`p-3 rounded-xl cursor-pointer border transition-all ${selected?.id === m.id ? "border-blue-600 bg-blue-900/20" : "border-gray-800 bg-gray-900 hover:border-gray-700"}`}
            >
              <div className="flex items-start justify-between gap-2">
                <p className="text-white text-sm font-medium leading-tight">{m.name}</p>
                <span className={`text-xs px-2 py-0.5 rounded-full shrink-0 ${STATUS_META[m.status].bg} ${STATUS_META[m.status].color}`}>
                  {STATUS_META[m.status].label}
                </span>
              </div>
              {m.area_of_operations && (
                <p className="text-gray-500 text-xs mt-1">{m.area_of_operations}</p>
              )}
              <p className="text-gray-600 text-xs mt-1">{m.objectives.length} objectives · {new Date(m.created_at).toLocaleDateString()}</p>
            </div>
          ))}
          {!loading && filtered.length === 0 && (
            <div className="text-center py-12">
              <MdAssignment size={36} className="text-gray-700 mx-auto mb-2" />
              <p className="text-gray-500 text-sm">No missions</p>
            </div>
          )}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {selected ? (
          <div className="p-6 max-w-3xl">
            <div className="flex items-start justify-between mb-6">
              <div>
                <h2 className="text-white text-xl font-bold">{selected.name}</h2>
                {selected.area_of_operations && (
                  <p className="text-gray-400 text-sm mt-1">{selected.area_of_operations}</p>
                )}
              </div>
              <div className="flex items-center gap-2">
                <span className={`text-sm px-3 py-1 rounded-full font-medium ${STATUS_META[selected.status].bg} ${STATUS_META[selected.status].color}`}>
                  {STATUS_META[selected.status].label}
                </span>
                {canManage && (
                  <select
                    value={selected.status}
                    onChange={(e) => handleStatusChange(selected.id, e.target.value as MissionStatusType)}
                    className="bg-gray-800 border border-gray-700 text-gray-300 text-sm rounded-lg px-2 py-1 focus:outline-none"
                  >
                    {STATUSES.map((s) => (
                      <option key={s} value={s}>{STATUS_META[s].label}</option>
                    ))}
                  </select>
                )}
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4 mb-6">
              {[
                ["Start Date", selected.start_date ? new Date(selected.start_date).toLocaleDateString() : "Not set"],
                ["End Date", selected.end_date ? new Date(selected.end_date).toLocaleDateString() : "Not set"],
                ["Assignments", selected.assignments.length + " assigned"],
                ["Created", new Date(selected.created_at).toLocaleDateString()],
              ].map(([label, value]) => (
                <div key={label} className="bg-gray-900 border border-gray-800 rounded-xl p-4">
                  <p className="text-gray-500 text-xs">{label}</p>
                  <p className="text-white text-sm mt-1">{value}</p>
                </div>
              ))}
            </div>

            {selected.description && (
              <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 mb-4">
                <h3 className="text-gray-400 text-xs uppercase tracking-wider mb-2">Description</h3>
                <p className="text-gray-300 text-sm">{selected.description}</p>
              </div>
            )}

            {selected.briefing_notes && (
              <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 mb-4">
                <h3 className="text-gray-400 text-xs uppercase tracking-wider mb-2">Briefing Notes</h3>
                <p className="text-gray-300 text-sm whitespace-pre-wrap">{selected.briefing_notes}</p>
              </div>
            )}

            {selected.objectives.length > 0 && (
              <div className="bg-gray-900 border border-gray-800 rounded-xl p-4">
                <h3 className="text-gray-400 text-xs uppercase tracking-wider mb-3">Objectives</h3>
                <div className="space-y-2">
                  {selected.objectives.map((obj) => (
                    <div key={obj.id} className="flex items-start gap-3">
                      {obj.is_completed
                        ? <MdCheckCircle className="text-green-500 shrink-0 mt-0.5" size={18} />
                        : <MdRadioButtonUnchecked className="text-gray-600 shrink-0 mt-0.5" size={18} />
                      }
                      <div>
                        <p className={`text-sm ${obj.is_completed ? "line-through text-gray-500" : "text-white"}`}>{obj.title}</p>
                        {obj.description && <p className="text-gray-500 text-xs mt-0.5">{obj.description}</p>}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        ) : (
          <div className="flex items-center justify-center h-full">
            <div className="text-center">
              <MdAssignment size={48} className="text-gray-700 mx-auto mb-3" />
              <p className="text-gray-400">Select a mission to view details</p>
            </div>
          </div>
        )}
      </div>

      {showCreate && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
          <div className="bg-gray-900 border border-gray-700 rounded-xl p-6 w-full max-w-lg">
            <h3 className="text-white font-semibold text-lg mb-4">Create Mission</h3>
            <form onSubmit={handleCreate} className="space-y-4">
              {[
                ["Mission Name *", "name", "text", "Operation Eagle", true],
                ["Area of Operations", "area_of_operations", "text", "Northern Sector", false],
              ].map(([label, key, type, placeholder, required]) => (
                <div key={key as string}>
                  <label className="block text-gray-300 text-sm mb-1">{label as string}</label>
                  <input
                    type={type as string}
                    required={required as boolean}
                    value={(form as any)[key as string]}
                    onChange={(e) => setForm({ ...form, [key as string]: e.target.value })}
                    placeholder={placeholder as string}
                    className="w-full bg-gray-800 border border-gray-700 text-white rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:border-green-600"
                  />
                </div>
              ))}
              <div>
                <label className="block text-gray-300 text-sm mb-1">Description</label>
                <textarea
                  value={form.description}
                  onChange={(e) => setForm({ ...form, description: e.target.value })}
                  className="w-full bg-gray-800 border border-gray-700 text-white rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:border-green-600 h-20 resize-none"
                />
              </div>
              <div>
                <label className="block text-gray-300 text-sm mb-1">Briefing Notes</label>
                <textarea
                  value={form.briefing_notes}
                  onChange={(e) => setForm({ ...form, briefing_notes: e.target.value })}
                  className="w-full bg-gray-800 border border-gray-700 text-white rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:border-green-600 h-24 resize-none"
                />
              </div>
              <div>
                <label className="block text-gray-300 text-sm mb-1">Initial Status</label>
                <select
                  value={form.status}
                  onChange={(e) => setForm({ ...form, status: e.target.value as MissionStatusType })}
                  className="w-full bg-gray-800 border border-gray-700 text-white rounded-lg px-3 py-2.5 text-sm focus:outline-none"
                >
                  {STATUSES.slice(0, 3).map((s) => <option key={s} value={s}>{STATUS_META[s].label}</option>)}
                </select>
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setShowCreate(false)} className="flex-1 bg-gray-800 text-gray-300 rounded-lg py-2.5 text-sm">Cancel</button>
                <button type="submit" disabled={creating} className="flex-1 bg-green-700 hover:bg-green-600 disabled:bg-blue-800 text-white rounded-lg py-2.5 text-sm font-medium">
                  {creating ? "Creating..." : "Create"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
