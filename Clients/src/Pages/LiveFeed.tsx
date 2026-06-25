import { useState, useEffect, useRef, useCallback } from "react";
import {
  MdOutlineLiveTv, MdOutlineStopCircle, MdOutlineVideoCall,
  MdOutlineGroup, MdOutlinePerson, MdOutlineSearch,
  MdOutlineHistory, MdPersonAdd, MdOutlineDelete,
  MdMic, MdMicOff, MdVideocam, MdVideocamOff, MdPeople,
} from "react-icons/md";
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
interface RemotePeer { stream: MediaStream; name: string; }

// ── Inline video tile ─────────────────────────────────────────────────────────

function RemoteVideoTile({ peerId, peer }: { peerId: string; peer: RemotePeer }) {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    if (ref.current) ref.current.srcObject = peer.stream;
  }, [peer.stream]);
  return (
    <div style={{ position: "relative", background: "#111827", borderRadius: 12, overflow: "hidden", aspectRatio: "16/9" }}>
      <video ref={ref} autoPlay playsInline style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />
      <div style={{ position: "absolute", bottom: 8, left: 10, color: "#fff", fontSize: 12, fontWeight: 600, background: "rgba(0,0,0,0.55)", padding: "2px 8px", borderRadius: 4 }}>
        {peer.name}
      </div>
    </div>
  );
}

