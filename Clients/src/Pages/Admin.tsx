import { useEffect, useState } from "react";
import { adminApi, mediaUrl } from "../services/api";
import type { User, Invite, AuditLog } from "../types";
import {
  MdPeople, MdQrCode, MdHistory, MdAdd, MdBlock, MdRefresh,
  MdBarChart, MdEdit, MdDelete, MdLock, MdVisibility, MdVisibilityOff,
  MdClose, MdCheck, MdPersonAdd, MdShield,
} from "react-icons/md";

// ── Constants ──────────────────────────────────────────────────────────────
type Tab = "overview" | "users" | "invites" | "audit";

const ROLES = [
  { value: "operations_coordinator", label: "Coordinator", short: "COORD", color: "#ef4444", bg: "#2d0a0a" },
  { value: "planning_officer",       label: "Planning Officer", short: "PLAN", color: "#f59e0b", bg: "#2d1a00" },
  { value: "team_leader",            label: "Team Leader", short: "LEAD", color: "#22c55e", bg: "#052e16" },
  { value: "field_user",             label: "Field User", short: "FIELD", color: "#4ade80", bg: "#052e16" },
];

const roleInfo = (role: string) => ROLES.find((r) => r.value === role) ?? ROLES[3];

const hk = {
  card:  { background: "#0a140a", border: "1px solid #152015" } as React.CSSProperties,
  input: { background: "#040804", border: "1px solid #152015", color: "#d1fae5", padding: "8px 12px", width: "100%", fontFamily: "'JetBrains Mono', monospace", fontSize: 12, outline: "none" } as React.CSSProperties,
  label: { color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1.5, textTransform: "uppercase" as const, display: "block", marginBottom: 6 },
  btn:   (col = "#16a34a") => ({ background: col, border: "none", color: "#fff", padding: "8px 16px", cursor: "pointer", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, letterSpacing: 1, display: "flex", alignItems: "center", gap: 6 } as React.CSSProperties),
};

// ── Modal wrapper ─────────────────────────────────────────────────────────
function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.75)", zIndex: 9999, display: "flex", alignItems: "center", justifyContent: "center", padding: 16 }}>
      <div style={{ background: "#020602", border: "1px solid #0f1f0f", width: "100%", maxWidth: 480, maxHeight: "90vh", overflow: "auto" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "14px 16px", borderBottom: "1px solid #0f1f0f" }}>
          <span style={{ color: "#22c55e", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, letterSpacing: 2, textTransform: "uppercase" }}>{title}</span>
          <button onClick={onClose} style={{ background: "none", border: "none", color: "#374151", cursor: "pointer" }}><MdClose size={16} /></button>
        </div>
        <div style={{ padding: 20 }}>{children}</div>
      </div>
    </div>
  );
}

// ── Role badge ────────────────────────────────────────────────────────────
function RoleBadge({ role }: { role: string }) {
  const r = roleInfo(role);
  return (
    <span style={{ background: r.bg, color: r.color, fontFamily: "'JetBrains Mono', monospace", fontSize: 9, fontWeight: 700, letterSpacing: 1.5, padding: "2px 7px", textTransform: "uppercase" }}>
      {r.short}
    </span>
  );
}

