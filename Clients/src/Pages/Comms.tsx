import { useCallback, useEffect, useRef, useState } from "react";
import { useLocation } from "react-router-dom";
import { messageApi, teamApi, userApi, evidenceApi } from "../services/api";
import api from "../services/api";
import type { Message, Team, TeamMember } from "../types";
import { useAuthStore } from "../stores/authStore";
import {
  MdSend,
  MdPublic,
  MdPeople,
  MdPerson,
  MdCrisisAlert,
  MdVideocam,
  MdVideocamOff,
  MdMic,
  MdMicOff,
  MdCallEnd,
  MdAttachFile,
  MdAdd,
  MdCheck,
  MdClose,
  MdVideoCall,
} from "react-icons/md";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ChannelType = "global" | "team" | "dm" | "emergency";

type Channel = {
  id: string;
  label: string;
  type: ChannelType;
  icon: React.ReactNode;
};

type ChannelMeta = {
  type: ChannelType;
  id: string;
  name: string;
  last_message: { content: string; sender_name: string; sent_at: string } | null;
  unread_count: number;
};

type PeerInfo = { name: string; stream: MediaStream | null; muted?: boolean; cameraOff?: boolean };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatTimestamp(isoStr: string): string {
  const date = new Date(isoStr);
  const now = new Date();
  const isToday =
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  const diffMs = now.getTime() - date.getTime();
  const diffDays = diffMs / (1000 * 60 * 60 * 24);
  if (isToday) return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  if (diffDays < 7)
    return date.toLocaleDateString([], { weekday: "short" });
  return date.toLocaleDateString([], { month: "2-digit", day: "2-digit" });
}

function formatDateSeparator(isoStr: string): string {
  const date = new Date(isoStr);
  const now = new Date();
  const isToday =
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday =
    date.getFullYear() === yesterday.getFullYear() &&
    date.getMonth() === yesterday.getMonth() &&
    date.getDate() === yesterday.getDate();
  if (isToday) return "Today";
  if (isYesterday) return "Yesterday";
  return date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
}

function isSameDay(a: string, b: string): boolean {
  const da = new Date(a);
  const db = new Date(b);
  return (
    da.getFullYear() === db.getFullYear() &&
    da.getMonth() === db.getMonth() &&
    da.getDate() === db.getDate()
  );
}

function truncate(str: string, max: number): string {
  return str.length > max ? str.slice(0, max) + "…" : str;
}

function channelIcon(type: ChannelType): React.ReactNode {
  if (type === "global") return <MdPublic size={18} />;
  if (type === "team") return <MdPeople size={18} />;
  if (type === "emergency") return <MdCrisisAlert size={18} />;
  return <MdPerson size={18} />;
}

// ---------------------------------------------------------------------------
// VideoCallModal
// ---------------------------------------------------------------------------

interface VideoCallModalProps {
  roomId: string;
  roomTitle: string;
  onClose: () => void;
}

