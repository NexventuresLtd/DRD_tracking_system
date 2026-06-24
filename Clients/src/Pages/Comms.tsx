import { useEffect, useRef, useState } from "react";
import { messageApi, teamApi } from "../services/api";
import type { Message, Team } from "../types";
import { useAuthStore } from "../stores/authStore";
import { MdSend, MdPublic, MdPeople, MdPerson } from "react-icons/md";

type Channel = { id: string; label: string; type: "global" | "team" | "dm"; icon: React.ReactNode };

export default function Comms() {
  const { user } = useAuthStore();
  const [channels, setChannels] = useState<Channel[]>([
    { id: "global", label: "Global", type: "global", icon: <MdPublic size={16} /> },
  ]);
  const [active, setActive] = useState<Channel>(channels[0]);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    teamApi.list().then(({ data }) => {
      const teamChannels: Channel[] = data.map((t: Team) => ({
        id: `team:${t.id}`,
        label: t.name,
        type: "team" as const,
        icon: <MdPeople size={16} />,
      }));
      setChannels((prev) => {
        const nonTeam = prev.filter((c) => c.type !== "team");
        return [...nonTeam, ...teamChannels];
      });
    }).catch(() => {});
  }, []);

  useEffect(() => {
    loadMessages();
    setupWS();
    return () => wsRef.current?.close();
  }, [active]);

  const loadMessages = () => {
    setLoading(true);
    const p = active.type === "global"
      ? messageApi.getGlobal()
      : active.type === "team"
        ? messageApi.getTeam(active.id.replace("team:", ""))
        : messageApi.getDM(active.id.replace("dm:", ""));
    p.then(({ data }) => setMessages(Array.isArray(data) ? data : []))
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
    const ws = new WebSocket(`${wsUrl}/ws/messages/${encodeURIComponent(channel)}?token=${token}`);
    wsRef.current = ws;
    ws.onmessage = (e) => {
      const msg = JSON.parse(e.data);
      if (msg.type === "new_message") {
        setMessages((prev) => [...prev, msg.message]);
        setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }), 50);
      }
    };
  };

  const sendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim()) return;
    const text = input.trim();
    setInput("");
    try {
      const channel = active.id === "global" ? "global"
        : active.type === "team" ? `team:${active.id.replace("team:", "")}`
        : `dm:${active.id.replace("dm:", "")}`;
      await messageApi.send({ content: text, channel });
    } catch {}
  };

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  return (
    <div className="flex h-full">
      <div className="w-60 border-r border-gray-800 flex flex-col">
        <div className="p-4 border-b border-gray-800">
          <p className="text-gray-400 text-xs uppercase tracking-wider font-semibold">Channels</p>
        </div>
        <div className="flex-1 overflow-y-auto p-2 space-y-1">
          {channels.map((ch) => (
            <button
              key={ch.id}
              onClick={() => setActive(ch)}
              className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors text-left ${
                active.id === ch.id ? "bg-green-700 text-white" : "text-gray-400 hover:bg-gray-800 hover:text-white"
              }`}
            >
              {ch.icon}
              <span className="truncate">{ch.label}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 flex flex-col min-w-0">
        <div className="h-12 border-b border-gray-800 flex items-center px-4 gap-2">
          {active.icon}
          <span className="text-white font-medium text-sm">{active.label}</span>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-3">
          {loading ? (
            <div className="flex justify-center pt-8">
              <div className="w-6 h-6 border-2 border-blue-600 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : messages.length === 0 ? (
            <div className="text-center py-16">
              <MdPublic size={36} className="text-gray-700 mx-auto mb-2" />
              <p className="text-gray-500 text-sm">No messages yet</p>
            </div>
          ) : messages.map((msg, i) => {
            const isMe = msg.sender_id === user?.id;
            const prevMsg = messages[i - 1];
            const showHeader = !prevMsg || prevMsg.sender_id !== msg.sender_id;
            return (
              <div key={msg.id} className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
                <div className={`max-w-md ${isMe ? "items-end" : "items-start"} flex flex-col`}>
                  {showHeader && !isMe && (
                    <span className="text-gray-500 text-xs mb-1 ml-1">
                      {msg.sender?.full_name || msg.sender_id.substring(0, 8)}
                    </span>
                  )}
                  <div className={`px-4 py-2.5 rounded-2xl text-sm ${
                    isMe ? "bg-green-700 text-white rounded-br-sm" : "bg-gray-800 text-gray-200 rounded-bl-sm"
                  }`}>
                    {msg.content}
                  </div>
                  <span className="text-gray-600 text-xs mt-1 mx-1">
                    {new Date(msg.sent_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                  </span>
                </div>
              </div>
            );
          })}
          <div ref={bottomRef} />
        </div>

        <div className="p-4 border-t border-gray-800">
          <form onSubmit={sendMessage} className="flex gap-3">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder={`Message ${active.label}...`}
              className="flex-1 bg-gray-800 border border-gray-700 text-white rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-green-600"
            />
            <button
              type="submit"
              disabled={!input.trim()}
              className="bg-green-700 hover:bg-green-600 disabled:bg-gray-800 text-white rounded-xl px-4 py-2.5 transition-colors"
            >
              <MdSend size={18} />
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}