// ── Overview tab ───────────────────────────────────────────────────────────
function OverviewTab() {
  const [stats, setStats] = useState<any>(null);
  useEffect(() => { adminApi.getStats().then(({ data }) => setStats(data)).catch(() => {}); }, []);

  if (!stats) return <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 11 }}>LOADING...</div>;

  const statCards = [
    { label: "TOTAL USERS",    value: stats.total_users,      color: "#22c55e" },
    { label: "ACTIVE NOW",     value: stats.active_users_now,  color: "#4ade80" },
    { label: "TEAMS",          value: stats.total_teams,       color: "#f59e0b" },
    { label: "OPEN INVITES",   value: stats.active_invites,    color: "#06b6d4" },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: 10 }}>
        {statCards.map(({ label, value, color }) => (
          <div key={label} style={{ ...hk.card, padding: "16px 14px" }}>
            <div style={{ color, fontFamily: "'JetBrains Mono', monospace", fontSize: 28, fontWeight: 700 }}>{value ?? 0}</div>
            <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 9, letterSpacing: 2, marginTop: 4 }}>{label}</div>
          </div>
        ))}
      </div>

      <div style={{ ...hk.card, padding: 16 }}>
        <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 2, marginBottom: 14 }}>USERS BY ROLE</div>
        {ROLES.map((r) => {
          const count = stats.users_by_role?.[r.value] ?? 0;
          const pct = stats.total_users ? (count / stats.total_users) * 100 : 0;
          return (
            <div key={r.value} style={{ marginBottom: 10 }}>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                <span style={{ color: r.color, fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1 }}>{r.short}</span>
                <span style={{ color: "#4b5563", fontFamily: "'JetBrains Mono', monospace", fontSize: 10 }}>{count}</span>
              </div>
              <div style={{ height: 3, background: "#0a140a" }}>
                <div style={{ height: "100%", width: `${pct}%`, background: r.color, transition: "width 0.4s" }} />
              </div>
            </div>
          );
        })}
      </div>

      <div style={{ ...hk.card, padding: 16 }}>
        <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 2, marginBottom: 14 }}>COORDINATOR CAPABILITIES</div>
        {[
          "Create, edit, and delete any user account",
          "Assign and change user roles",
          "Reset any user password",
          "Generate QR codes and invite vouchers for enrollment",
          "Create and manage teams",
          "Create and manage missions and routes",
          "View full audit logs and system activity",
          "Manage geofences and zones",
          "View analytics and playback",
          "Access all live feeds and communications",
          "Manage evidence and packages",
          "Configure system settings",
        ].map((cap) => (
          <div key={cap} style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
            <MdCheck size={12} style={{ color: "#16a34a", flexShrink: 0 }} />
            <span style={{ color: "#6b7280", fontSize: 12 }}>{cap}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Users tab ──────────────────────────────────────────────────────────────
function UsersTab() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [showCreate, setShowCreate] = useState(false);
  const [editUser, setEditUser] = useState<User | null>(null);
  const [resetUser, setResetUser] = useState<User | null>(null);
  const [deleteUser, setDeleteUser] = useState<User | null>(null);
  const [createForm, setCreateForm] = useState({ email: "", username: "", full_name: "", password: "", role: "field_user", phone: "" });
  const [showPass, setShowPass] = useState(false);
  const [newPass, setNewPass] = useState("");
  const [msg, setMsg] = useState("");

  const load = () => {
    setLoading(true);
    adminApi.getUsers().then(({ data }) => setUsers(data.users)).catch(() => {}).finally(() => setLoading(false));
  };
  useEffect(load, []);

  const filtered = users.filter((u) =>
    !search || u.full_name?.toLowerCase().includes(search.toLowerCase()) ||
    u.email?.toLowerCase().includes(search.toLowerCase()) ||
    u.username?.toLowerCase().includes(search.toLowerCase())
  );

  const flash = (m: string) => { setMsg(m); setTimeout(() => setMsg(""), 2500); };

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await adminApi.createUser(createForm);
      setShowCreate(false);
      setCreateForm({ email: "", username: "", full_name: "", password: "", role: "field_user", phone: "" });
      load();
      flash("User created");
    } catch (err: any) {
      flash(err.response?.data?.detail || "Error creating user");
    }
  };

  const handleUpdate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editUser) return;
    try {
      await adminApi.updateUser(editUser.id, { full_name: editUser.full_name, phone: editUser.phone, role: editUser.role, is_active: editUser.is_active });
      setEditUser(null);
      load();
      flash("User updated");
    } catch { flash("Error updating user"); }
  };

  const handleToggleActive = async (u: User) => {
    await adminApi.updateUser(u.id, { is_active: !u.is_active });
    load();
    flash(`User ${u.is_active ? "deactivated" : "activated"}`);
  };

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!resetUser || newPass.length < 6) return;
    try {
      await adminApi.resetPassword(resetUser.id, newPass);
      setResetUser(null);
      setNewPass("");
      flash("Password reset");
    } catch { flash("Error resetting password"); }
  };

  const handleDelete = async () => {
    if (!deleteUser) return;
    try {
      await adminApi.deleteUser(deleteUser.id);
      setDeleteUser(null);
      load();
      flash("User deleted");
    } catch (err: any) { flash(err.response?.data?.detail || "Error deleting user"); }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      {msg && (
        <div style={{ background: "#052e16", border: "1px solid #16a34a", color: "#22c55e", padding: "8px 14px", fontFamily: "'JetBrains Mono', monospace", fontSize: 11 }}>
          {msg}
        </div>
      )}

      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <input
          placeholder="SEARCH USERS..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ ...hk.input, flex: 1 }}
        />
        <button onClick={load} style={hk.btn("#0a140a")}><MdRefresh size={15} /></button>
        <button onClick={() => setShowCreate(true)} style={hk.btn()}>
          <MdPersonAdd size={15} /> ADD USER
        </button>
      </div>

      {loading ? (
        <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, padding: 20 }}>LOADING...</div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
          {filtered.map((u) => (
            <div key={u.id} style={{ ...hk.card, padding: "12px 14px", display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{
                width: 36, height: 36, background: "#052e16", border: "1px solid #152015",
                display: "flex", alignItems: "center", justifyContent: "center",
                color: "#22c55e", fontSize: 13, fontWeight: 700, flexShrink: 0,
                fontFamily: "'JetBrains Mono', monospace", overflow: "hidden",
              }}>
                {u.avatar_url ? <img src={mediaUrl(u.avatar_url)} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} /> : u.full_name?.charAt(0).toUpperCase()}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 2 }}>
                  <span style={{ color: "#d1fae5", fontSize: 13, fontWeight: 600 }}>{u.full_name}</span>
                  <RoleBadge role={u.role} />
                  {!u.is_active && (
                    <span style={{ background: "#1a0505", color: "#ef4444", fontFamily: "'JetBrains Mono', monospace", fontSize: 9, padding: "1px 6px" }}>INACTIVE</span>
                  )}
                </div>
                <span style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 10 }}>
                  {u.email} · @{u.username}
                  {u.phone ? ` · ${u.phone}` : ""}
                </span>
              </div>
              <div style={{ display: "flex", gap: 4, flexShrink: 0 }}>
                <button
                  onClick={() => setEditUser({ ...u })}
                  title="Edit user"
                  style={{ background: "transparent", border: "1px solid #152015", color: "#4b5563", padding: "5px 7px", cursor: "pointer" }}
                  onMouseEnter={(e) => { e.currentTarget.style.color = "#22c55e"; e.currentTarget.style.borderColor = "#16a34a"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.color = "#4b5563"; e.currentTarget.style.borderColor = "#152015"; }}
                >
                  <MdEdit size={14} />
                </button>
                <button
                  onClick={() => setResetUser(u)}
                  title="Reset password"
                  style={{ background: "transparent", border: "1px solid #152015", color: "#4b5563", padding: "5px 7px", cursor: "pointer" }}
                  onMouseEnter={(e) => { e.currentTarget.style.color = "#f59e0b"; e.currentTarget.style.borderColor = "#f59e0b"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.color = "#4b5563"; e.currentTarget.style.borderColor = "#152015"; }}
                >
                  <MdLock size={14} />
                </button>
                <button
                  onClick={() => handleToggleActive(u)}
                  title={u.is_active ? "Deactivate" : "Activate"}
                  style={{ background: "transparent", border: "1px solid #152015", color: "#4b5563", padding: "5px 7px", cursor: "pointer" }}
                  onMouseEnter={(e) => { e.currentTarget.style.color = u.is_active ? "#f59e0b" : "#22c55e"; e.currentTarget.style.borderColor = u.is_active ? "#f59e0b" : "#22c55e"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.color = "#4b5563"; e.currentTarget.style.borderColor = "#152015"; }}
                >
                  <MdBlock size={14} />
                </button>
                <button
                  onClick={() => setDeleteUser(u)}
                  title="Delete user"
                  style={{ background: "transparent", border: "1px solid #152015", color: "#4b5563", padding: "5px 7px", cursor: "pointer" }}
                  onMouseEnter={(e) => { e.currentTarget.style.color = "#ef4444"; e.currentTarget.style.borderColor = "#ef4444"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.color = "#4b5563"; e.currentTarget.style.borderColor = "#152015"; }}
                >
                  <MdDelete size={14} />
                </button>
              </div>
            </div>
          ))}
          {filtered.length === 0 && (
            <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, padding: "30px 0", textAlign: "center" }}>
              NO USERS FOUND
            </div>
          )}
        </div>
      )}

      {/* Create user modal */}
      {showCreate && (
        <Modal title="Create User" onClose={() => setShowCreate(false)}>
          <form onSubmit={handleCreate} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            {[
              { label: "Full Name", key: "full_name", type: "text", placeholder: "John Doe" },
              { label: "Email", key: "email", type: "email", placeholder: "user@example.com" },
              { label: "Username", key: "username", type: "text", placeholder: "johndoe" },
              { label: "Phone (optional)", key: "phone", type: "tel", placeholder: "+1234567890" },
            ].map(({ label, key, type, placeholder }) => (
              <div key={key}>
                <label style={hk.label}>{label}</label>
                <input
                  type={type}
                  required={key !== "phone"}
                  placeholder={placeholder}
                  value={(createForm as any)[key]}
                  onChange={(e) => setCreateForm({ ...createForm, [key]: e.target.value })}
                  style={hk.input}
                />
              </div>
            ))}
            <div>
              <label style={hk.label}>Password</label>
              <div style={{ position: "relative" }}>
                <input
                  type={showPass ? "text" : "password"}
                  required
                  placeholder="Min 6 characters"
                  value={createForm.password}
                  onChange={(e) => setCreateForm({ ...createForm, password: e.target.value })}
                  style={{ ...hk.input, paddingRight: 36 }}
                />
                <button type="button" onClick={() => setShowPass(!showPass)} style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "#374151", cursor: "pointer" }}>
                  {showPass ? <MdVisibilityOff size={14} /> : <MdVisibility size={14} />}
                </button>
              </div>
            </div>
            <div>
              <label style={hk.label}>Role</label>
              <select
                value={createForm.role}
                onChange={(e) => setCreateForm({ ...createForm, role: e.target.value })}
                style={{ ...hk.input, appearance: "none" }}
              >
                {ROLES.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
              </select>
            </div>
            <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
              <button type="button" onClick={() => setShowCreate(false)} style={{ ...hk.btn("#0a140a"), flex: 1, justifyContent: "center" }}>CANCEL</button>
              <button type="submit" style={{ ...hk.btn(), flex: 1, justifyContent: "center" }}>CREATE USER</button>
            </div>
          </form>
        </Modal>
      )}

      {/* Edit user modal */}
      {editUser && (
        <Modal title="Edit User" onClose={() => setEditUser(null)}>
          <form onSubmit={handleUpdate} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <div>
              <label style={hk.label}>Full Name</label>
              <input value={editUser.full_name} onChange={(e) => setEditUser({ ...editUser, full_name: e.target.value })} style={hk.input} />
            </div>
            <div>
              <label style={hk.label}>Phone</label>
              <input value={editUser.phone ?? ""} onChange={(e) => setEditUser({ ...editUser, phone: e.target.value })} style={hk.input} />
            </div>
            <div>
              <label style={hk.label}>Role</label>
              <select value={editUser.role} onChange={(e) => setEditUser({ ...editUser, role: e.target.value as any })} style={{ ...hk.input, appearance: "none" }}>
                {ROLES.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
              </select>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <input
                type="checkbox"
                id="is_active"
                checked={editUser.is_active}
                onChange={(e) => setEditUser({ ...editUser, is_active: e.target.checked })}
                style={{ accentColor: "#16a34a" }}
              />
              <label htmlFor="is_active" style={{ ...hk.label, margin: 0 }}>ACCOUNT ACTIVE</label>
            </div>
            <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
              <button type="button" onClick={() => setEditUser(null)} style={{ ...hk.btn("#0a140a"), flex: 1, justifyContent: "center" }}>CANCEL</button>
              <button type="submit" style={{ ...hk.btn(), flex: 1, justifyContent: "center" }}>SAVE</button>
            </div>
          </form>
        </Modal>
      )}

      {/* Reset password modal */}
      {resetUser && (
        <Modal title={`Reset Password — ${resetUser.username}`} onClose={() => { setResetUser(null); setNewPass(""); }}>
          <form onSubmit={handleResetPassword} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <div>
              <label style={hk.label}>New Password</label>
              <div style={{ position: "relative" }}>
                <input
                  type={showPass ? "text" : "password"}
                  required
                  minLength={6}
                  placeholder="Min 6 characters"
                  value={newPass}
                  onChange={(e) => setNewPass(e.target.value)}
                  style={{ ...hk.input, paddingRight: 36 }}
                />
                <button type="button" onClick={() => setShowPass(!showPass)} style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "#374151", cursor: "pointer" }}>
                  {showPass ? <MdVisibilityOff size={14} /> : <MdVisibility size={14} />}
                </button>
              </div>
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <button type="button" onClick={() => { setResetUser(null); setNewPass(""); }} style={{ ...hk.btn("#0a140a"), flex: 1, justifyContent: "center" }}>CANCEL</button>
              <button type="submit" style={{ ...hk.btn("#b45309"), flex: 1, justifyContent: "center" }}>RESET</button>
            </div>
          </form>
        </Modal>
      )}

      {/* Delete confirm modal */}
      {deleteUser && (
        <Modal title="Confirm Delete" onClose={() => setDeleteUser(null)}>
          <p style={{ color: "#6b7280", fontSize: 13, marginBottom: 16 }}>
            Permanently delete <strong style={{ color: "#d1fae5" }}>{deleteUser.full_name}</strong> (@{deleteUser.username})?
            This cannot be undone.
          </p>
          <div style={{ display: "flex", gap: 8 }}>
            <button onClick={() => setDeleteUser(null)} style={{ ...hk.btn("#0a140a"), flex: 1, justifyContent: "center" }}>CANCEL</button>
            <button onClick={handleDelete} style={{ ...hk.btn("#7f1d1d"), flex: 1, justifyContent: "center" }}>DELETE</button>
          </div>
        </Modal>
      )}
    </div>
  );
}

