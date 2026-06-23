import { useEffect, useState } from "react";
import { teamApi, userApi } from "../services/api";
import type { Team, User } from "../types";
import { MdAdd, MdPeople, MdPersonAdd, MdDelete, MdEdit } from "react-icons/md";
import { useNavigate } from "react-router-dom";
import { useAuthStore } from "../stores/authStore";

export default function Teams() {
  const { user: me } = useAuthStore();
  const [teams, setTeams] = useState<Team[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({ name: "", description: "", color: "#22c55e" });
  const [creating, setCreating] = useState(false);
  const navigate = useNavigate();

  const canManage = me?.role === "operations_coordinator" || me?.role === "planning_officer" || me?.role === "team_leader";

  useEffect(() => {
    load();
  }, []);

  const load = () => {
    setLoading(true);
    teamApi.list()
      .then(({ data }) => setTeams(data))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    try {
      await teamApi.create(form);
      setShowCreate(false);
      setForm({ name: "", description: "", color: "#22c55e" });
      load();
    } catch {
    } finally {
      setCreating(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Delete this team?")) return;
    await teamApi.delete(id).catch(() => {});
    load();
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-white text-xl font-bold">Teams</h2>
          <p className="text-gray-400 text-sm">{teams.length} team{teams.length !== 1 ? "s" : ""} total</p>
        </div>
        {canManage && (
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-2 bg-green-700 hover:bg-green-600 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
          >
            <MdAdd size={18} />
            New Team
          </button>
        )}
      </div>

      {showCreate && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
          <div className="bg-gray-900 border border-gray-700 rounded-xl p-6 w-full max-w-md">
            <h3 className="text-white font-semibold text-lg mb-4">Create Team</h3>
            <form onSubmit={handleCreate} className="space-y-4">
              <div>
                <label className="block text-gray-300 text-sm mb-1">Team Name *</label>
                <input
                  required
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                  className="w-full bg-gray-800 border border-gray-700 text-white rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:border-green-600"
                  placeholder="Alpha Team"
                />
              </div>
              <div>
                <label className="block text-gray-300 text-sm mb-1">Description</label>
                <textarea
                  value={form.description}
                  onChange={(e) => setForm({ ...form, description: e.target.value })}
                  className="w-full bg-gray-800 border border-gray-700 text-white rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:border-green-600 h-20 resize-none"
                  placeholder="Optional description..."
                />
              </div>
              <div>
                <label className="block text-gray-300 text-sm mb-1">Color</label>
                <input
                  type="color"
                  value={form.color}
                  onChange={(e) => setForm({ ...form, color: e.target.value })}
                  className="h-10 w-20 bg-transparent border border-gray-700 rounded-lg cursor-pointer"
                />
              </div>
              <div className="flex gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setShowCreate(false)}
                  className="flex-1 bg-gray-800 hover:bg-gray-700 text-gray-300 rounded-lg py-2.5 text-sm transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={creating}
                  className="flex-1 bg-green-700 hover:bg-green-600 disabled:bg-blue-800 text-white rounded-lg py-2.5 text-sm font-medium transition-colors"
                >
                  {creating ? "Creating..." : "Create"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {loading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[...Array(6)].map((_, i) => (
            <div key={i} className="bg-gray-900 border border-gray-800 rounded-xl p-5 animate-pulse h-32" />
          ))}
        </div>
      ) : teams.length === 0 ? (
        <div className="text-center py-16">
          <MdPeople size={48} className="text-gray-700 mx-auto mb-3" />
          <p className="text-gray-400">No teams yet</p>
          {canManage && (
            <button
              onClick={() => setShowCreate(true)}
              className="mt-4 text-green-400 hover:text-green-300 text-sm"
            >
              Create the first team
            </button>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {teams.map((team) => (
            <div
              key={team.id}
              className="bg-gray-900 border border-gray-800 hover:border-gray-600 rounded-xl p-5 cursor-pointer transition-all group"
              onClick={() => navigate(`/teams/${team.id}`)}
            >
              <div className="flex items-start justify-between mb-3">
                <div className="flex items-center gap-3">
                  <div
                    className="w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold text-sm"
                    style={{ backgroundColor: team.color }}
                  >
                    {team.name.charAt(0).toUpperCase()}
                  </div>
                  <div>
                    <p className="text-white font-semibold group-hover:text-green-400 transition-colors">{team.name}</p>
                    <p className="text-gray-500 text-xs flex items-center gap-1">
                      <MdPeople size={12} />
                      {team.member_count ?? 0} member{(team.member_count ?? 0) !== 1 ? "s" : ""}
                    </p>
                  </div>
                </div>
                {canManage && (
                  <button
                    onClick={(e) => { e.stopPropagation(); handleDelete(team.id); }}
                    className="opacity-0 group-hover:opacity-100 p-1.5 rounded-lg hover:bg-red-900 text-gray-500 hover:text-red-400 transition-all"
                  >
                    <MdDelete size={16} />
                  </button>
                )}
              </div>
              {team.description && (
                <p className="text-gray-400 text-sm line-clamp-2">{team.description}</p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
