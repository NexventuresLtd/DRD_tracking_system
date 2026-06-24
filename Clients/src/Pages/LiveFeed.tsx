import { useState, useEffect, useRef, useCallback } from "react";
import { MdOutlineLiveTv, MdOutlineStopCircle, MdOutlineVideoCall,
         MdOutlineGroup, MdOutlinePerson, MdOutlineSearch,
         MdOutlineHistory, MdOutlineAdd } from "react-icons/md";
import { teamApi, userApi, liveFeedApi } from "../services/api";
import { useAuthStore } from "../stores/authStore";

interface LiveSession {
  id: string;
  title: string;
  host_id: string;
  is_active: boolean;
  mission_id?: string;
  viewer_count?: number;
  invite_list?: string[];
  started_at?: string;
  created_at?: string;
}

interface Team { id: string; name: string; }
interface UserItem { id: string; full_name: string; username: string; role: string; }

function InvitePanel({
  teams, users, selectedTeams, selectedUsers, onTeamToggle, onUserToggle,
}: {
  teams: Team[]; users: UserItem[];
  selectedTeams: string[]; selectedUsers: string[];
  onTeamToggle: (id: string) => void;
  onUserToggle: (id: string) => void;
}) {
  const [tab, setTab] = useState<"teams" | "users">("teams");
  const [q, setQ] = useState("");
  const filteredTeams = teams.filter(t => t.name.toLowerCase().includes(q.toLowerCase()));
  const filteredUsers = users.filter(u =>
    (u.full_name || u.username).toLowerCase().includes(q.toLowerCase())
  );
  return (
    <div className="rounded-lg overflow-hidden" style={{ background: "#040804", border: "1px solid #1a2e1a" }}>
      <div className="flex" style={{ borderBottom: "1px solid #1a2e1a" }}>
        {(["teams", "users"] as const).map(t => (
          <button key={t} onClick={() => setTab(t)}
            className="flex-1 py-2 text-xs font-semibold uppercase tracking-widest flex items-center justify-center gap-1 transition-colors"
            style={{
              color: tab === t ? "#22c55e" : "#4b5563",
              borderBottom: tab === t ? "2px solid #22c55e" : "2px solid transparent",
            }}>
            {t === "teams"
              ? <><MdOutlineGroup size={13} /> Teams ({selectedTeams.length})</>
              : <><MdOutlinePerson size={13} /> Users ({selectedUsers.length})</>
            }
          </button>
        ))}
      </div>
      <div className="p-2">
        <div className="flex items-center gap-2 mb-2 px-2 py-1 rounded" style={{ background: "#0a140a" }}>
          <MdOutlineSearch className="text-gray-500 shrink-0" size={13} />
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search…"
            className="bg-transparent text-white text-xs outline-none flex-1" />
        </div>
        <div className="max-h-40 overflow-y-auto space-y-0.5">
          {tab === "teams"
            ? filteredTeams.map(t => (
                <label key={t.id} className="flex items-center gap-2 px-2 py-1.5 rounded cursor-pointer hover:bg-green-900/20">
                  <input type="checkbox" checked={selectedTeams.includes(t.id)}
                    onChange={() => onTeamToggle(t.id)} className="accent-green-500" />
                  <span className="text-white text-xs">{t.name}</span>
                </label>
              ))
            : filteredUsers.map(u => (
                <label key={u.id} className="flex items-center gap-2 px-2 py-1.5 rounded cursor-pointer hover:bg-green-900/20">
                  <input type="checkbox" checked={selectedUsers.includes(u.id)}
                    onChange={() => onUserToggle(u.id)} className="accent-green-500" />
                  <span className="text-white text-xs">{u.full_name || u.username}</span>
                  <span className="text-gray-500 text-xs ml-auto">{u.role?.replace("_", " ")}</span>
                </label>
              ))
          }
        </div>
      </div>
    </div>
  );
}