// ── Invites tab ───────────────────────────────────────────────────────────
function InvitesTab() {
  const [invites, setInvites] = useState<Invite[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ assigned_role: "field_user", invite_type: "qr", max_uses: 1, note: "" });
  const [qrData, setQrData] = useState<{ code: string; qr_image_base64: string } | null>(null);

  const load = () => {
    setLoading(true);
    adminApi.listInvites().then(({ data }) => setInvites(data)).catch(() => {}).finally(() => setLoading(false));
  };
  useEffect(load, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    const { data } = await adminApi.createInvite({ ...form, expires_in_hours: 168 });
    if (form.invite_type === "qr") {
      const qr = await adminApi.getInviteQR(data.id);
      setQrData(qr.data);
    }
    setShowForm(false);
    load();
  };

  const handleRevoke = async (id: string) => {
    await adminApi.revokeInvite(id).catch(() => {});
    load();
  };

  const handleShowQR = async (id: string) => {
    const { data } = await adminApi.getInviteQR(id);
    setQrData(data);
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <div style={{ display: "flex", justifyContent: "flex-end", gap: 8 }}>
        <button onClick={load} style={hk.btn("#0a140a")}><MdRefresh size={15} /></button>
        <button onClick={() => setShowForm(true)} style={hk.btn()}>
          <MdAdd size={15} /> GENERATE INVITE
        </button>
      </div>

      {loading ? (
        <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, padding: 20 }}>LOADING...</div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
          {invites.map((inv) => (
            <div key={inv.id} style={{ ...hk.card, padding: "12px 14px", display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
                  <span style={{ color: "#22c55e", fontFamily: "'JetBrains Mono', monospace", fontSize: 12 }}>{inv.code}</span>
                  <span style={{
                    fontFamily: "'JetBrains Mono', monospace", fontSize: 9, padding: "1px 6px",
                    background: inv.is_active ? "#052e16" : "#0a0a0a",
                    color: inv.is_active ? "#22c55e" : "#374151",
                  }}>
                    {inv.is_active ? "ACTIVE" : "USED"}
                  </span>
                  <RoleBadge role={inv.assigned_role} />
                </div>
                <span style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 10 }}>
                  {inv.invite_type?.toUpperCase()} · {inv.use_count}/{inv.max_uses} uses
                  {inv.note ? ` · ${inv.note}` : ""}
                </span>
              </div>
              <div style={{ display: "flex", gap: 4 }}>
                {inv.invite_type === "qr" && (
                  <button onClick={() => handleShowQR(inv.id)} style={{ background: "transparent", border: "1px solid #152015", color: "#4b5563", padding: "5px 7px", cursor: "pointer" }}
                    onMouseEnter={(e) => { e.currentTarget.style.color = "#22c55e"; e.currentTarget.style.borderColor = "#16a34a"; }}
                    onMouseLeave={(e) => { e.currentTarget.style.color = "#4b5563"; e.currentTarget.style.borderColor = "#152015"; }}
                  >
                    <MdQrCode size={14} />
                  </button>
                )}
                {inv.is_active && (
                  <button onClick={() => handleRevoke(inv.id)} style={{ background: "transparent", border: "1px solid #152015", color: "#4b5563", padding: "5px 7px", cursor: "pointer" }}
                    onMouseEnter={(e) => { e.currentTarget.style.color = "#ef4444"; e.currentTarget.style.borderColor = "#ef4444"; }}
                    onMouseLeave={(e) => { e.currentTarget.style.color = "#4b5563"; e.currentTarget.style.borderColor = "#152015"; }}
                  >
                    <MdBlock size={14} />
                  </button>
                )}
              </div>
            </div>
          ))}
          {invites.length === 0 && (
            <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, padding: "30px 0", textAlign: "center" }}>NO INVITES YET</div>
          )}
        </div>
      )}

      {showForm && (
        <Modal title="Generate Invite" onClose={() => setShowForm(false)}>
          <form onSubmit={handleCreate} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <div>
              <label style={hk.label}>Type</label>
              <select value={form.invite_type} onChange={(e) => setForm({ ...form, invite_type: e.target.value })} style={{ ...hk.input, appearance: "none" }}>
                <option value="qr">QR Code</option>
                <option value="voucher">Voucher Code</option>
              </select>
            </div>
            <div>
              <label style={hk.label}>Assign Role</label>
              <select value={form.assigned_role} onChange={(e) => setForm({ ...form, assigned_role: e.target.value })} style={{ ...hk.input, appearance: "none" }}>
                {ROLES.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
              </select>
            </div>
            <div>
              <label style={hk.label}>Max Uses</label>
              <input type="number" min={1} max={100} value={form.max_uses} onChange={(e) => setForm({ ...form, max_uses: parseInt(e.target.value) })} style={hk.input} />
            </div>
            <div>
              <label style={hk.label}>Note (optional)</label>
              <input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} placeholder="For field team alpha..." style={hk.input} />
            </div>
            <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
              <button type="button" onClick={() => setShowForm(false)} style={{ ...hk.btn("#0a140a"), flex: 1, justifyContent: "center" }}>CANCEL</button>
              <button type="submit" style={{ ...hk.btn(), flex: 1, justifyContent: "center" }}>GENERATE</button>
            </div>
          </form>
        </Modal>
      )}

      {qrData && (
        <Modal title="Enrollment QR Code" onClose={() => setQrData(null)}>
          <div style={{ textAlign: "center" }}>
            <img src={qrData.qr_image_base64} alt="QR" style={{ width: 200, height: 200, background: "#fff", padding: 8, margin: "0 auto 14px", display: "block" }} />
            <div style={{ background: "#040804", border: "1px solid #0f1f0f", padding: "8px 14px", display: "inline-block" }}>
              <span style={{ color: "#22c55e", fontFamily: "'JetBrains Mono', monospace", fontSize: 14, letterSpacing: 2 }}>{qrData.code}</span>
            </div>
            <p style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 10, marginTop: 12 }}>
              FIELD USERS SCAN WITH MOBILE APP TO ENROLL
            </p>
          </div>
        </Modal>
      )}
    </div>
  );
}

