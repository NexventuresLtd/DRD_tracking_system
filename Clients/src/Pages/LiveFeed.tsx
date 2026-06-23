import { useState, useEffect, useRef, useCallback } from "react";
import api from "../services/api";
import { useAuthStore } from "../stores/authStore";

interface LiveSession {
  id: string;
  title: string;
  host_id: string;
  is_active: boolean;
  viewer_count?: number;
  created_at: string;
}

export default function LiveFeedPage() {
  const { user } = useAuthStore();
  const [sessions, setSessions] = useState<LiveSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [active, setActive] = useState<LiveSession | null>(null);
  const [hosting, setHosting] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [creating, setCreating] = useState(false);
  const localVideoRef = useRef<HTMLVideoElement>(null);
  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const [streamActive, setStreamActive] = useState(false);
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);

  const load = useCallback(async () => {
    try {
      const { data } = await api.get("/live-sessions");
      setSessions(data.filter((s: LiveSession) => s.is_active));
    } catch { /**/ } finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const createSession = async () => {
    if (!newTitle.trim()) return;
    setCreating(true);
    try {
      const { data } = await api.post("/live-sessions", { title: newTitle, is_public: true });
      setNewTitle("");
      await load();
      joinSession({ ...data, title: newTitle, host_id: user!.id, is_active: true, created_at: new Date().toISOString() }, true);
    } catch { /**/ } finally { setCreating(false); }
  };

  const joinSession = async (session: LiveSession, asHost = false) => {
    setActive(session);
    setHosting(asHost);
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
      if (e.candidate && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "ice_candidate", candidate: e.candidate }));
      }
    };

    pc.ontrack = (e) => {
      if (remoteVideoRef.current) remoteVideoRef.current.srcObject = e.streams[0];
    };

    if (asHost) {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
        setLocalStream(stream);
        stream.getTracks().forEach((t) => pc.addTrack(t, stream));
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
    localStream?.getTracks().forEach((t) => t.stop());
    pcRef.current?.close();
    wsRef.current?.close();
    setActive(null);
    setHosting(false);
    setStreamActive(false);
    setLocalStream(null);
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
            className="px-4 py-2 rounded-lg text-white text-sm font-semibold"
            style={{ background: "#dc2626" }}>
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
          <div className="mt-4 text-center text-gray-400 text-sm">
            Camera access denied or unavailable. Grant camera permission to broadcast.
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-white font-bold text-xl">Live Feeds</h1>
          <p className="text-gray-500 text-sm mt-0.5">{sessions.length} active streams</p>
        </div>
      </div>

      {/* Create session */}
      <div className="mb-6 flex gap-3">
        <input value={newTitle} onChange={(e) => setNewTitle(e.target.value)}
          placeholder="New stream title…" className="flex-1 px-4 py-2.5 rounded-lg text-white text-sm"
          style={{ background: "#060d06", border: "1px solid #374151" }}
          onKeyDown={(e) => e.key === "Enter" && createSession()} />
        <button onClick={createSession} disabled={creating || !newTitle.trim()}
          className="px-5 py-2.5 rounded-lg text-white text-sm font-semibold hover:opacity-90 disabled:opacity-40"
          style={{ background: "#16a34a" }}>
          {creating ? "Starting…" : "Go Live"}
        </button>
      </div>

      {loading ? (
        <div className="text-center py-12 text-gray-500">Loading…</div>
      ) : sessions.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-gray-500 text-4xl mb-3">📡</p>
          <p className="text-gray-400 text-sm">No active streams — start one above</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {sessions.map((s) => (
            <div key={s.id} className="rounded-xl overflow-hidden cursor-pointer group"
              style={{ background: "#060d06", border: "1px solid #0a140a" }}
              onClick={() => joinSession(s, s.host_id === user?.id)}>
              <div className="h-36 flex items-center justify-center" style={{ background: "#040804" }}>
                <span className="text-5xl">📡</span>
              </div>
              <div className="p-4">
                <div className="flex items-center gap-2 mb-1">
                  <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse shrink-0" />
                  <h3 className="text-white text-sm font-semibold line-clamp-1">{s.title}</h3>
                </div>
                <p className="text-gray-500 text-xs">
                  {s.host_id === user?.id ? "Your stream" : "Live now"} · {new Date(s.created_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