function VideoCallModal({ roomId, roomTitle, onClose }: VideoCallModalProps) {
  const { user } = useAuthStore();
  const [peers, setPeers] = useState<Map<string, PeerInfo>>(new Map());
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [muted, setMuted] = useState(false);
  const [cameraOff, setCameraOff] = useState(false);
  const [participantCount, setParticipantCount] = useState(1);
  const [callStatus, setCallStatus] = useState<"connecting" | "connected" | "alone">("connecting");

  // Refs avoid stale closures in async WS message handlers
  const localStreamRef = useRef<MediaStream | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const localVideoRef = useRef<HTMLVideoElement>(null);
  const pcsRef = useRef<Map<string, RTCPeerConnection>>(new Map());
  const remoteVideoRefs = useRef<Map<string, HTMLVideoElement>>(new Map());
  // ICE candidates queued while waiting for remote description to be set
  const iceCandidateQueues = useRef<Map<string, RTCIceCandidateInit[]>>(new Map());
  const mutedRef = useRef(false);
  const cameraOffRef = useRef(false);

  const token = localStorage.getItem("access_token");
  const apiBase = import.meta.env.VITE_API_URL || "http://localhost:1104";
  const wsUrl = apiBase.replace(/^http/, "ws");

  useEffect(() => {
    if (!token) return;
    let cleanedUp = false;

    // createPC defined inside useEffect so it always uses current refs, no stale closure
    function createPC(peerId: string, peerName: string): RTCPeerConnection {
      pcsRef.current.get(peerId)?.close();
      const pc = new RTCPeerConnection({
        iceServers: [
          { urls: "stun:stun.l.google.com:19302" },
          { urls: "stun:stun1.l.google.com:19302" },
        ],
      });

      // Add local tracks from ref (always current, no stale closure)
      if (localStreamRef.current) {
        localStreamRef.current.getTracks().forEach((track) =>
          pc.addTrack(track, localStreamRef.current!)
        );
      }

      pc.onicecandidate = (event) => {
        if (event.candidate && wsRef.current?.readyState === WebSocket.OPEN) {
          wsRef.current.send(JSON.stringify({
            type: "ice_candidate",
            candidate: event.candidate.toJSON(),
            target: peerId,
          }));
        }
      };

      pc.ontrack = (event) => {
        if (cleanedUp) return;
        const [remoteStream] = event.streams;
        setPeers((prev) => {
          const next = new Map(prev);
          const existing = next.get(peerId);
          next.set(peerId, {
            name: existing?.name || peerName,
            stream: remoteStream,
            muted: existing?.muted ?? false,
            cameraOff: existing?.cameraOff ?? false,
          });
          return next;
        });
        const videoEl = remoteVideoRefs.current.get(peerId);
        if (videoEl) videoEl.srcObject = remoteStream;
      };

      pc.onconnectionstatechange = () => {
        if (pc.connectionState === "failed") pc.restartIce();
      };

      pcsRef.current.set(peerId, pc);
      return pc;
    }

    async function flushIceCandidates(peerId: string, pc: RTCPeerConnection) {
      const queue = iceCandidateQueues.current.get(peerId) || [];
      iceCandidateQueues.current.delete(peerId);
      for (const cand of queue) {
        try { await pc.addIceCandidate(new RTCIceCandidate(cand)); } catch {}
      }
    }

    async function init() {
      // Get media before opening WS so tracks are ready when offers arrive
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
        if (cleanedUp) { stream.getTracks().forEach((t) => t.stop()); return; }
        localStreamRef.current = stream;
        setLocalStream(stream);
        if (localVideoRef.current) localVideoRef.current.srcObject = stream;
      } catch {
        // No camera/mic — proceed audio/video-less
      }

      if (cleanedUp) return;

      const ws = new WebSocket(`${wsUrl}/ws/video/${encodeURIComponent(roomId)}?token=${token}`);
      wsRef.current = ws;

      ws.onopen = () => { if (!cleanedUp) setCallStatus("alone"); };

      ws.onmessage = async (e: MessageEvent) => {
        if (cleanedUp) return;
        let msg: Record<string, unknown>;
        try { msg = JSON.parse(e.data as string) as Record<string, unknown>; }
        catch { return; }

        const msgType = msg.type as string;

        if (msgType === "room_state") {
          const serverPeers = (msg.peers as Array<{ user_id: string; name: string }>) || [];
          const count = (msg.participant_count as number) ?? (serverPeers.length + 1);
          setParticipantCount(count);

          if (serverPeers.length === 0) {
            setCallStatus("alone");
            return;
          }
          setCallStatus("connected");

          // Pre-populate peer list so UI shows names before streams arrive
          setPeers((prev) => {
            const next = new Map(prev);
            for (const p of serverPeers) {
              if (!next.has(p.user_id))
                next.set(p.user_id, { name: p.name, stream: null, muted: false, cameraOff: false });
            }
            return next;
          });

          // New joiner sends offers to all existing peers
          for (const peer of serverPeers) {
            try {
              const pc = createPC(peer.user_id, peer.name);
              const offer = await pc.createOffer();
              await pc.setLocalDescription(offer);
              ws.send(JSON.stringify({ type: "offer", sdp: offer, target: peer.user_id }));
            } catch {}
          }

        } else if (msgType === "peer_joined") {
          const peerId = msg.user_id as string;
          const peerName = msg.name as string;
          const count = msg.participant_count as number;
          if (count) setParticipantCount(count);
          setCallStatus("connected");
          setPeers((prev) => {
            const next = new Map(prev);
            if (!next.has(peerId))
              next.set(peerId, { name: peerName, stream: null, muted: false, cameraOff: false });
            return next;
          });

        } else if (msgType === "peer_left") {
          const peerId = msg.user_id as string;
          const count = msg.participant_count as number;
          pcsRef.current.get(peerId)?.close();
          pcsRef.current.delete(peerId);
          iceCandidateQueues.current.delete(peerId);
          if (count) setParticipantCount(count);
          setPeers((prev) => {
            const next = new Map(prev);
            next.delete(peerId);
            if (next.size === 0) setCallStatus("alone");
            return next;
          });

        } else if (msgType === "offer") {
          const fromId = msg.from as string;
          const fromName = (msg.name as string) || fromId.substring(0, 8);
          setCallStatus("connected");
          setPeers((prev) => {
            const next = new Map(prev);
            if (!next.has(fromId))
              next.set(fromId, { name: fromName, stream: null, muted: false, cameraOff: false });
            return next;
          });
          try {
            let pc = pcsRef.current.get(fromId);
            if (!pc) pc = createPC(fromId, fromName);
            await pc.setRemoteDescription(new RTCSessionDescription(msg.sdp as RTCSessionDescriptionInit));
            await flushIceCandidates(fromId, pc);
            const answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            ws.send(JSON.stringify({ type: "answer", sdp: answer, target: fromId }));
          } catch {}

        } else if (msgType === "answer") {
          const fromId = msg.from as string;
          const pc = pcsRef.current.get(fromId);
          if (pc) {
            try {
              await pc.setRemoteDescription(new RTCSessionDescription(msg.sdp as RTCSessionDescriptionInit));
              await flushIceCandidates(fromId, pc);
            } catch {}
          }

        } else if (msgType === "ice_candidate") {
          const fromId = msg.from as string;
          const candidate = msg.candidate as RTCIceCandidateInit;
          const pc = pcsRef.current.get(fromId);
          if (pc && pc.remoteDescription) {
            try { await pc.addIceCandidate(new RTCIceCandidate(candidate)); } catch {}
          } else {
            // Queue until remote description is set
            const queue = iceCandidateQueues.current.get(fromId) || [];
            queue.push(candidate);
            iceCandidateQueues.current.set(fromId, queue);
          }

        } else if (msgType === "broadcast") {
          const subtype = msg.subtype as string;
          const fromId = msg.from as string;
          if (subtype === "peer_state_update") {
            setPeers((prev) => {
              const next = new Map(prev);
              const peer = next.get(fromId);
              if (peer)
                next.set(fromId, { ...peer, muted: msg.muted as boolean, cameraOff: msg.camera_off as boolean });
              return next;
            });
          }
        }
      };

      ws.onclose = () => { /* reconnect could go here */ };
    }

    init().catch(() => {});

    return () => {
      cleanedUp = true;
      localStreamRef.current?.getTracks().forEach((t) => t.stop());
      localStreamRef.current = null;
      pcsRef.current.forEach((pc) => pc.close());
      pcsRef.current.clear();
      wsRef.current?.close();
      wsRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roomId, token, wsUrl]);

  // Sync local stream to video element when it becomes available
  useEffect(() => {
    if (localStream && localVideoRef.current) localVideoRef.current.srcObject = localStream;
  }, [localStream]);

  // Sync remote streams whenever peer state updates
  useEffect(() => {
    peers.forEach((peerInfo, peerId) => {
      const videoEl = remoteVideoRefs.current.get(peerId);
      if (videoEl && peerInfo.stream) videoEl.srcObject = peerInfo.stream;
    });
  }, [peers]);

  const broadcastState = (isMuted: boolean, isCamOff: boolean) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({
        type: "broadcast",
        subtype: "peer_state_update",
        muted: isMuted,
        camera_off: isCamOff,
      }));
    }
  };

  const toggleMute = () => {
    if (localStreamRef.current) {
      const newMuted = !mutedRef.current;
      mutedRef.current = newMuted;
      localStreamRef.current.getAudioTracks().forEach((t) => { t.enabled = !newMuted; });
      setMuted(newMuted);
      broadcastState(newMuted, cameraOffRef.current);
    }
  };

  const toggleCamera = () => {
    if (localStreamRef.current) {
      const newCamOff = !cameraOffRef.current;
      cameraOffRef.current = newCamOff;
      localStreamRef.current.getVideoTracks().forEach((t) => { t.enabled = !newCamOff; });
      setCameraOff(newCamOff);
      broadcastState(mutedRef.current, newCamOff);
    }
  };

  const handleEndCall = () => {
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    pcsRef.current.forEach((pc) => pc.close());
    pcsRef.current.clear();
    wsRef.current?.close();
    onClose();
  };

  const peerEntries = Array.from(peers.entries());

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 9999,
        background: "rgba(0,0,0,0.95)",
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Top bar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "12px 20px",
          background: "#0F172A",
          borderBottom: "1px solid #1F2937",
          flexShrink: 0,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <MdVideoCall size={22} color="#22c55e" />
          <span style={{ color: "#fff", fontWeight: 600, fontSize: 15 }}>{roomTitle}</span>
          {/* Live participant count */}
          <span
            style={{
              background: "#1F2937",
              color: callStatus === "connected" ? "#22c55e" : "#6b7280",
              borderRadius: 6,
              padding: "2px 10px",
              fontSize: 12,
              display: "flex",
              alignItems: "center",
              gap: 4,
            }}
          >
            <MdPeople size={13} />
            {participantCount} {participantCount === 1 ? "participant" : "participants"}
          </span>
        </div>
        <button
          onClick={handleEndCall}
          style={{
            background: "#dc2626",
            color: "#fff",
            border: "none",
            borderRadius: 8,
            padding: "6px 14px",
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            gap: 6,
            fontSize: 13,
          }}
        >
          <MdCallEnd size={16} />
          Leave
        </button>
      </div>

      {/* Video grid */}
      <div
        style={{
          flex: 1,
          position: "relative",
          overflow: "hidden",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexWrap: "wrap",
          gap: 8,
          padding: 16,
        }}
      >
        {callStatus === "connecting" && (
          <div style={{ textAlign: "center", color: "#9ca3af" }}>
            <div
              style={{
                width: 40,
                height: 40,
                border: "3px solid #22c55e",
                borderTopColor: "transparent",
                borderRadius: "50%",
                animation: "spin 1s linear infinite",
                margin: "0 auto 12px",
              }}
            />
            <p style={{ fontSize: 15 }}>Connecting…</p>
          </div>
        )}

        {callStatus === "alone" && (
          <div style={{ textAlign: "center", color: "#6b7280" }}>
            <MdVideoCall size={60} style={{ marginBottom: 12, opacity: 0.4 }} />
            <p style={{ fontSize: 16, marginBottom: 6 }}>Waiting for others to join…</p>
            <p style={{ fontSize: 12, fontFamily: "monospace", color: "#4b5563" }}>
              Room: {roomId}
            </p>
          </div>
        )}

        {peerEntries.map(([peerId, info]) => (
          <div
            key={peerId}
            style={{
              flex: "1 1 300px",
              maxWidth: 480,
              background: "#0F172A",
              borderRadius: 12,
              overflow: "hidden",
              position: "relative",
              aspectRatio: "16/9",
              border: "1px solid #1F2937",
            }}
          >
            {info.stream && !info.cameraOff ? (
              <video
                ref={(el) => {
                  if (el) {
                    remoteVideoRefs.current.set(peerId, el);
                    if (info.stream) el.srcObject = info.stream;
                  }
                }}
                autoPlay
                playsInline
                style={{ width: "100%", height: "100%", objectFit: "cover" }}
              />
            ) : (
              <div
                style={{
                  width: "100%",
                  height: "100%",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  flexDirection: "column",
                  color: "#6b7280",
                }}
              >
                <MdPerson size={48} style={{ opacity: 0.4 }} />
                <span style={{ fontSize: 12, marginTop: 6 }}>
                  {info.stream ? "Camera Off" : "Connecting…"}
                </span>
              </div>
            )}
            {/* Name + state indicators */}
            <div style={{ position: "absolute", bottom: 8, left: 8, display: "flex", gap: 4, alignItems: "center" }}>
              <span
                style={{
                  background: "rgba(0,0,0,0.65)",
                  color: "#fff",
                  borderRadius: 6,
                  padding: "2px 8px",
                  fontSize: 12,
                }}
              >
                {info.name || peerId.substring(0, 8)}
              </span>
              {info.muted && (
                <span style={{ background: "rgba(220,38,38,0.75)", borderRadius: 6, padding: "2px 5px", display: "flex" }}>
                  <MdMicOff size={12} color="#fff" />
                </span>
              )}
              {info.cameraOff && (
                <span style={{ background: "rgba(220,38,38,0.75)", borderRadius: 6, padding: "2px 5px", display: "flex" }}>
                  <MdVideocamOff size={12} color="#fff" />
                </span>
              )}
            </div>
          </div>
        ))}

        {/* Local video PiP */}
        <div
          style={{
            position: "absolute",
            bottom: 80,
            right: 16,
            width: 160,
            height: 120,
            background: "#0F172A",
            borderRadius: 10,
            overflow: "hidden",
            border: "2px solid #22c55e",
            boxShadow: "0 4px 20px rgba(0,0,0,0.5)",
          }}
        >
          {!cameraOff ? (
            <video
              ref={localVideoRef}
              autoPlay
              playsInline
              muted
              style={{ width: "100%", height: "100%", objectFit: "cover", transform: "scaleX(-1)" }}
            />
          ) : (
            <div
              style={{
                width: "100%",
                height: "100%",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "#6b7280",
              }}
            >
              <MdVideocamOff size={32} style={{ opacity: 0.5 }} />
            </div>
          )}
          <div
            style={{
              position: "absolute",
              bottom: 4,
              left: 4,
              background: "rgba(0,0,0,0.6)",
              color: "#fff",
              borderRadius: 4,
              padding: "1px 6px",
              fontSize: 10,
              display: "flex",
              alignItems: "center",
              gap: 3,
            }}
          >
            {user?.full_name || "You"}
            {muted && <MdMicOff size={10} />}
          </div>
        </div>
      </div>

      {/* Bottom controls */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 16,
          padding: "16px 20px",
          background: "#0F172A",
          borderTop: "1px solid #1F2937",
          flexShrink: 0,
        }}
      >
        <button
          onClick={toggleMute}
          title={muted ? "Unmute" : "Mute"}
          style={{
            background: muted ? "#dc2626" : "#1F2937",
            color: "#fff",
            border: "none",
            borderRadius: "50%",
            width: 48,
            height: 48,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            cursor: "pointer",
            transition: "background 0.15s",
          }}
        >
          {muted ? <MdMicOff size={22} /> : <MdMic size={22} />}
        </button>

        <button
          onClick={toggleCamera}
          title={cameraOff ? "Camera on" : "Camera off"}
          style={{
            background: cameraOff ? "#dc2626" : "#1F2937",
            color: "#fff",
            border: "none",
            borderRadius: "50%",
            width: 48,
            height: 48,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            cursor: "pointer",
            transition: "background 0.15s",
          }}
        >
          {cameraOff ? <MdVideocamOff size={22} /> : <MdVideocam size={22} />}
        </button>

        <button
          onClick={handleEndCall}
          title="Leave call"
          style={{
            background: "#dc2626",
            color: "#fff",
            border: "none",
            borderRadius: "50%",
            width: 56,
            height: 56,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            cursor: "pointer",
          }}
        >
          <MdCallEnd size={26} />
        </button>
      </div>

      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );
}

