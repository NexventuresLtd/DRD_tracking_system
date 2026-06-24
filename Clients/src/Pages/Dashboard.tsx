import { useEffect, useState, useRef, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { useAuthStore } from "../stores/authStore";
import { adminApi, teamApi, missionApi, zonesApi, routeApi, postsApi } from "../services/api";
import {
  MdPeople, MdAssignment, MdRoute, MdLocationOn, MdSecurity,
  MdOutlineSearch, MdOutlineFlag, MdOutlineMap, MdOutlineShield,
} from "react-icons/md";
import { Link } from "react-router-dom";

interface Stats {
  total_users: number;
  total_teams: number;
  active_users_now: number;
  active_invites: number;
  users_by_role: Record<string, number>;
}

interface SearchResult {
  id: string;
  label: string;
  sub?: string;
  category: string;
  route: string;
}

const ROLE_COLORS: Record<string, string> = {
  operations_coordinator: "bg-red-500",
  planning_officer: "bg-orange-500",
  team_leader: "bg-green-600",
  field_user: "bg-green-500",
};

function GlobalSearch() {
  const [q, setQ] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();
  const debounceRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const search = useCallback(async (query: string) => {
    if (!query.trim()) { setResults([]); return; }
    setLoading(true);
    const q = query.toLowerCase();
    const found: SearchResult[] = [];
    await Promise.allSettled([
      missionApi.list().then(({ data }) => {
        (data as { id: string; name: string; status: string }[])
          .filter(m => m.name.toLowerCase().includes(q))
          .slice(0, 4)
          .forEach(m => found.push({ id: m.id, label: m.name, sub: m.status, category: "Mission", route: "/missions" }));
      }),
      teamApi.list().then(({ data }) => {
        const teams = data?.teams ?? data ?? [];
        (teams as { id: string; name: string }[])
          .filter((t: { name: string }) => t.name.toLowerCase().includes(q))
          .slice(0, 4)
          .forEach((t: { id: string; name: string }) => found.push({ id: t.id, label: t.name, category: "Team", route: "/teams" }));
      }),
      zonesApi.list().then(({ data }) => {
        (data as { id: string; name: string; zone_type: string }[])
          .filter(z => z.name.toLowerCase().includes(q))
          .slice(0, 3)
          .forEach(z => found.push({ id: z.id, label: z.name, sub: z.zone_type, category: "Zone", route: "/zones" }));
      }),
      routeApi.list().then(({ data }) => {
        (data as { id: string; name: string; route_type: string }[])
          .filter(r => r.name.toLowerCase().includes(q))
          .slice(0, 3)
          .forEach(r => found.push({ id: r.id, label: r.name, sub: r.route_type, category: "Route", route: "/routes" }));
      }),
      postsApi.list().then(({ data }) => {
        const posts = data?.posts ?? data ?? [];
        (posts as { id: string; name: string }[])
          .filter((p: { name: string }) => p.name.toLowerCase().includes(q))
          .slice(0, 3)
          .forEach((p: { id: string; name: string }) => found.push({ id: p.id, label: p.name, category: "Facility", route: "/posts" }));
      }),
    ]);
    setResults(found);
    setLoading(false);
  }, []);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    if (q.length >= 2) {
      setOpen(true);
      debounceRef.current = setTimeout(() => search(q), 300);
    } else {
      setResults([]);
      setOpen(false);
    }
  }, [q, search]);

  const CAT_COLORS: Record<string, string> = {
    Mission: "#22c55e", Team: "#60a5fa", Zone: "#a78bfa", Route: "#38bdf8", Facility: "#f59e0b",
  };

  const go = (r: SearchResult) => {
    setQ(""); setOpen(false);
    navigate(r.route);
  };

  return (
    <div ref={ref} className="relative w-full max-w-xl">
      <div className="flex items-center gap-2 px-4 py-2.5 rounded-xl" style={{ background: "#060d06", border: "1px solid #1a2e1a" }}>
        <MdOutlineSearch size={18} color="#4b5563" />
        <input
          value={q}
          onChange={e => setQ(e.target.value)}
          onFocus={() => q.length >= 2 && setOpen(true)}
          placeholder="Search missions, teams, zones, routes, facilities…"
          className="flex-1 bg-transparent text-white text-sm outline-none placeholder:text-gray-600"
        />
        {loading && <div className="w-3 h-3 border border-green-500 border-t-transparent rounded-full animate-spin" />}
      </div>
      {open && (
        <div className="absolute top-full mt-1 left-0 right-0 z-50 rounded-xl overflow-hidden shadow-2xl"
          style={{ background: "#060d06", border: "1px solid #1a2e1a" }}>
          {results.length === 0 && !loading
            ? <div className="px-4 py-3 text-gray-500 text-sm">No results for "{q}"</div>
            : results.map(r => (
                <button key={`${r.category}-${r.id}`} onClick={() => go(r)}
                  className="w-full flex items-center gap-3 px-4 py-2.5 text-left hover:bg-green-900/20 transition-colors"
                  style={{ borderBottom: "1px solid #0a140a" }}>
                  <span className="text-xs font-bold px-1.5 py-0.5 rounded shrink-0" style={{ background: `${CAT_COLORS[r.category]}20`, color: CAT_COLORS[r.category] }}>
                    {r.category}
                  </span>
                  <span className="text-white text-sm flex-1 truncate">{r.label}</span>
                  {r.sub && <span className="text-gray-500 text-xs shrink-0">{r.sub}</span>}
                </button>
              ))
          }
        </div>
      )}
    </div>
  );
}

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
      <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
        <div>
          <h2 className="text-white text-xl font-bold">{greeting()}, {user?.full_name?.split(" ")[0]}</h2>
          <p className="text-gray-400 text-sm mt-1">
            {new Date().toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}
          </p>
        </div>
        <GlobalSearch />
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
                    <div className={`h-2 rounded-full ${ROLE_COLORS[role] || "bg-gray-500"}`} style={{ width: `${pct}%` }} />
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
          { to: "/missions", icon: <MdOutlineFlag size={24} />, title: "Missions", desc: "Operations planning and tracking", color: "bg-yellow-700" },
          { to: "/zones", icon: <MdOutlineMap size={24} />, title: "Zones", desc: "Area of operations zones", color: "bg-indigo-700" },
          { to: "/posts", icon: <MdOutlineShield size={24} />, title: "Facilities", desc: "Bases, hospitals, and posts", color: "bg-orange-700" },
        ].map((item) => (
          <Link key={item.to} to={item.to}
            className="bg-gray-900 border border-gray-800 hover:border-gray-600 rounded-xl p-5 flex items-start gap-4 transition-all group">
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
