import { useEffect, useState } from "react";
import { notificationApi } from "../services/api";
import type { Notification } from "../types";
import { MdNotifications, MdDoneAll, MdCircle } from "react-icons/md";

const PRIORITY_COLORS: Record<string, string> = {
  critical: "border-l-red-500",
  high:     "border-l-orange-500",
  normal:   "border-l-blue-500",
  low:      "border-l-gray-600",
};

export default function NotificationsPage() {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [loading, setLoading] = useState(true);
  const [unreadOnly, setUnreadOnly] = useState(false);

  useEffect(() => { load(); }, [unreadOnly]);

  const load = () => {
    setLoading(true);
    notificationApi.list({ unread_only: unreadOnly })
      .then(({ data }) => setNotifications(Array.isArray(data) ? data : []))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  const markRead = async (id: string) => {
    await notificationApi.markRead(id).catch(() => {});
    setNotifications((prev) => prev.map((n) => n.id === id ? { ...n, is_read: true } : n));
  };

  const markAllRead = async () => {
    await notificationApi.markAllRead().catch(() => {});
    setNotifications((prev) => prev.map((n) => ({ ...n, is_read: true })));
  };

  const unreadCount = notifications.filter((n) => !n.is_read).length;

  return (
    <div className="p-6 max-w-3xl">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-white text-xl font-bold">Notifications</h2>
          <p className="text-gray-400 text-sm">{unreadCount} unread</p>
        </div>
        <div className="flex items-center gap-3">
          <label className="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={unreadOnly}
              onChange={(e) => setUnreadOnly(e.target.checked)}
              className="rounded border-gray-600 bg-gray-800 text-green-600"
            />
            <span className="text-gray-400 text-sm">Unread only</span>
          </label>
          {unreadCount > 0 && (
            <button
              onClick={markAllRead}
              className="flex items-center gap-2 text-sm text-gray-400 hover:text-white transition-colors"
            >
              <MdDoneAll size={18} />
              Mark all read
            </button>
          )}
        </div>
      </div>

      {loading ? (
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="h-16 bg-gray-900 rounded-xl animate-pulse" />
          ))}
        </div>
      ) : notifications.length === 0 ? (
        <div className="text-center py-20">
          <MdNotifications size={48} className="text-gray-700 mx-auto mb-3" />
          <p className="text-gray-400">No notifications</p>
        </div>
      ) : (
        <div className="space-y-2">
          {notifications.map((n) => (
            <div
              key={n.id}
              onClick={() => !n.is_read && markRead(n.id)}
              className={`bg-gray-900 border border-gray-800 border-l-4 ${PRIORITY_COLORS[n.priority] || PRIORITY_COLORS.normal} rounded-xl p-4 flex items-start gap-3 cursor-pointer hover:border-gray-700 transition-colors ${n.is_read ? "opacity-60" : ""}`}
            >
              <MdCircle
                size={10}
                className={`mt-1.5 shrink-0 ${n.is_read ? "text-gray-700" : "text-green-400"}`}
              />
              <div className="min-w-0 flex-1">
                <p className={`text-sm font-medium ${n.is_read ? "text-gray-400" : "text-white"}`}>{n.title}</p>
                {n.body && <p className="text-gray-500 text-xs mt-0.5">{n.body}</p>}
                <p className="text-gray-600 text-xs mt-1">
                  {new Date(n.created_at).toLocaleString()}
                  {n.priority !== "normal" && (
                    <span className={`ml-2 capitalize ${n.priority === "critical" ? "text-red-400" : "text-orange-400"}`}>
                      · {n.priority}
                    </span>
                  )}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