// ---------------------------------------------------------------------------
// NewDMPanel
// ---------------------------------------------------------------------------

interface NewDMPanelProps {
  teams: Team[];
  isCoordinator: boolean;
  onSelect: (userId: string, name: string) => void;
  onClose: () => void;
}

type DMUser = { id: string; name: string; subtitle?: string; avatar_url?: string };

function NewDMPanel({ teams, isCoordinator, onSelect, onClose }: NewDMPanelProps) {
  const [users, setUsers] = useState<DMUser[]>([]);
  const [loading, setLoading] = useState(true);
  const { user } = useAuthStore();

  useEffect(() => {
    if (isCoordinator) {
      // Coordinator: fetch every user in the system
      userApi
        .list({ page_size: 200 })
        .then(({ data }) => {
          const all = ((data as { users?: unknown[] }).users ?? (Array.isArray(data) ? data : [])) as {
            id: string; full_name: string; username: string; role: string; avatar_url?: string;
          }[];
          const roleLabel: Record<string, string> = {
            operations_coordinator: "Coordinator",
            planning_officer: "Planning Officer",
            team_leader: "Team Leader",
            field_user: "Field User",
          };
          setUsers(
            all
              .filter((u) => u.id !== user?.id)
              .map((u) => ({
                id: u.id,
                name: u.full_name || u.username,
                subtitle: roleLabel[u.role] ?? u.role,
                avatar_url: u.avatar_url,
              }))
          );
        })
        .catch(() => setUsers([]))
        .finally(() => setLoading(false));
    } else {
      // Non-coordinator: fetch members of own teams
      const promises = teams.map((t) => teamApi.getMembers(t.id));
      Promise.all(promises)
        .then((results) => {
          const all: TeamMember[] = results.flatMap((r) =>
            Array.isArray(r.data) ? (r.data as TeamMember[]) : []
          );
          const seen = new Set<string>();
          const unique = all.filter((m) => {
            if (m.user_id === user?.id) return false;
            if (seen.has(m.user_id)) return false;
            seen.add(m.user_id);
            return true;
          });
          setUsers(
            unique.map((m) => ({
              id: m.user_id,
              name: m.user?.full_name || m.user?.username || m.user_id.substring(0, 8),
              subtitle: m.role_in_team,
              avatar_url: m.user?.avatar_url,
            }))
          );
        })
        .catch(() => setUsers([]))
        .finally(() => setLoading(false));
    }
  }, [teams, isCoordinator, user?.id]);

  const apiBase = import.meta.env.VITE_API_URL || "http://localhost:1104";

  return (
    <div
      style={{
        position: "absolute",
        bottom: 60,
        left: 8,
        width: 240,
        background: "#0F172A",
        border: "1px solid #1F2937",
        borderRadius: 10,
        boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
        zIndex: 100,
        overflow: "hidden",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "10px 12px",
          borderBottom: "1px solid #1F2937",
        }}
      >
        <span style={{ color: "#fff", fontWeight: 600, fontSize: 13 }}>
          {isCoordinator ? "Message Anyone" : "Start a DM"}
        </span>
        <button
          onClick={onClose}
          style={{ background: "none", border: "none", color: "#9ca3af", cursor: "pointer", padding: 0, display: "flex" }}
        >
          <MdClose size={16} />
        </button>
      </div>
      <div style={{ maxHeight: 280, overflowY: "auto" }}>
        {loading ? (
          <div style={{ padding: "16px", textAlign: "center", color: "#6b7280", fontSize: 12 }}>Loading…</div>
        ) : users.length === 0 ? (
          <div style={{ padding: "16px", textAlign: "center", color: "#6b7280", fontSize: 12 }}>No users found</div>
        ) : (
          users.map((u) => (
            <button
              key={u.id}
              onClick={() => onSelect(u.id, u.name)}
              style={{
                width: "100%",
                display: "flex",
                alignItems: "center",
                gap: 8,
                padding: "8px 12px",
                background: "none",
                border: "none",
                cursor: "pointer",
                color: "#e5e7eb",
                fontSize: 13,
                textAlign: "left",
                transition: "background 0.1s",
              }}
              onMouseEnter={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "#1F2937")}
              onMouseLeave={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "none")}
            >
              {u.avatar_url ? (
                <img
                  src={u.avatar_url.startsWith("http") ? u.avatar_url : `${apiBase}${u.avatar_url}`}
                  alt=""
                  style={{ width: 28, height: 28, borderRadius: "50%", objectFit: "cover", flexShrink: 0 }}
                  onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = "none"; }}
                />
              ) : (
                <div
                  style={{
                    width: 28, height: 28, borderRadius: "50%", background: "#374151",
                    display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
                  }}
                >
                  <span style={{ color: "#9ca3af", fontSize: 11, fontWeight: 600 }}>
                    {u.name[0]?.toUpperCase() ?? "?"}
                  </span>
                </div>
              )}
              <div style={{ minWidth: 0 }}>
                <p style={{ margin: 0, fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {u.name}
                </p>
                {u.subtitle && (
                  <p style={{ margin: 0, fontSize: 11, color: "#6b7280" }}>{u.subtitle}</p>
                )}
              </div>
            </button>
          ))
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main Comms component
// ---------------------------------------------------------------------------

export default function Comms() {
  const { user } = useAuthStore();
  const location = useLocation();
  const dmState = location.state as { dmUserId?: string; dmUserName?: string } | null;

  const isCoordinator = user?.role === "operations_coordinator";

  const globalChannel: Channel = {
    id: "global",
    label: "Global",
    type: "global",
    icon: <MdPublic size={16} />,
  };

  const emergencyChannel: Channel = {
    id: "emergency",
    label: "Emergency",
    type: "emergency",
    icon: <MdCrisisAlert size={16} />,
  };

  const [channels, setChannels] = useState<Channel[]>(
    isCoordinator ? [globalChannel, emergencyChannel] : [globalChannel]
  );
  const [teams, setTeams] = useState<Team[]>([]);
  const [channelMeta, setChannelMeta] = useState<Map<string, ChannelMeta>>(new Map());
  const [unreadCounts, setUnreadCounts] = useState<Map<string, number>>(new Map());
  const [active, setActive] = useState<Channel>(globalChannel);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [showDMPanel, setShowDMPanel] = useState(false);
  const [videoCallRoomId, setVideoCallRoomId] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [replyTo, setReplyTo] = useState<Message | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);

  const bottomRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // ---------------------------------------------------------------------------
  // Boot: fetch teams + channel meta
  // ---------------------------------------------------------------------------

  useEffect(() => {
    // Coordinator sees all teams; others only see their own
    teamApi
      .list(!isCoordinator)
      .then(({ data }) => {
        const t = data as Team[];
        setTeams(t);
        const teamChannels: Channel[] = t.map((tm: Team) => ({
          id: `team:${tm.id}`,
          label: tm.name,
          type: "team" as const,
          icon: <MdPeople size={16} />,
        }));
        setChannels((prev) => {
          const nonTeam = prev.filter((c) => c.type !== "team");
          return [...nonTeam, ...teamChannels];
        });
      })
      .catch(() => {});
  }, [isCoordinator]);

  // Fetch channel metadata
  useEffect(() => {
    api
      .get("/messages/channels-meta")
      .then(({ data }) => {
        const arr = data as ChannelMeta[];
        const map = new Map<string, ChannelMeta>();
        const unread = new Map<string, number>();
        arr.forEach((m) => {
          const key = m.type === "global" ? "global" : `${m.type}:${m.id}`;
          map.set(key, m);
          if (m.unread_count > 0) unread.set(key, m.unread_count);
        });
        setChannelMeta(map);
        setUnreadCounts(unread);
      })
      .catch(() => {
        // Endpoint doesn't exist yet — graceful fallback
      });
  }, []);

  // Auto-open DM when navigating from map
  useEffect(() => {
    if (!dmState?.dmUserId) return;
    const dmChannel: Channel = {
      id: `dm:${dmState.dmUserId}`,
      label: dmState.dmUserName ?? "Direct Message",
      type: "dm",
      icon: <MdPerson size={16} />,
    };
    setChannels((prev) => {
      const exists = prev.find((c) => c.id === dmChannel.id);
      return exists ? prev : [...prev, dmChannel];
    });
    setActive(dmChannel);
  }, [dmState?.dmUserId]);

  // ---------------------------------------------------------------------------
  // Channel switching
  // ---------------------------------------------------------------------------

  const switchChannel = (ch: Channel) => {
    setActive(ch);
    // Mark as read
    setUnreadCounts((prev) => {
      const next = new Map(prev);
      next.delete(ch.id);
      return next;
    });
    setReplyTo(null);
  };

  // ---------------------------------------------------------------------------
  // Load messages + WebSocket setup
  // ---------------------------------------------------------------------------

  useEffect(() => {
    loadMessages();
    setupWS();
    return () => wsRef.current?.close();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active.id]);

  const loadMessages = () => {
    setLoading(true);
    const p =
      active.type === "global"
        ? messageApi.getGlobal()
        : active.type === "emergency"
        ? messageApi.getEmergency()
        : active.type === "team"
        ? messageApi.getTeam(active.id.replace("team:", ""))
        : messageApi.getDM(active.id.replace("dm:", ""));
    p.then(({ data }) => setMessages(Array.isArray(data) ? (data as Message[]) : []))
      .catch(() => setMessages([]))
      .finally(() => setLoading(false));
  };

  const setupWS = () => {
    wsRef.current?.close();
    const token = localStorage.getItem("access_token");
    if (!token) return;
    const apiBase = import.meta.env.VITE_API_URL || "http://localhost:1104";
    const wsUrl = apiBase.replace(/^http/, "ws");
    const channel = active.id === "global" ? "global" : active.id;
    const ws = new WebSocket(
      `${wsUrl}/ws/messages/${encodeURIComponent(channel)}?token=${token}`
    );
    wsRef.current = ws;
    ws.onmessage = (e) => {
      let msg: { type: string; message: Message };
      try {
        msg = JSON.parse(e.data as string) as { type: string; message: Message };
      } catch {
        return;
      }
      if (msg.type === "new_message") {
        setMessages((prev) => [...prev, msg.message]);
        setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }), 50);
      }
    };
  };

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // ---------------------------------------------------------------------------
  // Send message
  // ---------------------------------------------------------------------------

  const activeChannel = (): string => {
    if (active.id === "global") return "global";
    if (active.id === "emergency") return "emergency";
    if (active.type === "team") return `team:${active.id.replace("team:", "")}`;
    return `dm:${active.id.replace("dm:", "")}`;
  };

  const sendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim()) return;
    const text = input.trim();
    setInput("");
    setReplyTo(null);
    try {
      await messageApi.send({
        content: text,
        channel: activeChannel(),
        ...(replyTo ? { reply_to_id: replyTo.id } : {}),
      });
    } catch {}
  };

  // ---------------------------------------------------------------------------
  // Video call
  // ---------------------------------------------------------------------------

  const startVideoCall = async () => {
    const roomId = `${active.id}-${Date.now()}`;
    setVideoCallRoomId(roomId);
    try {
      await messageApi.send({
        content: `📹 Video call started. Join: ${roomId}`,
        channel: activeChannel(),
        message_type: "system",
      });
    } catch {}
  };

  // ---------------------------------------------------------------------------
  // Image attachment
  // ---------------------------------------------------------------------------

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const { data } = await evidenceApi.upload(fd);
      const url = (data as { url?: string; file_url?: string; path?: string }).url
        ?? (data as { url?: string; file_url?: string; path?: string }).file_url
        ?? (data as { url?: string; file_url?: string; path?: string }).path
        ?? "";
      if (url) {
        await messageApi.send({ content: `[IMAGE] ${url}`, channel: activeChannel(), message_type: "image" });
      }
    } catch {}
    setUploading(false);
    // Reset input
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  // ---------------------------------------------------------------------------
  // DM panel
  // ---------------------------------------------------------------------------

  const openDM = (userId: string, name: string) => {
    const dmChannel: Channel = {
      id: `dm:${userId}`,
      label: name,
      type: "dm",
      icon: <MdPerson size={16} />,
    };
    setChannels((prev) => {
      const exists = prev.find((c) => c.id === dmChannel.id);
      return exists ? prev : [...prev, dmChannel];
    });
    switchChannel(dmChannel);
    setShowDMPanel(false);
  };

  // ---------------------------------------------------------------------------
  // Render helpers
  // ---------------------------------------------------------------------------

  const renderMessageContent = (msg: Message) => {
    const { content } = msg;

    // Video call link
    if (content.startsWith("📹 Video call started. Join:")) {
      const roomId = content.replace("📹 Video call started. Join:", "").trim();
      return (
        <div>
          <p style={{ margin: 0, marginBottom: 6 }}>{content}</p>
          <button
            onClick={() => setVideoCallRoomId(roomId)}
            style={{
              background: "#16a34a",
              color: "#fff",
              border: "none",
              borderRadius: 6,
              padding: "4px 10px",
              fontSize: 12,
              cursor: "pointer",
              display: "flex",
              alignItems: "center",
              gap: 4,
            }}
          >
            <MdVideocam size={14} />
            Join Call
          </button>
        </div>
      );
    }

    // Image message
    if (content.startsWith("[IMAGE] ")) {
      const url = content.replace("[IMAGE] ", "").trim();
      const apiBase = import.meta.env.VITE_API_URL || "http://localhost:1104";
      const fullUrl = url.startsWith("http") ? url : `${apiBase}${url}`;
      return (
        <img
          src={fullUrl}
          alt="Attached"
          style={{ maxHeight: 200, borderRadius: 8, cursor: "pointer", display: "block" }}
          onClick={() => setImagePreview(fullUrl)}
          onError={(e) => {
            (e.currentTarget as HTMLImageElement).style.display = "none";
          }}
        />
      );
    }

    return <span>{content}</span>;
  };

  // Group channels by type for sidebar
  const globalChannels = channels.filter((c) => c.type === "global" || c.type === "emergency");
  const teamChannels = channels.filter((c) => c.type === "team");
  const dmChannels = channels.filter((c) => c.type === "dm");

  const renderChannelItem = (ch: Channel) => {
    const meta = channelMeta.get(ch.id);
    const unread = unreadCounts.get(ch.id) ?? 0;
    const isActive = active.id === ch.id;

    return (
      <button
        key={ch.id}
        onClick={() => switchChannel(ch)}
        style={{
          width: "100%",
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "8px 10px",
          borderRadius: 8,
          border: "none",
          cursor: "pointer",
          textAlign: "left",
          background: isActive ? "#15803d" : "transparent",
          transition: "background 0.1s",
        }}
        onMouseEnter={(e) => {
          if (!isActive)
            (e.currentTarget as HTMLButtonElement).style.background = "#1F2937";
        }}
        onMouseLeave={(e) => {
          if (!isActive)
            (e.currentTarget as HTMLButtonElement).style.background = "transparent";
        }}
      >
        {/* Avatar/icon area */}
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: "50%",
            background: isActive
              ? "rgba(255,255,255,0.15)"
              : ch.type === "emergency"
              ? "rgba(220,38,38,0.15)"
              : "#1F2937",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexShrink: 0,
            color: isActive ? "#fff" : ch.type === "emergency" ? "#ef4444" : "#9ca3af",
          }}
        >
          {ch.icon}
        </div>

        {/* Text */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <span
              style={{
                color: isActive
                  ? "#fff"
                  : ch.type === "emergency"
                  ? "#f87171"
                  : unread > 0
                  ? "#f9fafb"
                  : "#d1d5db",
                fontWeight: ch.type === "emergency" || unread > 0 ? 700 : 500,
                fontSize: 13,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {ch.label}
            </span>
            {meta?.last_message && (
              <span style={{ color: "#6b7280", fontSize: 10, flexShrink: 0, marginLeft: 4 }}>
                {formatTimestamp(meta.last_message.sent_at)}
              </span>
            )}
          </div>
          {meta?.last_message ? (
            <p
              style={{
                margin: 0,
                fontSize: 11,
                color: unread > 0 ? "#9ca3af" : "#6b7280",
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {truncate(`${meta.last_message.sender_name}: ${meta.last_message.content}`, 35)}
            </p>
          ) : null}
        </div>

        {/* Unread badge */}
        {unread > 0 && (
          <div
            style={{
              background: "#16a34a",
              color: "#fff",
              borderRadius: "50%",
              minWidth: 18,
              height: 18,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 10,
              fontWeight: 700,
              padding: "0 4px",
              flexShrink: 0,
            }}
          >
            {unread > 99 ? "99+" : unread}
          </div>
        )}
      </button>
    );
  };

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div style={{ display: "flex", height: "100%", background: "#030712" }}>
      {/* ── Sidebar ── */}
      <div
        style={{
          width: 260,
          borderRight: "1px solid #1F2937",
          display: "flex",
          flexDirection: "column",
          background: "#0F172A",
          flexShrink: 0,
          position: "relative",
        }}
      >
        <div
          style={{
            padding: "14px 14px 10px",
            borderBottom: "1px solid #1F2937",
          }}
        >
          <p style={{ color: "#6b7280", fontSize: 10, textTransform: "uppercase", letterSpacing: "0.08em", fontWeight: 600, margin: 0 }}>
            Communications
          </p>
        </div>

        <div style={{ flex: 1, overflowY: "auto", padding: "8px 6px" }}>
          {/* Global channels */}
          {globalChannels.length > 0 && (
            <div style={{ marginBottom: 8 }}>
              <p style={{ color: "#4b5563", fontSize: 10, textTransform: "uppercase", padding: "4px 10px", margin: "0 0 2px", letterSpacing: "0.06em" }}>
                General
              </p>
              {globalChannels.map(renderChannelItem)}
            </div>
          )}

          {/* Team channels */}
          {teamChannels.length > 0 && (
            <div style={{ marginBottom: 8 }}>
              <p style={{ color: "#4b5563", fontSize: 10, textTransform: "uppercase", padding: "4px 10px", margin: "0 0 2px", letterSpacing: "0.06em" }}>
                Teams
              </p>
              {teamChannels.map(renderChannelItem)}
            </div>
          )}

          {/* DM channels */}
          {dmChannels.length > 0 && (
            <div style={{ marginBottom: 8 }}>
              <p style={{ color: "#4b5563", fontSize: 10, textTransform: "uppercase", padding: "4px 10px", margin: "0 0 2px", letterSpacing: "0.06em" }}>
                Direct Messages
              </p>
              {dmChannels.map(renderChannelItem)}
            </div>
          )}
        </div>

        {/* New DM button */}
        <div style={{ padding: "8px 10px", borderTop: "1px solid #1F2937", position: "relative" }}>
          <button
            onClick={() => setShowDMPanel((v) => !v)}
            style={{
              width: "100%",
              display: "flex",
              alignItems: "center",
              gap: 8,
              padding: "8px 10px",
              background: "#1F2937",
              border: "none",
              borderRadius: 8,
              color: "#9ca3af",
              cursor: "pointer",
              fontSize: 13,
              transition: "background 0.1s",
            }}
          >
            <MdAdd size={16} />
            New Direct Message
          </button>

          {showDMPanel && (
            <NewDMPanel
              teams={teams}
              isCoordinator={isCoordinator}
              onSelect={openDM}
              onClose={() => setShowDMPanel(false)}
            />
          )}
        </div>
      </div>

      {/* ── Chat area ── */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", minWidth: 0, background: "#030712" }}>
        {/* Header */}
        <div
          style={{
            height: 52,
            borderBottom: "1px solid #1F2937",
            display: "flex",
            alignItems: "center",
            padding: "0 16px",
            gap: 10,
            background: "#0F172A",
            flexShrink: 0,
          }}
        >
          <div
            style={{
              width: 32,
              height: 32,
              borderRadius: "50%",
              background: "#1F2937",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "#9ca3af",
            }}
          >
            {active.icon}
          </div>
          <div style={{ flex: 1 }}>
            <span style={{ color: "#fff", fontWeight: 600, fontSize: 14 }}>{active.label}</span>
            <p style={{ margin: 0, color: "#6b7280", fontSize: 11 }}>
              {active.type === "global"
                ? "All team members"
                : active.type === "team"
                ? "Team channel"
                : active.type === "dm"
                ? "Direct message"
                : "Channel"}
            </p>
          </div>

        </div>

        {/* Messages */}
        <div style={{ flex: 1, overflowY: "auto", padding: "16px" }}>
          {loading ? (
            <div style={{ display: "flex", justifyContent: "center", paddingTop: 32 }}>
              <div
                style={{
                  width: 24,
                  height: 24,
                  border: "2px solid #22c55e",
                  borderTopColor: "transparent",
                  borderRadius: "50%",
                  animation: "spin 1s linear infinite",
                }}
              />
            </div>
          ) : messages.length === 0 ? (
            <div style={{ textAlign: "center", paddingTop: 64 }}>
              <MdPublic size={40} color="#374151" style={{ margin: "0 auto 8px", display: "block" }} />
              <p style={{ color: "#6b7280", fontSize: 14 }}>No messages yet. Start the conversation!</p>
            </div>
          ) : (
            messages.map((msg, i) => {
              const isMe = msg.sender_id === user?.id;
              const prevMsg = messages[i - 1];
              const showDateSep = !prevMsg || !isSameDay(prevMsg.sent_at, msg.sent_at);
              const showHeader = !prevMsg || prevMsg.sender_id !== msg.sender_id || showDateSep;
              const isImageMsg = msg.content.startsWith("[IMAGE] ");
              const isVideoCall = msg.content.startsWith("📹 Video call started. Join:");

              return (
                <div key={msg.id}>
                  {/* Date separator */}
                  {showDateSep && (
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 12,
                        margin: "16px 0 12px",
                      }}
                    >
                      <div style={{ flex: 1, height: 1, background: "#1F2937" }} />
                      <span style={{ color: "#4b5563", fontSize: 11, whiteSpace: "nowrap" }}>
                        {formatDateSeparator(msg.sent_at)}
                      </span>
                      <div style={{ flex: 1, height: 1, background: "#1F2937" }} />
                    </div>
                  )}

                  <div
                    style={{
                      display: "flex",
                      justifyContent: isMe ? "flex-end" : "flex-start",
                      marginBottom: 2,
                    }}
                  >
                    <div
                      style={{
                        maxWidth: 480,
                        display: "flex",
                        flexDirection: "column",
                        alignItems: isMe ? "flex-end" : "flex-start",
                      }}
                    >
                      {/* Sender name + avatar */}
                      {showHeader && !isMe && (
                        <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 4, marginLeft: 2 }}>
                          {/* Avatar */}
                          {msg.sender?.avatar_url ? (
                            <img
                              src={msg.sender.avatar_url.startsWith("http") ? msg.sender.avatar_url : `${import.meta.env.VITE_API_URL || "http://localhost:1104"}${msg.sender.avatar_url}`}
                              alt=""
                              style={{ width: 22, height: 22, borderRadius: "50%", objectFit: "cover", flexShrink: 0 }}
                              onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = "none"; }}
                            />
                          ) : (
                            <div style={{ width: 22, height: 22, borderRadius: "50%", background: "#1F2937", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                              <span style={{ color: "#9ca3af", fontSize: 9, fontWeight: 600 }}>
                                {(msg.sender?.full_name || msg.sender?.username || "?")[0].toUpperCase()}
                              </span>
                            </div>
                          )}
                          <span style={{ color: "#9ca3af", fontSize: 11 }}>
                            {msg.sender?.full_name || msg.sender?.username || msg.sender_id.substring(0, 8)}
                          </span>
                        </div>
                      )}

                      {/* Reply preview */}
                      {(msg as Message & { reply_to_id?: string }).reply_to_id && (
                        <div
                          style={{
                            background: "#1F2937",
                            borderLeft: "3px solid #374151",
                            borderRadius: 6,
                            padding: "4px 8px",
                            marginBottom: 4,
                            maxWidth: "100%",
                            color: "#6b7280",
                            fontSize: 11,
                          }}
                        >
                          Replying to a message
                        </div>
                      )}

                      {/* Bubble */}
                      <div
                        style={{
                          padding: isImageMsg ? "4px" : "8px 14px",
                          borderRadius: 18,
                          borderBottomRightRadius: isMe ? 4 : 18,
                          borderBottomLeftRadius: isMe ? 18 : 4,
                          background: isVideoCall
                            ? "#1F2937"
                            : isMe
                            ? "#15803d"
                            : "#1F2937",
                          color: "#f3f4f6",
                          fontSize: 13,
                          lineHeight: 1.45,
                          border: isVideoCall ? "1px solid #374151" : "none",
                          cursor: "default",
                          position: "relative",
                        }}
                        onDoubleClick={() => setReplyTo(msg)}
                        title="Double-click to reply"
                      >
                        {renderMessageContent(msg)}
                      </div>

                      {/* Timestamp + status */}
                      <div
                        style={{
                          display: "flex",
                          alignItems: "center",
                          gap: 4,
                          marginTop: 2,
                          marginLeft: 4,
                          marginRight: 4,
                        }}
                      >
                        <span style={{ color: "#4b5563", fontSize: 10 }}>
                          {new Date(msg.sent_at).toLocaleTimeString([], {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </span>
                        {isMe && (
                          <MdCheck
                            size={12}
                            color={msg.is_read ? "#22c55e" : "#6b7280"}
                            title={msg.is_read ? "Read" : "Delivered"}
                          />
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              );
            })
          )}
          <div ref={bottomRef} />
        </div>

        {/* Reply preview bar */}
        {replyTo && (
          <div
            style={{
              padding: "8px 16px",
              borderTop: "1px solid #1F2937",
              background: "#0F172A",
              display: "flex",
              alignItems: "center",
              gap: 10,
            }}
          >
            <div style={{ flex: 1, borderLeft: "3px solid #22c55e", paddingLeft: 10 }}>
              <p style={{ margin: 0, color: "#9ca3af", fontSize: 11, fontWeight: 600 }}>
                Replying to {replyTo.sender?.full_name || replyTo.sender_id.substring(0, 8)}
              </p>
              <p style={{ margin: 0, color: "#6b7280", fontSize: 11 }}>
                {truncate(replyTo.content, 60)}
              </p>
            </div>
            <button
              onClick={() => setReplyTo(null)}
              style={{ background: "none", border: "none", color: "#6b7280", cursor: "pointer", padding: 0 }}
            >
              <MdClose size={16} />
            </button>
          </div>
        )}

        {/* Input area */}
        <div
          style={{
            padding: "12px 16px",
            borderTop: replyTo ? "none" : "1px solid #1F2937",
            background: "#0F172A",
          }}
        >
          <form
            onSubmit={sendMessage}
            style={{ display: "flex", gap: 8, alignItems: "center" }}
          >
            {/* Attach button */}
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              disabled={uploading}
              title="Attach image"
              style={{
                background: "none",
                border: "none",
                color: uploading ? "#374151" : "#6b7280",
                cursor: uploading ? "not-allowed" : "pointer",
                padding: "6px",
                display: "flex",
                alignItems: "center",
                borderRadius: 8,
                flexShrink: 0,
                transition: "color 0.15s",
              }}
            >
              {uploading ? (
                <div
                  style={{
                    width: 18,
                    height: 18,
                    border: "2px solid #22c55e",
                    borderTopColor: "transparent",
                    borderRadius: "50%",
                    animation: "spin 1s linear infinite",
                  }}
                />
              ) : (
                <MdAttachFile size={20} />
              )}
            </button>

            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              style={{ display: "none" }}
              onChange={handleFileChange}
            />

            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder={`Message ${active.label}…`}
              style={{
                flex: 1,
                background: "#1F2937",
                border: "1px solid #374151",
                color: "#f3f4f6",
                borderRadius: 22,
                padding: "10px 16px",
                fontSize: 13,
                outline: "none",
                transition: "border-color 0.15s",
              }}
              onFocus={(e) =>
                ((e.currentTarget as HTMLInputElement).style.borderColor = "#16a34a")
              }
              onBlur={(e) =>
                ((e.currentTarget as HTMLInputElement).style.borderColor = "#374151")
              }
            />

            <button
              type="submit"
              disabled={!input.trim()}
              style={{
                background: input.trim() ? "#15803d" : "#1F2937",
                border: "none",
                borderRadius: "50%",
                width: 40,
                height: 40,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                cursor: input.trim() ? "pointer" : "not-allowed",
                color: input.trim() ? "#fff" : "#4b5563",
                flexShrink: 0,
                transition: "background 0.15s",
              }}
            >
              <MdSend size={18} />
            </button>
          </form>
        </div>
      </div>

      {/* ── Video Call Modal ── */}
      {videoCallRoomId && (
        <VideoCallModal
          roomId={videoCallRoomId}
          roomTitle={active.label}
          onClose={() => setVideoCallRoomId(null)}
        />
      )}

      {/* ── Image full-screen preview ── */}
      {imagePreview && (
        <div
          onClick={() => setImagePreview(null)}
          style={{
            position: "fixed",
            inset: 0,
            zIndex: 9998,
            background: "rgba(0,0,0,0.9)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            cursor: "zoom-out",
          }}
        >
          <img
            src={imagePreview}
            alt="Preview"
            style={{ maxWidth: "90vw", maxHeight: "90vh", objectFit: "contain", borderRadius: 8 }}
            onClick={(e) => e.stopPropagation()}
          />
          <button
            onClick={() => setImagePreview(null)}
            style={{
              position: "absolute",
              top: 16,
              right: 16,
              background: "#1F2937",
              border: "none",
              borderRadius: "50%",
              width: 36,
              height: 36,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "#fff",
              cursor: "pointer",
            }}
          >
            <MdClose size={18} />
          </button>
        </div>
      )}

      {/* Global spinner CSS */}
      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );
}