function InvitePanel({ teams, users, selectedTeams, selectedUsers, onTeamToggle, onUserToggle }: {
  teams: Team[]; users: UserItem[];
  selectedTeams: string[]; selectedUsers: string[];
  onTeamToggle: (id: string) => void; onUserToggle: (id: string) => void;
}) {
  const [tab, setTab] = useState<"teams" | "users">("teams");
  const [q, setQ] = useState("");
  const filteredTeams = teams.filter(t => t.name.toLowerCase().includes(q.toLowerCase()));
  const filteredUsers = users.filter(u => (u.full_name || u.username).toLowerCase().includes(q.toLowerCase()));
  return (
    <div className="rounded-lg overflow-hidden" style={{ background: "#040804", border: "1px solid #1a2e1a" }}>
      <div className="flex" style={{ borderBottom: "1px solid #1a2e1a" }}>
        {(["teams", "users"] as const).map(t => (
          <button key={t} onClick={() => setTab(t)} className="flex-1 py-2 text-xs font-semibold uppercase tracking-widest flex items-center justify-center gap-1 transition-colors"
            style={{ color: tab === t ? "#22c55e" : "#4b5563", borderBottom: tab === t ? "2px solid #22c55e" : "2px solid transparent" }}>
            {t === "teams" ? <><MdOutlineGroup size={13} /> Teams ({selectedTeams.length})</> : <><MdOutlinePerson size={13} /> Users ({selectedUsers.length})</>}
          </button>
        ))}
      </div>
      <div className="p-2">
        <div className="flex items-center gap-2 mb-2 px-2 py-1 rounded" style={{ background: "#0a140a" }}>
          <MdOutlineSearch className="text-gray-500 shrink-0" size={13} />
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search…" className="bg-transparent text-white text-xs outline-none flex-1" />
        </div>
        <div className="max-h-40 overflow-y-auto space-y-0.5">
          {tab === "teams"
            ? filteredTeams.map(t => (
                <label key={t.id} className="flex items-center gap-2 px-2 py-1.5 rounded cursor-pointer hover:bg-green-900/20">
                  <input type="checkbox" checked={selectedTeams.includes(t.id)} onChange={() => onTeamToggle(t.id)} className="accent-green-500" />
                  <span className="text-white text-xs">{t.name}</span>
                </label>
              ))
            : filteredUsers.map(u => (
                <label key={u.id} className="flex items-center gap-2 px-2 py-1.5 rounded cursor-pointer hover:bg-green-900/20">
                  <input type="checkbox" checked={selectedUsers.includes(u.id)} onChange={() => onUserToggle(u.id)} className="accent-green-500" />
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
  const [newTitle, setNewTitle] = useState("");
  const [creating, setCreating] = useState(false);
  const [showInvite, setShowInvite] = useState(false);
  const [showPast, setShowPast] = useState(false);
  const [teams, setTeams] = useState<Team[]>([]);
  const [users, setUsers] = useState<UserItem[]>([]);
  const [selTeams, setSelTeams] = useState<string[]>([]);
  const [selUsers, setSelUsers] = useState<string[]>([]);
  const [showSessionInvite, setShowSessionInvite] = useState(false);
  const [sessionInviteTeams, setSessionInviteTeams] = useState<string[]>([]);
  const [sessionInviteUsers, setSessionInviteUsers] = useState<string[]>([]);
  const [sending, setSending] = useState(false);

  // WebRTC multi-party state
  const localVideoRef = useRef<HTMLVideoElement>(null);
  const localStreamRef = useRef<MediaStream | null>(null);
  const peersRef = useRef<Map<string, RTCPeerConnection>>(new Map());
  const peerNamesRef = useRef<Map<string, string>>(new Map());
  const wsRef = useRef<WebSocket | null>(null);
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [remoteStreams, setRemoteStreams] = useState<Record<string, RemotePeer>>({});
  const [participantCount, setParticipantCount] = useState(1);
  const [micOn, setMicOn] = useState(true);
  const [camOn, setCamOn] = useState(true);
  const [streamActive, setStreamActive] = useState(false);

  const load = useCallback(async () => {
    try {
      const { data } = await liveFeedApi.list();
      setSessions(Array.isArray(data) ? data.filter((s: LiveSession) => s.is_active) : []);
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  const loadPast = useCallback(async () => {
    try { const { data } = await liveFeedApi.listPast(); setPastSessions(Array.isArray(data) ? data : []); }
    catch { /**/ }
  }, []);

  useEffect(() => {
    load();
    teamApi.list().then(r => setTeams(r.data?.teams ?? r.data ?? [])).catch(() => {});
    userApi.list({ page_size: 100 }).then(r => setUsers(r.data?.users ?? [])).catch(() => {});
  }, [load]);

  useEffect(() => { if (showPast) loadPast(); }, [showPast, loadPast]);

  // ── WebRTC peer management ────────────────────────────────────────────────

  const createPC = useCallback((peerId: string, ws: WebSocket): RTCPeerConnection => {
    if (peersRef.current.has(peerId)) return peersRef.current.get(peerId)!;
    const pc = new RTCPeerConnection({ iceServers: [{ urls: "stun:stun.l.google.com:19302" }] });

    if (localStreamRef.current) {
      localStreamRef.current.getTracks().forEach(t => pc.addTrack(t, localStreamRef.current!));
    }

    pc.ontrack = (e) => {
      if (e.streams[0]) {
        setRemoteStreams(prev => ({
          ...prev,
          [peerId]: { stream: e.streams[0], name: peerNamesRef.current.get(peerId) ?? "Peer" },
        }));
      }
    };

    pc.onicecandidate = (e) => {
      if (e.candidate && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "ice_candidate", target: peerId, candidate: e.candidate }));
      }
    };

    peersRef.current.set(peerId, pc);
    return pc;
  }, []);

  const offerTo = useCallback(async (peerId: string, ws: WebSocket) => {
    const pc = createPC(peerId, ws);
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    ws.send(JSON.stringify({ type: "offer", target: peerId, sdp: offer }));
  }, [createPC]);

  const removePeer = useCallback((peerId: string) => {
    peersRef.current.get(peerId)?.close();
    peersRef.current.delete(peerId);
    peerNamesRef.current.delete(peerId);
    setRemoteStreams(prev => { const n = { ...prev }; delete n[peerId]; return n; });
  }, []);

  const startCall = useCallback(async (session: LiveSession) => {
    setActive(session);
    setRemoteStreams({});
    setParticipantCount(1);

    // Get local media
    let stream: MediaStream | null = null;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
      localStreamRef.current = stream;
      setLocalStream(stream);
      if (localVideoRef.current) localVideoRef.current.srcObject = stream;
      setStreamActive(true);
    } catch {
      setStreamActive(false);
    }

    const token = localStorage.getItem("access_token");
    const BASE_WS = (import.meta.env.VITE_API_URL || "http://localhost:1104").replace(/^http/, "ws");
    const ws = new WebSocket(`${BASE_WS}/ws/video/${session.id}?token=${encodeURIComponent(token ?? "")}`);
    wsRef.current = ws;

    ws.onmessage = async (ev) => {
      const msg = JSON.parse(ev.data);
      switch (msg.type) {
        case "room_state": {
          const peers = (msg.peers ?? []) as { user_id: string; name: string }[];
          setParticipantCount(peers.length + 1);
          for (const peer of peers) {
            peerNamesRef.current.set(peer.user_id, peer.name);
            await offerTo(peer.user_id, ws);
          }
          break;
        }
        case "peer_joined": {
          peerNamesRef.current.set(msg.user_id, msg.name ?? msg.user_id);
          setParticipantCount(p => p + 1);
          break;
        }
        case "peer_left": {
          removePeer(msg.user_id);
          setParticipantCount(p => Math.max(1, p - 1));
          break;
        }
        case "offer": {
          const pc = createPC(msg.from, ws);
          await pc.setRemoteDescription(new RTCSessionDescription(msg.sdp));
          const answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          ws.send(JSON.stringify({ type: "answer", target: msg.from, sdp: answer }));
          break;
        }
        case "answer": {
          const pc = peersRef.current.get(msg.from);
          if (pc) await pc.setRemoteDescription(new RTCSessionDescription(msg.sdp)).catch(() => {});
          break;
        }
        case "ice_candidate": {
          const pc = peersRef.current.get(msg.from);
          if (pc && msg.candidate) await pc.addIceCandidate(new RTCIceCandidate(msg.candidate)).catch(() => {});
          break;
        }
      }
    };

    ws.onclose = () => setParticipantCount(1);
  }, [offerTo, removePeer, createPC]);

  const leaveCall = useCallback(async (end = false) => {
    localStreamRef.current?.getTracks().forEach(t => t.stop());
    localStreamRef.current = null;
    for (const [id] of peersRef.current) removePeer(id);
    wsRef.current?.close();
    wsRef.current = null;
    if (end && active) await liveFeedApi.end(active.id).catch(() => {});
    setActive(null);
    setLocalStream(null);
    setRemoteStreams({});
    setStreamActive(false);
    setParticipantCount(1);
    if (localVideoRef.current) localVideoRef.current.srcObject = null;
    load();
  }, [active, removePeer, load]);

  const handleDeleteSession = async (id: string) => {
    if (!confirm("Delete this session? All participants will be disconnected.")) return;
    await liveFeedApi.delete(id).catch(() => {});
    load();
  };

  const toggleMic = () => {
    localStreamRef.current?.getAudioTracks().forEach(t => { t.enabled = !t.enabled; });
    setMicOn(p => !p);
  };
  const toggleCam = () => {
    localStreamRef.current?.getVideoTracks().forEach(t => { t.enabled = !t.enabled; });
    setCamOn(p => !p);
  };

  const createSession = async () => {
    if (!newTitle.trim()) return;
    setCreating(true);
    try {
      const { data } = await liveFeedApi.create({ title: newTitle, invite_team_ids: selTeams, invite_user_ids: selUsers });
      setNewTitle(""); setSelTeams([]); setSelUsers([]); setShowInvite(false);
      await startCall({ ...data, title: newTitle, host_id: user!.id, is_active: true });
    } catch { /**/ } finally { setCreating(false); }
  };

  const sendSessionInvites = async () => {
    if (!active || (!sessionInviteTeams.length && !sessionInviteUsers.length)) return;
    setSending(true);
    try { await liveFeedApi.invite(active.id, { user_ids: sessionInviteUsers, team_ids: sessionInviteTeams }); setShowSessionInvite(false); setSessionInviteTeams([]); setSessionInviteUsers([]); }
    catch { /**/ } finally { setSending(false); }
  };

  // ── In-call view ──────────────────────────────────────────────────────────

  if (active) {
    const remotePeers = Object.entries(remoteStreams);
    const isHost = active.host_id === user?.id;
    const totalCount = participantCount;

    return (
      <div style={{ height: "100vh", background: "#0a0f0a", display: "flex", flexDirection: "column" }}>
        {/* Header */}
        <div style={{ padding: "12px 20px", background: "#060d06", borderBottom: "1px solid #0a1f0a", display: "flex", alignItems: "center", justifyContent: "space-between", flexShrink: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#ef4444", animation: "pulse 2s infinite" }} />
            <span style={{ color: "#f0fdf4", fontWeight: 700, fontSize: 15 }}>{active.title}</span>
            <div style={{ display: "flex", alignItems: "center", gap: 4, padding: "3px 10px", background: "#1a2e1a", border: "1px solid #16a34a", color: "#22c55e", fontSize: 12, borderRadius: 20 }}>
              <MdPeople size={13} /> {totalCount} {totalCount === 1 ? "participant" : "participants"}
            </div>
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            {isHost && (
              <button onClick={() => setShowSessionInvite(p => !p)}
                style={{ padding: "6px 12px", background: "#0a1f0a", border: "1px solid #16a34a", color: "#22c55e", fontSize: 12, borderRadius: 8, cursor: "pointer", display: "flex", alignItems: "center", gap: 6 }}>
                <MdPersonAdd size={14} /> Invite
              </button>
            )}
          </div>
        </div>

        {/* Invite panel */}
        {isHost && showSessionInvite && (
          <div style={{ padding: "12px 20px", background: "#060d06", borderBottom: "1px solid #0a1f0a" }}>
            <InvitePanel teams={teams} users={users} selectedTeams={sessionInviteTeams} selectedUsers={sessionInviteUsers}
              onTeamToggle={(id) => setSessionInviteTeams(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id])}
              onUserToggle={(id) => setSessionInviteUsers(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id])} />
            <button onClick={sendSessionInvites} disabled={sending || (!sessionInviteTeams.length && !sessionInviteUsers.length)}
              style={{ marginTop: 10, width: "100%", padding: "8px 0", background: "#16a34a", border: "none", color: "#000", fontWeight: 700, fontSize: 13, borderRadius: 8, cursor: "pointer", opacity: sending ? 0.5 : 1 }}>
              {sending ? "Sending…" : "Send Invites"}
            </button>
          </div>
        )}

        {/* Video grid */}
        <div style={{ flex: 1, padding: 16, overflowY: "auto" }}>
          {remotePeers.length === 0 ? (
            <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 16 }}>
              <MdOutlineGroup size={56} color="#1f3d1f" />
              <div style={{ color: "#4b5563", fontSize: 15, fontWeight: 600 }}>Waiting for others to join…</div>
              <div style={{ color: "#374151", fontSize: 12 }}>Share the session with your team</div>
            </div>
          ) : (
            <div style={{ display: "grid", gridTemplateColumns: remotePeers.length === 1 ? "1fr" : "repeat(auto-fill, minmax(360px, 1fr))", gap: 12 }}>
              {remotePeers.map(([peerId, peer]) => (
                <RemoteVideoTile key={peerId} peerId={peerId} peer={peer} />
              ))}
            </div>
          )}
        </div>

        {/* Local video PIP */}
        <div style={{ position: "fixed", bottom: 100, right: 20, width: 160, height: 90, borderRadius: 12, overflow: "hidden", border: "2px solid #16a34a", background: "#111", boxShadow: "0 4px 20px rgba(0,0,0,0.6)", zIndex: 10 }}>
          {!camOn ? (
            <div style={{ width: "100%", height: "100%", background: "#111827", display: "flex", alignItems: "center", justifyContent: "center" }}>
              <MdVideocamOff size={28} color="#374151" />
            </div>
          ) : (
            <video ref={localVideoRef} autoPlay muted playsInline style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          )}
          <div style={{ position: "absolute", bottom: 4, left: 6, color: "#fff", fontSize: 10, background: "rgba(0,0,0,0.55)", padding: "1px 5px", borderRadius: 3 }}>
            You {!streamActive && "(no cam)"}
          </div>
        </div>

        {/* Controls bar */}
        <div style={{ padding: "16px 20px", background: "#060d06", borderTop: "1px solid #0a1f0a", display: "flex", alignItems: "center", justifyContent: "center", gap: 16, flexShrink: 0 }}>
          <button onClick={toggleMic} style={{ width: 52, height: 52, borderRadius: "50%", background: micOn ? "#1f2937" : "#7f1d1d", border: "none", color: micOn ? "#d1d5db" : "#fca5a5", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>
            {micOn ? <MdMic size={22} /> : <MdMicOff size={22} />}
          </button>
          <button onClick={toggleCam} style={{ width: 52, height: 52, borderRadius: "50%", background: camOn ? "#1f2937" : "#7f1d1d", border: "none", color: camOn ? "#d1d5db" : "#fca5a5", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>
            {camOn ? <MdVideocam size={22} /> : <MdVideocamOff size={22} />}
          </button>
          <button onClick={() => leaveCall(false)} style={{ padding: "12px 28px", borderRadius: 26, background: "#dc2626", border: "none", color: "#fff", fontWeight: 700, fontSize: 14, cursor: "pointer" }}>
            Leave
          </button>
          {isHost && (
            <button onClick={() => leaveCall(true)} style={{ padding: "12px 28px", borderRadius: 26, background: "#7f1d1d", border: "1px solid #dc2626", color: "#fca5a5", fontWeight: 700, fontSize: 14, cursor: "pointer" }}>
              End for All
            </button>
          )}
        </div>
      </div>
    );
  }

  // ── Session list ──────────────────────────────────────────────────────────

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-white font-bold text-xl flex items-center gap-2">
            <MdOutlineLiveTv className="text-red-500" size={22} /> Live Sessions
          </h1>
          <p className="text-gray-500 text-sm mt-0.5">{sessions.length} active · Google Meet-style multi-party</p>
        </div>
        <button onClick={() => setShowPast(p => !p)} className="flex items-center gap-1.5 px-3 py-1.5 rounded text-xs font-semibold"
          style={{ background: "#0a140a", color: "#9ca3af", border: "1px solid #1a2e1a" }}>
          <MdOutlineHistory size={14} /> Past Sessions
        </button>
      </div>

      {/* Create */}
      <div className="mb-4 rounded-xl p-4" style={{ background: "#060d06", border: "1px solid #1a2e1a" }}>
        <div className="flex gap-3 mb-3">
          <input value={newTitle} onChange={(e) => setNewTitle(e.target.value)} placeholder="New session title…"
            className="flex-1 px-4 py-2.5 rounded-lg text-white text-sm" style={{ background: "#040804", border: "1px solid #374151" }}
            onKeyDown={(e) => e.key === "Enter" && createSession()} />
          <button onClick={() => setShowInvite(p => !p)} className="flex items-center gap-1.5 px-3 py-2.5 rounded-lg text-xs font-semibold"
            style={{ background: showInvite ? "#14532d" : "#0a140a", color: "#22c55e", border: "1px solid #16a34a" }}>
            <MdOutlineGroup size={14} />
            Invite{(selTeams.length + selUsers.length) > 0 ? ` (${selTeams.length + selUsers.length})` : ""}
          </button>
          <button onClick={createSession} disabled={creating || !newTitle.trim()}
            className="flex items-center gap-1.5 px-5 py-2.5 rounded-lg text-white text-sm font-semibold disabled:opacity-40"
            style={{ background: "#16a34a" }}>
            <MdOutlineVideoCall size={16} />
            {creating ? "Starting…" : "Start Session"}
          </button>
        </div>
        {showInvite && (
          <InvitePanel teams={teams} users={users} selectedTeams={selTeams} selectedUsers={selUsers}
            onTeamToggle={(id) => setSelTeams(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id])}
            onUserToggle={(id) => setSelUsers(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id])} />
        )}
      </div>

      {/* Past sessions */}
      {showPast && (
        <div className="mb-6 rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #1a2e1a" }}>
          <div className="px-4 py-2 flex items-center gap-2" style={{ borderBottom: "1px solid #1a2e1a" }}>
            <MdOutlineHistory size={14} className="text-gray-400" />
            <span className="text-gray-300 text-xs font-semibold uppercase tracking-widest">Past Sessions</span>
          </div>
          {pastSessions.length === 0 ? <p className="px-4 py-4 text-gray-500 text-xs">No past sessions.</p>
            : pastSessions.map(s => (
              <div key={s.id} className="px-4 py-3 flex items-center gap-3" style={{ borderBottom: "1px solid #0a140a" }}>
                <MdOutlineStopCircle className="text-gray-600 shrink-0" size={16} />
                <span className="text-white text-sm flex-1">{s.title}</span>
                <span className="text-gray-500 text-xs">{s.started_at ? new Date(s.started_at).toLocaleString("en-GB", { dateStyle: "short", timeStyle: "short" }) : "—"}</span>
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
          <p className="text-gray-400 text-sm">No active sessions — start one above</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {sessions.map((s) => (
            <div key={s.id} className="rounded-xl overflow-hidden" style={{ background: "#060d06", border: "1px solid #0a140a" }}>
              <div className="h-36 flex items-center justify-center cursor-pointer" style={{ background: "#040804" }}
                onClick={() => startCall(s)}>
                <MdOutlineLiveTv className="text-red-500 animate-pulse" size={48} />
              </div>
              <div className="p-4">
                <div className="flex items-center gap-2 mb-1">
                  <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse shrink-0" />
                  <h3 className="text-white text-sm font-semibold flex-1 line-clamp-1 cursor-pointer" onClick={() => startCall(s)}>{s.title}</h3>
                  {s.host_id === user?.id && (
                    <button onClick={() => handleDeleteSession(s.id)} title="Delete session"
                      style={{ background: "none", border: "none", color: "#6b7280", cursor: "pointer", padding: "2px", flexShrink: 0 }}>
                      <MdOutlineDelete size={16} />
                    </button>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <p className="text-gray-500 text-xs flex-1">
                    {s.host_id === user?.id ? "You're hosting" : "Live now"} · {s.created_at ? new Date(s.created_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }) : ""}
                  </p>
                  {(s.invite_list?.length ?? 0) > 0 && (
                    <span className="flex items-center gap-1 text-gray-500 text-xs">
                      <MdOutlineGroup size={12} /> {s.invite_list!.length}
                    </span>
                  )}
                </div>
                <button onClick={() => startCall(s)}
                  className="mt-3 w-full py-2 rounded-lg text-xs font-semibold"
                  style={{ background: "#16a34a", color: "#000" }}>
                  Join Session
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
