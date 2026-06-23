import { useState, useRef } from "react";
import { useAuthStore } from "../stores/authStore";
import { userApi, mediaUrl } from "../services/api";
import { MdEdit, MdSave, MdCameraAlt, MdPerson } from "react-icons/md";

const ROLE_LABELS: Record<string, string> = {
  operations_coordinator: "Operations Coordinator",
  planning_officer: "Planning Officer",
  team_leader: "Team Leader",
  field_user: "Field User",
};

const ROLE_COLORS: Record<string, string> = {
  operations_coordinator: "bg-red-600",
  planning_officer: "bg-orange-500",
  team_leader: "bg-green-700",
  field_user: "bg-green-600",
};

export default function Profile() {
  const { user, updateUser } = useAuthStore();
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({ full_name: user?.full_name || "", phone: user?.phone || "" });
  const [saving, setSaving] = useState(false);
  const [success, setSuccess] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  if (!user) return null;

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      const { data } = await userApi.update(user.id, form);
      updateUser(data);
      setEditing(false);
      setSuccess(true);
      setTimeout(() => setSuccess(false), 3000);
    } catch {}
    setSaving(false);
  };

  const handleAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const { data } = await userApi.uploadAvatar(user.id, file);
      updateUser({ avatar_url: data.avatar_url });
    } catch {}
  };

  return (
    <div className="p-6 max-w-2xl">
      <h2 className="text-white text-xl font-bold mb-6">Profile & Settings</h2>

      {success && (
        <div className="bg-green-900/30 border border-green-700 text-green-300 rounded-lg px-4 py-3 mb-6 text-sm">
          Profile updated successfully
        </div>
      )}

      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 mb-6">
        <div className="flex items-center gap-6 mb-6">
          <div className="relative">
            <div className="w-20 h-20 rounded-2xl bg-gray-700 flex items-center justify-center text-white text-2xl font-bold overflow-hidden">
              {user.avatar_url ? (
                <img src={mediaUrl(user.avatar_url)} alt="" className="w-full h-full object-cover" />
              ) : (
                user.full_name?.charAt(0).toUpperCase()
              )}
            </div>
            <button
              onClick={() => fileRef.current?.click()}
              className="absolute -bottom-1 -right-1 w-7 h-7 rounded-full bg-green-700 hover:bg-green-600 flex items-center justify-center transition-colors"
            >
              <MdCameraAlt size={14} className="text-white" />
            </button>
            <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={handleAvatarChange} />
          </div>
          <div>
            <h3 className="text-white text-lg font-semibold">{user.full_name}</h3>
            <p className="text-gray-400 text-sm">@{user.username}</p>
            <span className={`inline-block mt-2 text-xs px-2.5 py-1 rounded-full text-white font-medium ${ROLE_COLORS[user.role]}`}>
              {ROLE_LABELS[user.role]}
            </span>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4 p-4 bg-gray-800/50 rounded-xl mb-4">
          {[
            ["Email", user.email],
            ["Username", `@${user.username}`],
            ["Status", user.is_active ? "Active" : "Inactive"],
            ["Verified", user.is_verified ? "Yes" : "No"],
          ].map(([label, value]) => (
            <div key={label}>
              <p className="text-gray-500 text-xs">{label}</p>
              <p className="text-gray-200 text-sm mt-0.5">{value}</p>
            </div>
          ))}
        </div>

        {editing ? (
          <form onSubmit={handleSave} className="space-y-4">
            <div>
              <label className="block text-gray-300 text-sm mb-1">Full Name</label>
              <input
                value={form.full_name}
                onChange={(e) => setForm({ ...form, full_name: e.target.value })}
                className="w-full bg-gray-800 border border-gray-700 text-white rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:border-green-600"
              />
            </div>
            <div>
              <label className="block text-gray-300 text-sm mb-1">Phone</label>
              <input
                value={form.phone}
                onChange={(e) => setForm({ ...form, phone: e.target.value })}
                className="w-full bg-gray-800 border border-gray-700 text-white rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:border-green-600"
                placeholder="+1 234 567 8900"
              />
            </div>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setEditing(false)}
                className="flex-1 bg-gray-800 text-gray-300 rounded-lg py-2.5 text-sm"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={saving}
                className="flex-1 bg-green-700 hover:bg-green-600 text-white rounded-lg py-2.5 text-sm font-medium flex items-center justify-center gap-2"
              >
                <MdSave size={16} />
                {saving ? "Saving..." : "Save Changes"}
              </button>
            </div>
          </form>
        ) : (
          <button
            onClick={() => setEditing(true)}
            className="flex items-center gap-2 bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white rounded-lg px-4 py-2.5 text-sm transition-colors"
          >
            <MdEdit size={16} />
            Edit Profile
          </button>
        )}
      </div>

      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 className="text-white font-semibold mb-4">Account Information</h3>
        <div className="space-y-3">
          {[
            ["User ID", user.id.substring(0, 8) + "..."],
            ["Role", ROLE_LABELS[user.role]],
            ["Phone", user.phone || "Not set"],
            ["Last seen", user.last_seen ? new Date(user.last_seen).toLocaleString() : "Unknown"],
          ].map(([label, value]) => (
            <div key={label} className="flex justify-between py-2 border-b border-gray-800 last:border-0">
              <span className="text-gray-400 text-sm">{label}</span>
              <span className="text-gray-200 text-sm font-mono">{value}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