export default function LiveFeedPage() {
  const { user } = useAuthStore();
  const [sessions, setSessions] = useState<LiveSession[]>([]);
  const [pastSessions, setPastSessions] = useState<LiveSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [active, setActive] = useState<LiveSession | null>(null);
  const [hosting, setHosting] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [creating, setCreating] = useState(false);
  const [showInvite, setShowInvite] = useState(false);
  const [showPast, setShowPast] = useState(false);
  const [teams, setTeams] = useState<Team[]>([]);
  const [users, setUsers] = useState<UserItem[]>([]);
  const [selTeams, setSelTeams] = useState<string[]>([]);
  const [selUsers, setSelUsers] = useState<string[]>([]);
  const localVideoRef = useRef<HTMLVideoElement>(null);
  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const [streamActive, setStreamActive] = useState(false);
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);

  const load = useCallback(async () => {
    try {
      const { data } = await liveFeedApi.list();
      setSessions(Array.isArray(data) ? data.filter((s: LiveSession) => s.is_active) : []);
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  const loadPast = useCallback(async () => {
    try {
      const { data } = await liveFeedApi.listPast();
      setPastSessions(Array.isArray(data) ? data : []);
    } catch { /**/ }
  }, []);

  useEffect(() => {
    load();
    teamApi.list().then(r => setTeams(r.data?.teams ?? r.data ?? [])).catch(() => {});
    userApi.list({ page_size: 100 }).then(r => setUsers(r.data?.users ?? [])).catch(() => {});
  }, [load]);

  useEffect(() => { if (showPast) loadPast(); }, [showPast, loadPast]);

  const toggleTeam = (id: string) => setSelTeams(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id]);
  const toggleUser = (id: string) => setSelUsers(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id]);

  const createSession = async () => {
    if (!newTitle.trim()) return;
    setCreating(true);
    try {
      const { data } = await liveFeedApi.create({
        title: newTitle,
        invite_team_ids: selTeams,
        invite_user_ids: selUsers,
      });
      setNewTitle(""); setSelTeams([]); setSelUsers([]); setShowInvite(false);
      await load();
      joinSession({ ...data, title: newTitle, host_id: user!.id, is_active: true, created_at: new Date().toISOString() }, true);
    } catch { /**/ } finally { setCreating(false); }
  };

  const joinSession = async (session: LiveSession, asHost = false) => {
    setActive(session); setHosting(asHost);
    await startWebRTC(session.id, asHost);
  };

  const startWebRTC = async (sessionId: string, asHost: boolean) => {
    const token = localStorage.getItem("access_token");
    const BASE_WS = (import.meta.env.VITE_API_URL || "http://localhost:1104").replace(/^http/, "ws");
    const ws = new WebSocket(`${BASE_WS}/ws/video/${sessionId}?token=${encodeURIComponent(token ?? "")}`);
    wsRef.current = ws;
    const pc = new RTCPeerConnection({ iceServers: [{ urls: "stun:stun.l.google.com:19302" }] });
    pcRef.current = pc;
    pc.onicecandidate = (e) => {
      if (e.candidate && ws.readyState === WebSocket.OPEN)
        ws.send(JSON.stringify({ type: "ice_candidate", candidate: e.candidate }));
    };
    pc.ontrack = (e) => { if (remoteVideoRef.current) remoteVideoRef.current.srcObject = e.streams[0]; };
    if (asHost) {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
        setLocalStream(stream);
        stream.getTracks().forEach(t => pc.addTrack(t, stream));
        if (localVideoRef.current) localVideoRef.current.srcObject = stream;
        setStreamActive(true);
      } catch { /**/ }
    }
    ws.onmessage = async (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.type === "offer" && !asHost) {
        await pc.setRemoteDescription(new RTCSessionDescription(msg.sdp));
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        ws.send(JSON.stringify({ type: "answer", sdp: answer }));
      } else if (msg.type === "answer" && asHost) {
        await pc.setRemoteDescription(new RTCSessionDescription(msg.sdp));
      } else if (msg.type === "ice_candidate" && msg.candidate) {
        await pc.addIceCandidate(new RTCIceCandidate(msg.candidate)).catch(() => {});
      } else if (msg.type === "viewer_joined" && asHost) {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        ws.send(JSON.stringify({ type: "offer", sdp: offer }));
      }
    };
  };

  const leaveSession = () => {
    localStream?.getTracks().forEach(t => t.stop());
    pcRef.current?.close();
    wsRef.current?.close();
    setActive(null); setHosting(false); setStreamActive(false); setLocalStream(null);
    if (localVideoRef.current) localVideoRef.current.srcObject = null;
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null;
    load();
  };

  if (active) {
    return (
      <div className="p-6">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h1 className="text-white font-bold text-xl">{active.title}</h1>
            <p className="text-gray-400 text-sm">{hosting ? "Broadcasting" : "Viewing"}</p>
          </div>
          <button onClick={leaveSession}
            className="flex items-center gap-2 px-4 py-2 rounded-lg text-white text-sm font-semibold"
            style={{ background: "#dc2626" }}>
            <MdOutlineStopCircle size={16} />
            {hosting ? "Stop Stream" : "Leave"}
          </button>
        </div>
        <div className={`grid gap-4 ${hosting ? "grid-cols-1 lg:grid-cols-2" : "grid-cols-1"}`}>
          {hosting && (
            <div className="rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
              <div className="px-4 py-2 flex items-center gap-2" style={{ borderBottom: "1px solid #0a140a" }}>
                <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                <span className="text-white text-xs font-semibold">Your Camera</span>
              </div>
              <video ref={localVideoRef} autoPlay muted playsInline className="w-full aspect-video object-cover bg-black" />
            </div>
          )}
          <div className="rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
            <div className="px-4 py-2" style={{ borderBottom: "1px solid #0a140a" }}>
              <span className="text-white text-xs font-semibold">{hosting ? "Remote Viewer" : "Live Stream"}</span>
            </div>
            <video ref={remoteVideoRef} autoPlay playsInline className="w-full aspect-video object-cover bg-black" />
          </div>
        </div>
        {hosting && !streamActive && (
          <p className="mt-4 text-center text-gray-400 text-sm">Camera access denied. Grant permission to broadcast.</p>
        )}
      </div>
    );
  }

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-white font-bold text-xl flex items-center gap-2">
            <MdOutlineLiveTv className="text-red-500" size={22} /> Live Feeds
          </h1>
          <p className="text-gray-500 text-sm mt-0.5">{sessions.length} active stream{sessions.length !== 1 ? "s" : ""}</p>
        </div>
        <button onClick={() => setShowPast(p => !p)}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded text-xs font-semibold"
          style={{ background: "#0a140a", color: "#9ca3af", border: "1px solid #1a2e1a" }}>
          <MdOutlineHistory size={14} /> Past Sessions
        </button>
      </div>

      {/* Create session */}
      <div className="mb-4 rounded-xl p-4" style={{ background: "#060d06", border: "1px solid #1a2e1a" }}>
        <div className="flex gap-3 mb-3">
          <input value={newTitle} onChange={(e) => setNewTitle(e.target.value)}
            placeholder="New stream title…" className="flex-1 px-4 py-2.5 rounded-lg text-white text-sm"
            style={{ background: "#040804", border: "1px solid #374151" }}
            onKeyDown={(e) => e.key === "Enter" && createSession()} />
          <button onClick={() => setShowInvite(p => !p)}
            className="flex items-center gap-1.5 px-3 py-2.5 rounded-lg text-xs font-semibold transition-colors"
            style={{
              background: showInvite ? "#14532d" : "#0a140a",
              color: "#22c55e",
              border: "1px solid #16a34a",
            }}>
            <MdOutlineGroup size={14} />
            Invite{(selTeams.length + selUsers.length) > 0 ? ` (${selTeams.length + selUsers.length})` : ""}
          </button>
          <button onClick={createSession} disabled={creating || !newTitle.trim()}
            className="flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold hover:opacity-90 disabled:opacity-40"
            style={{ background: "#16a34a" }}>
            <MdOutlineVideoCall size={16} />
            {creating ? "Starting…" : "Go Live"}
          </button>
        </div>
        {showInvite && (
          <InvitePanel teams={teams} users={users}
            selectedTeams={selTeams} selectedUsers={selUsers}
            onTeamToggle={toggleTeam} onUserToggle={toggleUser} />
        )}
      </div>

      {/* Past sessions */}
      {showPast && (
        <div className="mb-6 rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #1a2e1a" }}>
          <div className="px-4 py-2 flex items-center gap-2" style={{ borderBottom: "1px solid #1a2e1a" }}>
            <MdOutlineHistory size={14} className="text-gray-400" />
            <span className="text-gray-300 text-xs font-semibold uppercase tracking-widest">Past Recordings</span>
          </div>
          {pastSessions.length === 0
            ? <p className="px-4 py-4 text-gray-500 text-xs">No past sessions found.</p>
            : pastSessions.map(s => (
                <div key={s.id} className="px-4 py-3 flex items-center gap-3" style={{ borderBottom: "1px solid #0a140a" }}>
                  <MdOutlineStopCircle className="text-gray-600 shrink-0" size={16} />
                  <span className="text-white text-sm flex-1">{s.title}</span>
                  <span className="text-gray-500 text-xs">
                    {s.started_at ? new Date(s.started_at).toLocaleString("en-GB", { dateStyle: "short", timeStyle: "short" }) : "—"}
                  </span>
                </div>
              ))
          }
        </div>
      )}

      {/* Active sessions grid */}
      {loading ? (
        <div className="text-center py-12 text-gray-500">Loading…</div>
      ) : sessions.length === 0 ? (
        <div className="text-center py-12">
          <MdOutlineLiveTv className="mx-auto text-gray-600 mb-3" size={40} />
          <p className="text-gray-400 text-sm">No active streams — start one above</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {sessions.map((s) => (
            <div key={s.id} className="rounded-xl overflow-hidden cursor-pointer"
              style={{ background: "#060d06", border: "1px solid #0a140a" }}
              onClick={() => joinSession(s, s.host_id === user?.id)}>
              <div className="h-36 flex items-center justify-center" style={{ background: "#040804" }}>
                <MdOutlineLiveTv className="text-red-500 animate-pulse" size={48} />
              </div>
              <div className="p-4">
                <div className="flex items-center gap-2 mb-1">
                  <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse shrink-0" />
                  <h3 className="text-white text-sm font-semibold line-clamp-1">{s.title}</h3>
                </div>
                <div className="flex items-center gap-2">
                  <p className="text-gray-500 text-xs">
                    {s.host_id === user?.id ? "Your stream" : "Live now"} ·{" "}
                    {s.created_at ? new Date(s.created_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }) : ""}
                  </p>
                  {(s.invite_list?.length ?? 0) > 0 && (
                    <span className="ml-auto flex items-center gap-1 text-gray-500 text-xs">
                      <MdOutlineGroup size={12} /> {s.invite_list!.length}
                    </span>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
