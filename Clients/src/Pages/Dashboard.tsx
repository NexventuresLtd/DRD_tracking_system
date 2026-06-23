import { useEffect, useState } from "react";
import { useAuthStore } from "../stores/authStore";
import { adminApi, teamApi } from "../services/api";
import { MdPeople, MdAssignment, MdRoute, MdLocationOn, MdSecurity } from "react-icons/md";
import { Link } from "react-router-dom";

interface Stats {
  total_users: number;
  total_teams: number;
  active_users_now: number;
  active_invites: number;
  users_by_role: Record<string, number>;
}

const ROLE_COLORS: Record<string, string> = {
  operations_coordinator: "bg-red-500",
  planning_officer: "bg-orange-500",
  team_leader: "bg-green-600",
  field_user: "bg-green-500",
};

export default function Dashboard() {
  const { user } = useAuthStore();
  const [stats, setStats] = useState<Stats | null>(null);

  useEffect(() => {
    if (user?.role === "operations_coordinator") {
      adminApi.getStats().then(({ data }) => setStats(data)).catch(() => {});
    }
  }, [user]);

  const greeting = () => {
    const hour = new Date().getHours();
    if (hour < 12) return "Good morning";
    if (hour < 17) return "Good afternoon";
    return "Good evening";
  };

  return (
    <div className="p-6 space-y-6">
      <div>
        <h2 className="text-white text-xl font-bold">{greeting()}, {user?.full_name?.split(" ")[0]}</h2>
        <p className="text-gray-400 text-sm mt-1">
          {new Date().toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}
        </p>
      </div>

      {stats && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {[
            { label: "Total Users", value: stats.total_users, icon: <MdPeople size={22} />, color: "text-green-400", bg: "bg-blue-900/30" },
            { label: "Active Teams", value: stats.total_teams, icon: <MdPeople size={22} />, color: "text-green-400", bg: "bg-green-900/30" },
            { label: "Online Now", value: stats.active_users_now, icon: <MdLocationOn size={22} />, color: "text-emerald-400", bg: "bg-emerald-900/30" },
            { label: "Open Invites", value: stats.active_invites, icon: <MdSecurity size={22} />, color: "text-orange-400", bg: "bg-orange-900/30" },
          ].map((card) => (
            <div key={card.label} className="bg-gray-900 border border-gray-800 rounded-xl p-5">
              <div className={`w-10 h-10 rounded-lg ${card.bg} flex items-center justify-center ${card.color} mb-3`}>
                {card.icon}
              </div>
              <p className="text-2xl font-bold text-white">{card.value}</p>
              <p className="text-gray-400 text-sm mt-1">{card.label}</p>
            </div>
          ))}
        </div>
      )}

      {stats?.users_by_role && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
          <h3 className="text-white font-semibold mb-4">Users by Role</h3>
          <div className="space-y-3">
            {Object.entries(stats.users_by_role).map(([role, count]) => {
              const total = stats.total_users || 1;
              const pct = Math.round((count / total) * 100);
              return (
                <div key={role}>
                  <div className="flex justify-between text-sm mb-1">
                    <span className="text-gray-300 capitalize">{role.replace(/_/g, " ")}</span>
                    <span className="text-gray-400">{count}</span>
                  </div>
                  <div className="h-2 bg-gray-800 rounded-full">
                    <div
                      className={`h-2 rounded-full ${ROLE_COLORS[role] || "bg-gray-500"}`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {[
          { to: "/map", icon: <MdLocationOn size={24} />, title: "Live Map", desc: "View real-time team positions", color: "bg-green-700" },
          { to: "/teams", icon: <MdPeople size={24} />, title: "Teams", desc: "Manage teams and assignments", color: "bg-green-600" },
          { to: "/comms", icon: <MdAssignment size={24} />, title: "Communications", desc: "Team chat and coordination", color: "bg-purple-600" },
        ].map((item) => (
          <Link
            key={item.to}
            to={item.to}
            className="bg-gray-900 border border-gray-800 hover:border-gray-600 rounded-xl p-5 flex items-start gap-4 transition-all group"
          >
            <div className={`${item.color} w-12 h-12 rounded-xl flex items-center justify-center text-white shrink-0`}>
              {item.icon}
            </div>
            <div>
              <p className="text-white font-semibold group-hover:text-green-400 transition-colors">{item.title}</p>
              <p className="text-gray-400 text-sm mt-0.5">{item.desc}</p>
            </div>
          </Link>
        ))}
      </div>

      <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
        <h3 className="text-white font-semibold mb-1">System Status</h3>
        <p className="text-gray-400 text-sm mb-4">DRD Field Coordination Platform v2.0</p>
        <div className="flex flex-wrap gap-3">
          {["Backend API", "WebSocket", "Database", "Redis"].map((svc) => (
            <div key={svc} className="flex items-center gap-2 bg-gray-800 rounded-lg px-3 py-2">
              <div className="w-2 h-2 bg-green-500 rounded-full" />
              <span className="text-gray-300 text-sm">{svc}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