// ── Audit tab ─────────────────────────────────────────────────────────────
function AuditTab() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);

  const load = () => {
    setLoading(true);
    adminApi.getAuditLogs().then(({ data }) => setLogs(data.logs)).catch(() => {}).finally(() => setLoading(false));
  };
  useEffect(load, []);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <button onClick={load} style={hk.btn("#0a140a")}><MdRefresh size={15} /></button>
      </div>
      {loading ? (
        <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, padding: 20 }}>LOADING...</div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          {logs.map((log) => {
            const ok = (log.status_code ?? 0) < 400;
            return (
              <div key={log.id} style={{ ...hk.card, padding: "10px 14px", display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{
                  fontFamily: "'JetBrains Mono', monospace", fontSize: 10, fontWeight: 700, padding: "2px 6px",
                  background: ok ? "#052e16" : "#2d0a0a", color: ok ? "#22c55e" : "#ef4444", flexShrink: 0,
                }}>
                  {log.method} {log.status_code}
                </span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <span style={{ color: "#6b7280", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", display: "block" }}>
                    {log.action || log.path}
                  </span>
                </div>
                <span style={{ color: "#1f2d1f", fontFamily: "'JetBrains Mono', monospace", fontSize: 9, flexShrink: 0 }}>
                  {new Date(log.timestamp).toLocaleString("en-GB", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })}
                </span>
              </div>
            );
          })}
          {logs.length === 0 && (
            <div style={{ color: "#374151", fontFamily: "'JetBrains Mono', monospace", fontSize: 11, padding: "30px 0", textAlign: "center" }}>NO LOGS YET</div>
          )}
        </div>
      )}
    </div>
  );
}

// ── Root component ────────────────────────────────────────────────────────
export default function Admin() {
  const [tab, setTab] = useState<Tab>("overview");

  const TABS = [
    { key: "overview" as Tab, label: "OVERVIEW",  icon: <MdBarChart size={14} /> },
    { key: "users"    as Tab, label: "USERS",     icon: <MdPeople size={14} /> },
    { key: "invites"  as Tab, label: "INVITES",   icon: <MdQrCode size={14} /> },
    { key: "audit"    as Tab, label: "AUDIT LOG", icon: <MdHistory size={14} /> },
  ];

  return (
    <div style={{ padding: 24, display: "flex", flexDirection: "column", gap: 20, height: "100%", overflow: "auto" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <MdShield size={20} style={{ color: "#16a34a" }} />
        <div>
          <h2 style={{ color: "#d1fae5", fontSize: 16, fontWeight: 700, margin: 0, fontFamily: "'JetBrains Mono', monospace", letterSpacing: 1 }}>
            ADMINISTRATION
          </h2>
          <p style={{ color: "#374151", fontSize: 10, margin: 0, fontFamily: "'JetBrains Mono', monospace", letterSpacing: 1 }}>
            FULL SYSTEM CONTROL — COORDINATOR ACCESS
          </p>
        </div>
      </div>

      <div style={{ display: "flex", gap: 2, borderBottom: "1px solid #0f1f0f" }}>
        {TABS.map(({ key, label, icon }) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            style={{
              display: "flex", alignItems: "center", gap: 6,
              padding: "8px 14px", background: "transparent", border: "none",
              borderBottom: `2px solid ${tab === key ? "#16a34a" : "transparent"}`,
              cursor: "pointer", color: tab === key ? "#22c55e" : "#374151",
              fontFamily: "'JetBrains Mono', monospace", fontSize: 10, letterSpacing: 1,
              transition: "all 0.1s",
            }}
          >
            {icon}{label}
          </button>
        ))}
      </div>

      {tab === "overview" && <OverviewTab />}
      {tab === "users"    && <UsersTab />}
      {tab === "invites"  && <InvitesTab />}
      {tab === "audit"    && <AuditTab />}
    </div>
  );
}
