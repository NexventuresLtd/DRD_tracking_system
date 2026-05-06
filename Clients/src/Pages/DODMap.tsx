import React, { useState, useEffect, useRef, useCallback, useMemo } from "react";
import {
  MapContainer,
  TileLayer,
  Marker,
  Popup,
  Polyline,
  Polygon,
  CircleMarker,
  useMapEvents,
  useMap,
  Tooltip,
} from "react-leaflet";
import L from "leaflet";
import {
  FiWifiOff, FiUsers, FiAlertTriangle, FiClock,
  FiChevronDown, FiMapPin, FiActivity,
  FiNavigation, FiMessageSquare, FiFilter, FiRefreshCw,
  FiSettings, FiDownload, FiSend, FiX, FiCheck,
  FiPlus, FiMinus, FiCrosshair, FiFlag,
  FiShield, FiZap, FiEye,
  FiAlertCircle, FiCheckCircle,
  FiUser, FiBell, FiMaximize2, FiArrowRight, FiHome, FiTruck, FiMap,
  FiChevronLeft, FiChevronRight,
  FiMenu, FiHexagon, FiLock, FiMoon,
} from "react-icons/fi";
import {
  MdLocalHospital, MdDirectionsCar,
  MdSatellite,
  MdLocalPolice, MdTerrain, MdLayers,
} from "react-icons/md";
import { BiTargetLock } from "react-icons/bi";
import { TbRoute, TbBuildingHospital } from "react-icons/tb";
import "leaflet-routing-machine";
import * as api from "../services/api";
import { connectAll, disconnectAll, locationWS, messageWS, eventWS } from "../services/ws";

// ─────────────────────────── TYPES ───────────────────────────
type Status = "active" | "stale" | "offline";
type Team = "Team Alpha" | "Team Bravo" | "Team Charlie" | "Team Delta" | "Team Echo";
type FlagType = "safe" | "trouble" | "help";
type POIType = "checkpoint" | "hospital" | "base" | "observation" | "police" | "supply" | "vehicle" | "meeting" | "command" | "medical" | "extraction";
type MapViewType = "standard" | "satellite" | "terrain" | "topo" | "dark" | "night";
type TacticalShape = "circle" | "square" | "triangle" | "diamond" | "hexagon" | "star" | "cross";

interface Waypoint {
  lat: number;
  lng: number;
  label: string;
  type?: POIType;
}

interface Route {
  id: string;
  name: string;
  assignedTo: string;
  assignedTeam?: string;
  waypoints: Waypoint[];
  createdAt: Date;
  color: string;
  meetingPoint?: boolean;
  visibleTo: string[];
  coordinates: [number, number][];
  isZone?: boolean;
  zoneType?: "perimeter" | "sector" | "corridor" | "extraction";
  isActive?: boolean;
  routeStatus?: string;
  route_status?: string;
  activeFollowCount?: number;
}

interface RouteHistoryItem extends Route {
  deletedAt: Date;
}

interface User {
  user_id: string;
  name: string;
  group: Team;
  lat: number;
  lng: number;
  status: Status;
  lastUpdate: Date;
  message: string;
  speed?: number;
  heading?: number;
  flag?: FlagType | null;
  flagTime?: Date | null;
  currentRoute?: string;
  role?: "lead" | "medic" | "scout" | "support" | "sniper";
}

interface Event {
  id: string;
  time: Date;
  type: "UPDATE" | "STALE" | "OFFLINE" | "ONLINE" | "MESSAGE" | "FLAG" | "ROUTE" | "POI" | "ZONE" | "ALERT" | "ROUTE_FOLLOW";
  user: string;
  team: Team;
  event: string;
  location: string;
}

interface Message {
  id: string;
  from: string;
  to: string;
  content: string;
  time: Date;
  read: boolean;
  priority?: "low" | "normal" | "high" | "urgent";
}

interface POI {
  id: string;
  type: POIType;
  lat: number;
  lng: number;
  label: string;
  team?: Team;
  status?: "active" | "inactive" | "secured" | "compromised";
  visibleTo: string[];
  shape?: TacticalShape;
}

// interface Zone {
//   id: string;
//   name: string;
//   type: "perimeter" | "sector" | "corridor" | "extraction" | "danger" | "safe";
//   coordinates: [number, number][];
//   color: string;
//   assignedTeams: string[];
//   assignedUsers: string[];
//   createdAt: Date;
//   description?: string;
// }

interface TeamInfo {
  id: string;
  name: string;
  color: string;
  memberCount: number;
}

interface UserRecord {
  id: string;
  username: string;
  full_name: string;
  email: string;
  role: string;
  is_active: boolean;
  teamId?: string;
  teamName?: string;
  teamRole?: string;
}

interface SOSIncident {
  userId: string;
  description: string;
  createdAt: Date;
  lat: number;
  lng: number;
}

// ─────────────────────────── CONSTANTS ───────────────────────────
const TEAM_COLORS: Record<Team, { primary: string; marker: string; bg: string; border: string }> = {
  "Team Alpha": { primary: "#22c55e", marker: "#16a34a", bg: "rgba(34,197,94,0.15)", border: "#22c55e" },
  "Team Bravo": { primary: "#f59e0b", marker: "#d97706", bg: "rgba(245,158,11,0.15)", border: "#f59e0b" },
  "Team Charlie": { primary: "#ef4444", marker: "#dc2626", bg: "rgba(239,68,68,0.15)", border: "#ef4444" },
  "Team Delta": { primary: "#8b5cf6", marker: "#7c3aed", bg: "rgba(139,92,246,0.15)", border: "#8b5cf6" },
  "Team Echo": { primary: "#06b6d4", marker: "#0891b2", bg: "rgba(6,182,212,0.15)", border: "#06b6d4" },
};

const POI_ICONS_CONFIG: Record<POIType, { icon: React.ReactNode; color: string; label: string; tacticalIcon: string }> = {
  checkpoint: { icon: <BiTargetLock size={16} />, color: "#a855f7", label: "Checkpoint", tacticalIcon: "CP" },
  hospital: { icon: <TbBuildingHospital size={16} />, color: "#ef4444", label: "Hospital", tacticalIcon: "H" },
  base: { icon: <FiHome size={16} />, color: "#3b82f6", label: "Base", tacticalIcon: "FOB" },
  observation: { icon: <FiEye size={16} />, color: "#64748b", label: "Observation", tacticalIcon: "OP" },
  police: { icon: <MdLocalPolice size={16} />, color: "#06b6d4", label: "Police Station", tacticalIcon: "LE" },
  supply: { icon: <FiTruck size={16} />, color: "#f97316", label: "Supply Point", tacticalIcon: "SUP" },
  vehicle: { icon: <MdDirectionsCar size={16} />, color: "#84cc16", label: "Vehicle", tacticalIcon: "V" },
  meeting: { icon: <FiUsers size={16} />, color: "#ec4899", label: "Meeting Point", tacticalIcon: "RV" },
  command: { icon: <FiFlag size={16} />, color: "#dc2626", label: "Command Post", tacticalIcon: "CMD" },
  medical: { icon: <MdLocalHospital size={16} />, color: "#f43f5e", label: "Medical Station", tacticalIcon: "MED" },
  extraction: { icon: <FiArrowRight size={16} />, color: "#eab308", label: "Extraction Point", tacticalIcon: "EX" },
};

const STATUS_COLORS: Record<Status, string> = {
  active: "#22c55e",
  stale: "#f59e0b",
  offline: "#ef4444",
};

const FLAG_COLORS: Record<FlagType, { color: string; label: string; icon: React.ReactNode }> = {
  safe: { color: "#22c55e", label: "SAFE", icon: <FiCheckCircle size={12} /> },
  trouble: { color: "#f59e0b", label: "TROUBLE", icon: <FiAlertTriangle size={12} /> },
  help: { color: "#ef4444", label: "SOS / HELP", icon: <FiAlertCircle size={12} /> },
};

const ROLE_ICONS: Record<string, string> = {
  lead: "LD",
  medic: "MED",
  scout: "SC",
  support: "SUP",
  sniper: "SN",
};

const MAP_TILES: Record<MapViewType, { url: string; attribution: string; label: string; icon: React.ReactNode }> = {
  standard: {
    url: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    label: "Standard",
    icon: <FiMap size={14} />,
  },
  satellite: {
    url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
    attribution: '&copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community',
    label: "Satellite",
    icon: <MdSatellite size={14} />,
  },
  terrain: {
    url: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
    attribution: '&copy; <a href="https://opentopomap.org">OpenTopoMap</a>',
    label: "Terrain",
    icon: <MdTerrain size={14} />,
  },
  topo: {
    url: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
    attribution: '&copy; <a href="https://opentopomap.org">OpenTopoMap</a>',
    label: "Topographic",
    icon: <MdLayers size={14} />,
  },
  dark: {
    url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    label: "Dark",
    icon: <FiMoon size={14} />,
  },
  night: {
    url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    label: "Night",
    icon: <FiMoon size={14} />,
  },
};

const MAP_CENTER: [number, number] = [-1.9441, 30.0619];

function distanceKm(aLat: number, aLng: number, bLat: number, bLng: number) {
  const radius = 6371;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const lat1 = (aLat * Math.PI) / 180;
  const lat2 = (bLat * Math.PI) / 180;
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const a = sinLat * sinLat + Math.cos(lat1) * Math.cos(lat2) * sinLng * sinLng;
  return 2 * radius * Math.asin(Math.min(1, Math.sqrt(a)));
}

function formatDistance(distanceKmValue: number | null | undefined) {
  if (distanceKmValue == null || Number.isNaN(distanceKmValue)) {
    return "Distance unavailable";
  }
  if (distanceKmValue < 1) {
    return `${Math.round(distanceKmValue * 1000)} m`;
  }
  return `${distanceKmValue.toFixed(1)} km`;
}

const INITIAL_POIS: POI[] = [
  { id: "poi_1", type: "base", lat: -1.942, lng: 30.038, label: "FOB Alpha", team: "Team Alpha", status: "secured", visibleTo: ["ALL"], shape: "square" },
  { id: "poi_2", type: "checkpoint", lat: -1.915, lng: 30.045, label: "CP Alpha", visibleTo: ["ALL"], shape: "diamond" },
  { id: "poi_3", type: "checkpoint", lat: -1.955, lng: 30.005, label: "CP Bravo", visibleTo: ["ALL"], shape: "diamond" },
  { id: "poi_4", type: "checkpoint", lat: -1.965, lng: 30.065, label: "CP Charlie", visibleTo: ["ALL"], shape: "diamond" },
  { id: "poi_5", type: "observation", lat: -1.922, lng: 30.072, label: "OP Sierra", visibleTo: ["ALL"], shape: "triangle" },
  { id: "poi_6", type: "hospital", lat: -1.936, lng: 30.058, label: "Central Hospital", status: "active", visibleTo: ["ALL"], shape: "cross" },
  { id: "poi_7", type: "police", lat: -1.928, lng: 30.048, label: "Police HQ", visibleTo: ["ALL"], shape: "star" },
  { id: "poi_8", type: "supply", lat: -1.951, lng: 30.042, label: "Supply Depot", visibleTo: ["ALL"], shape: "hexagon" },
  { id: "poi_9", type: "command", lat: -1.940, lng: 30.055, label: "Tactical Command", visibleTo: ["ALL"], shape: "star" },
  { id: "poi_10", type: "extraction", lat: -1.960, lng: 30.070, label: "EX Point Lima", visibleTo: ["ALL"], shape: "circle" },
];

const INITIAL_USERS: User[] = [
  { user_id: "alpha_1", name: "Alpha 1", group: "Team Alpha", lat: -1.910, lng: 30.025, status: "active", lastUpdate: new Date(), message: "Moving to CP Alpha", speed: 3.2, heading: 45, flag: null, role: "lead" },
  { user_id: "alpha_2", name: "Alpha 2", group: "Team Alpha", lat: -1.935, lng: 30.032, status: "active", lastUpdate: new Date(), message: "At FOB Alpha", speed: 0, heading: 90, flag: null, role: "medic" },
  { user_id: "alpha_3", name: "Alpha 3", group: "Team Alpha", lat: -1.918, lng: 30.018, status: "active", lastUpdate: new Date(), message: "Patrol route", speed: 2.1, heading: 180, flag: null, role: "scout" },
  { user_id: "bravo_1", name: "Bravo 1", group: "Team Bravo", lat: -1.902, lng: 30.052, status: "active", lastUpdate: new Date(), message: "Near CP Alpha", speed: 1.5, heading: 270, flag: null, role: "lead" },
  { user_id: "bravo_2", name: "Bravo 2", group: "Team Bravo", lat: -1.928, lng: 30.068, status: "stale", lastUpdate: new Date(Date.now() - 65000), message: "Moving east", speed: 0, heading: 0, flag: null, role: "support" },
  { user_id: "bravo_3", name: "Bravo 3", group: "Team Bravo", lat: -1.945, lng: 30.055, status: "active", lastUpdate: new Date(), message: "Standing by", speed: 0.5, heading: 135, flag: null, role: "sniper" },
  { user_id: "charlie_1", name: "Charlie 1", group: "Team Charlie", lat: -1.948, lng: 30.072, status: "active", lastUpdate: new Date(), message: "Moving to CP Charlie", speed: 2.8, heading: 225, flag: null, role: "lead" },
  { user_id: "charlie_2", name: "Charlie 2", group: "Team Charlie", lat: -1.955, lng: 30.018, status: "offline", lastUpdate: new Date(Date.now() - 132000), message: "Last seen near CP Bravo", speed: 0, heading: 0, flag: null, role: "medic" },
  { user_id: "charlie_3", name: "Charlie 3", group: "Team Charlie", lat: -1.932, lng: 30.082, status: "stale", lastUpdate: new Date(Date.now() - 88000), message: "Near OP Sierra", speed: 0, heading: 0, flag: null, role: "scout" },
  { user_id: "delta_1", name: "Delta 1", group: "Team Delta", lat: -1.960, lng: 30.040, status: "active", lastUpdate: new Date(), message: "Supply run", speed: 4.0, heading: 90, flag: null, role: "lead" },
  { user_id: "echo_1", name: "Echo 1", group: "Team Echo", lat: -1.920, lng: 30.055, status: "active", lastUpdate: new Date(), message: "Medical support", speed: 1.0, heading: 0, flag: null, role: "medic" },
];

// ─────────────────────────── HELPER FUNCTIONS ───────────────────────────
function formatElapsed(d: Date): string {
  const s = Math.floor((Date.now() - d.getTime()) / 1000);
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s ago`;
  return `${Math.floor(m / 60)}h ${m % 60}m ago`;
}

function formatTime(d: Date): string {
  return d.toTimeString().slice(0, 8);
}

function getTacticalShapeSVG(shape: TacticalShape, color: string, size: number = 24): string {
  switch (shape) {
    case "circle":
      return `<svg width="${size}" height="${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${size / 2 - 2}" fill="${color}22" stroke="${color}" stroke-width="2"/></svg>`;
    case "square":
      return `<svg width="${size}" height="${size}"><rect x="2" y="2" width="${size - 4}" height="${size - 4}" fill="${color}22" stroke="${color}" stroke-width="2"/></svg>`;
    case "triangle":
      return `<svg width="${size}" height="${size}"><polygon points="${size / 2},2 ${size - 2},${size - 2} 2,${size - 2}" fill="${color}22" stroke="${color}" stroke-width="2"/></svg>`;
    case "diamond":
      const mid = size / 2;
      return `<svg width="${size}" height="${size}"><polygon points="${mid},2 ${size - 2},${mid} ${mid},${size - 2} 2,${mid}" fill="${color}22" stroke="${color}" stroke-width="2"/></svg>`;
    case "hexagon":
      const hmid = size / 2;
      return `<svg width="${size}" height="${size}"><polygon points="${hmid},2 ${size - 3},${hmid * 0.6} ${size - 3},${size - hmid * 0.6 - 2} ${hmid},${size - 2} 3,${size - hmid * 0.6 - 2} 3,${hmid * 0.6}" fill="${color}22" stroke="${color}" stroke-width="2"/></svg>`;
    case "star":
      return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><polygon points="${size / 2},2 ${size * 0.62},${size * 0.38} ${size - 2},${size * 0.38} ${size * 0.68},${size * 0.6} ${size * 0.78},${size - 2} ${size / 2},${size * 0.74} ${size * 0.22},${size - 2} ${size * 0.32},${size * 0.6} 2,${size * 0.38} ${size * 0.38},${size * 0.38}" fill="${color}22" stroke="${color}" stroke-width="2"/></svg>`;
    case "cross":
      return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><path d="M${size * 0.42} 2h${size * 0.16}v${size * 0.42}H${size - 2}v${size * 0.16}H${size * 0.58}V${size - 2}H${size * 0.42}V${size * 0.58}H2V${size * 0.42}h${size * 0.4}V2z" fill="${color}22" stroke="${color}" stroke-width="2"/></svg>`;
    default:
      return `<svg width="${size}" height="${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${size / 2 - 2}" fill="${color}22" stroke="${color}" stroke-width="2"/></svg>`;
  }
}

function createUserMarkerHTML(user: User, isSelected: boolean): string {
  const col = TEAM_COLORS[user.group].primary;
  const size = isSelected ? 40 : 32;
  const roleIcon = user.role ? ROLE_ICONS[user.role] || "" : "";

  return `
    <div style="
      width: ${size}px;
      height: ${size}px;
      border-radius: 50%;
      background: ${user.status === "offline" ? "rgba(30,41,59,0.9)" : TEAM_COLORS[user.group].bg};
      border: ${user.status === "stale" ? 3 : 2}px ${user.status === "stale" ? "dashed" : "solid"} ${user.status === "offline" ? "#ef4444" : col};
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: ${isSelected ? 12 : 10}px;
      font-weight: 700;
      color: ${user.status === "offline" ? "#94a3b8" : col};
      font-family: 'Poppins', sans-serif;
      box-shadow: 0 2px 8px rgba(0,0,0,0.4);
      position: relative;
    ">
      ${user.name.replace(" ", "").substring(0, 2).toUpperCase()}
      ${user.flag ? `<div style="position: absolute; top: -4px; right: -4px; width: 14px; height: 14px; border-radius: 50%; background: ${FLAG_COLORS[user.flag].color}; border: 2px solid #0a162e; font-size: 8px; display: flex; align-items: center; justify-content: center; color: white;">!</div>` : ""}
      ${roleIcon ? `<div style="position: absolute; bottom: -4px; right: -4px; width: 14px; height: 14px; border-radius: 50%; background: ${col}; border: 2px solid #0a162e; font-size: 8px; display: flex; align-items: center; justify-content: center; color: white;">${roleIcon}</div>` : ""}
    </div>
  `;
}

function createPOIMarkerHTML(poi: POI): string {
  const info = POI_ICONS_CONFIG[poi.type];
  const shape = poi.shape || "diamond";

  return `
    <div style="
      width: 34px;
      height: 34px;
      display: flex;
      align-items: center;
      justify-content: center;
      position: relative;
    ">
      ${getTacticalShapeSVG(shape, info.color, 34)}
      <span style="
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        font-size: 8px;
        font-weight: 700;
        color: ${info.color};
        font-family: 'Poppins', sans-serif;
        pointer-events: none;
      ">${info.tacticalIcon}</span>
    </div>
  `;
}

function createUserIcon(user: User, isSelected: boolean): L.DivIcon {
  return L.divIcon({
    className: "custom-user-marker",
    html: createUserMarkerHTML(user, isSelected),
    iconSize: [isSelected ? 40 : 32, isSelected ? 40 : 32],
    iconAnchor: [isSelected ? 20 : 16, isSelected ? 20 : 16],
    popupAnchor: [0, isSelected ? -20 : -16],
  });
}

function createPOIIcon(poi: POI): L.DivIcon {
  return L.divIcon({
    className: "custom-poi-marker",
    html: createPOIMarkerHTML(poi),
    iconSize: [34, 34],
    iconAnchor: [17, 17],
    popupAnchor: [0, -17],
  });
}

// ─────────────────────────── COMPONENTS ───────────────────────────

// function StatusDot({ status }: { status: Status }) {
//   return (
//     <span
//       className="inline-block rounded-full flex-shrink-0"
//       style={{
//         width: 7,
//         height: 7,
//         backgroundColor: STATUS_COLORS[status],
//         boxShadow: status === "active" ? `0 0 6px ${STATUS_COLORS.active}` : "none",
//       }}
//     />
//   );
// }

function PanelHeader({
  title,
  icon,
  expanded,
  onToggle,
  badge,
}: {
  title: string;
  icon: React.ReactNode;
  expanded: boolean;
  onToggle: () => void;
  badge?: number;
}) {
  return (
    <button
      onClick={onToggle}
      className="w-full flex items-center gap-2 px-3 py-2.5 bg-white/5 hover:bg-white/8 border-b border-white/10 text-foreground cursor-pointer text-xs font-semibold tracking-wide transition-colors"
    >
      <span className="text-slate-400 text-sm">{icon}</span>
      <span className="flex-1 text-left truncate">{title}</span>
      {badge !== undefined && badge > 0 && (
        <span className="bg-red-500 text-white rounded-full min-w-[18px] h-[18px] flex items-center justify-center text-[10px] font-bold px-1">
          {badge}
        </span>
      )}
      <span className="text-slate-500 text-xs transition-transform" style={{ transform: expanded ? "rotate(180deg)" : "rotate(0deg)" }}>
        <FiChevronDown size={12} />
      </span>
    </button>
  );
}

function MapEventsHandler({
  onMapClick,
  routeDrawMode,
}: {
  onMapClick: (lat: number, lng: number) => void;
  routeDrawMode: boolean;
}) {
  useMapEvents({
    click(e) {
      if (routeDrawMode) {
        onMapClick(e.latlng.lat, e.latlng.lng);
      }
    },
  });
  return null;
}

function MapFlyController({ target }: { target: { lat: number; lng: number } | null }) {
  const map = useMap();
  useEffect(() => {
    if (target) map.flyTo([target.lat, target.lng], 16, { duration: 1.2 });
  }, [target, map]);
  return null;
}

function RoutePath({ route }: { route: Route }) {
  const pathRef = useRef<L.Routing.Control | null>(null);
  const map = useMap();

  useEffect(() => {
    if (route.coordinates.length >= 2 && map) {
      if (pathRef.current) {
        map.removeControl(pathRef.current);
      }

      const control = L.Routing.control({
        waypoints: route.coordinates.map(coord => L.latLng(coord[0], coord[1])),
        routeWhileDragging: false,
        showAlternatives: false,
        fitSelectedRoutes: false,
        lineOptions: {
          styles: [
            {
              color: route.color,
              weight: route.isZone ? 1 : 4,
              opacity: route.isZone ? 0.5 : 0.8,
              dashArray: route.isZone ? "5 10" : undefined,
            }
          ],
          extendToWaypoints: true,
          missingRouteTolerance: 0,
        },
        // createMarker: () => null,
        router: new L.Routing.OSRMv1({
          serviceUrl: 'https://router.project-osrm.org/route/v1',
        }),
      });

      control.addTo(map);
      pathRef.current = control;

      return () => {
        if (pathRef.current) {
          map.removeControl(pathRef.current);
        }
      };
    }
  }, [route, map]);

  return null;
}

function TopBar({
  users,
  // sidebarOpen,
  onToggleSidebar,
  isConnected,
  onLogout,
  currentUser,
}: {
  users: User[];
  sidebarOpen: boolean;
  onToggleSidebar: () => void;
  isConnected: boolean;
  onLogout: () => void;
  currentUser: { username?: string; full_name?: string; email?: string; role?: string } | null;
}) {
  const active = users.filter(u => u.status === "active").length;
  const stale = users.filter(u => u.status === "stale").length;
  const offline = users.filter(u => u.status === "offline").length;
  const [showProfile, setShowProfile] = useState(false);

  const displayName = currentUser?.full_name || currentUser?.username || "Commander";
  const initials = displayName.split(" ").map(w => w[0] ?? "").join("").slice(0, 2).toUpperCase() || "CM";
  const roleColors: Record<string, string> = {
    super_admin: "#ef4444", admin: "#f97316", commander: "#8b5cf6",
    operator: "#3b82f6", field_unit: "#22c55e", viewer: "#94a3b8",
  };
  const roleColor = roleColors[currentUser?.role ?? ""] ?? "#3b82f6";

  return (
    <div className="bg-slate-900 border-b border-white/10 flex items-center px-3 md:px-4 h-14 gap-1 flex-shrink-0 relative">
      <button onClick={onToggleSidebar} className="md:hidden bg-transparent border-none text-slate-400 p-1.5 cursor-pointer mr-1">
        <FiMenu size={18} />
      </button>

      <div className="flex items-center gap-2 md:gap-3 mr-2 md:mr-4">
        <div className="w-8 h-8 md:w-9 md:h-9 rounded-lg bg-primary/20 border border-primary/50 flex items-center justify-center text-primary shrink-0">
          <FiShield size={16} />
        </div>
        <div className="hidden sm:block">
          <div className="text-foreground font-bold text-xs md:text-sm leading-tight">DRD TRACKING</div>
          <div className="text-slate-500 text-[9px] tracking-wider hidden md:block">Field Coordination</div>
        </div>
      </div>

      <div className="hidden sm:block w-px h-7 bg-white/10 mx-1 md:mx-2" />

      <div className="flex items-center gap-0.5 md:gap-1 flex-1 md:flex-none overflow-x-auto">
        <StatChip label="TOTAL" value={String(users.length)} icon={<FiUsers size={12} />} color="#94a3b8" />
        <StatChip label="ACT" value={String(active)} icon={<FiActivity size={12} />} color="#22c55e" />
        <StatChip label="STL" value={String(stale)} icon={<FiClock size={12} />} color="#f59e0b" />
        <StatChip label="OFF" value={String(offline)} icon={<FiWifiOff size={12} />} color="#ef4444" />
      </div>

      <div className="flex-1" />

      <div className="flex items-center gap-2 md:gap-3">
        {/* Live indicator */}
        <div className="hidden sm:flex items-center gap-1.5 text-[10px]" title={isConnected ? "Connected" : "Mock data"}>
          <span className="w-2 h-2 rounded-full animate-pulse" style={{ backgroundColor: isConnected ? "#22c55e" : "#f59e0b" }} />
          <span className="text-slate-500 font-semibold tracking-wider">{isConnected ? "LIVE" : "DEMO"}</span>
        </div>

        {/* Profile button */}
        <button
          onClick={() => setShowProfile(v => !v)}
          className="flex items-center gap-2 px-2 py-1.5 rounded-lg cursor-pointer transition-all hover:opacity-90"
          style={{ backgroundColor: `${roleColor}15`, border: `1px solid ${roleColor}35` }}
          title="View profile"
        >
          <div className="w-6 h-6 rounded-full flex items-center justify-center text-[9px] font-bold shrink-0"
            style={{ backgroundColor: `${roleColor}25`, border: `1.5px solid ${roleColor}60`, color: roleColor }}>
            {initials}
          </div>
          <div className="hidden md:block text-left">
            <div className="text-white text-[10px] font-semibold leading-none truncate max-w-[90px]">{displayName}</div>
            <div className="text-[8px] font-bold tracking-wider mt-0.5" style={{ color: roleColor }}>
              {(currentUser?.role ?? "viewer").toUpperCase().replace("_", " ")}
            </div>
          </div>
        </button>

        {/* Logout */}
        <button
          onClick={onLogout}
          title="Sign out"
          className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg font-semibold cursor-pointer transition-all hover:opacity-80"
          style={{ backgroundColor: "rgba(239,68,68,0.12)", border: "1px solid rgba(239,68,68,0.25)", color: "#ef4444", fontSize: 11 }}
        >
          <FiLock size={12} />
          <span className="hidden sm:inline">LOGOUT</span>
        </button>
      </div>

      {/* Profile dropdown */}
      {showProfile && currentUser && (
        <>
          <div className="fixed inset-0 z-[3999]" onClick={() => setShowProfile(false)} />
          <div className="absolute top-full right-3 mt-2 z-[4000] rounded-xl shadow-2xl overflow-hidden"
            style={{ width: 260, background: "#0f1c2e", border: "1px solid rgba(255,255,255,0.08)" }}>
            <div className="p-4 border-b" style={{ borderColor: "rgba(255,255,255,0.06)", background: `${roleColor}08` }}>
              <div className="flex items-center gap-3">
                <div className="w-11 h-11 rounded-full flex items-center justify-center font-bold text-sm shrink-0"
                  style={{ backgroundColor: `${roleColor}20`, border: `2px solid ${roleColor}50`, color: roleColor }}>
                  {initials}
                </div>
                <div className="min-w-0">
                  <div className="text-white font-semibold text-sm truncate">{currentUser.full_name || currentUser.username}</div>
                  {currentUser.username && currentUser.full_name && (
                    <div className="text-slate-500 text-[10px] truncate">@{currentUser.username}</div>
                  )}
                  <span className="inline-block mt-1 px-1.5 py-0.5 rounded text-[8px] font-bold tracking-wide"
                    style={{ backgroundColor: `${roleColor}18`, color: roleColor }}>
                    {(currentUser.role ?? "viewer").toUpperCase().replace("_", " ")}
                  </span>
                </div>
              </div>
            </div>
            {currentUser.email && (
              <div className="px-4 py-2.5 flex items-center gap-2 text-[11px] text-slate-400" style={{ borderBottom: "1px solid rgba(255,255,255,0.05)" }}>
                <FiUser size={11} className="shrink-0 text-slate-500" />
                <span className="truncate">{currentUser.email}</span>
              </div>
            )}
            <button
              onClick={() => { setShowProfile(false); onLogout(); }}
              className="w-full flex items-center gap-2 px-4 py-3 text-[11px] font-semibold transition-colors hover:opacity-80 cursor-pointer"
              style={{ color: "#ef4444", background: "rgba(239,68,68,0.06)", border: "none" }}
            >
              <FiLock size={12} />
              Sign out
            </button>
          </div>
        </>
      )}
    </div>
  );
}

function StatChip({ label, value, color, icon }: { label: string; value: string; color: string; icon: React.ReactNode }) {
  return (
    <div className="flex items-center gap-1 md:gap-1.5 px-1.5 md:px-2.5 py-1">
      <span style={{ color }} className="text-xs md:text-sm flex-shrink-0">{icon}</span>
      <div className="hidden sm:block">
        <div className="text-slate-600 text-[8px] md:text-[9px] tracking-wider font-medium">{label}</div>
        <div className="text-xs md:text-sm font-bold leading-tight" style={{ color }}>{value}</div>
      </div>
    </div>
  );
}

function MapLegend() {
  const items = [
    { color: "#22c55e", label: "Active", dot: true },
    { color: "#f59e0b", label: "Stale", dot: true },
    { color: "#ef4444", label: "Offline", dot: true },
    { color: "#a855f7", label: "Checkpoint", shape: "diamond" as TacticalShape },
    { color: "#3b82f6", label: "Base", shape: "square" as TacticalShape },
    { color: "#ef4444", label: "Hospital", shape: "cross" as TacticalShape },
    { color: "#06b6d4", label: "Police", shape: "star" as TacticalShape },
    { color: "#ec4899", label: "Meeting", shape: "circle" as TacticalShape },
  ];

  return (
    <div className="bg-slate-900/95 border-t border-white/10 flex flex-wrap gap-x-3 gap-y-1 p-1.5 md:p-2 text-[10px] md:text-[11px] text-slate-400 flex-shrink-0 overflow-x-auto">
      {items.map((item, i) => (
        <div key={i} className="flex items-center gap-1.5 flex-shrink-0">
          {item.dot ? (
            <span className="inline-block rounded-full flex-shrink-0" style={{ width: 8, height: 8, backgroundColor: item.color }} />
          ) : (
            <span
              className="inline-block flex-shrink-0"
              style={{ width: 12, height: 12 }}
              dangerouslySetInnerHTML={{ __html: getTacticalShapeSVG(item.shape!, item.color, 12) }}
            />
          )}
          <span className="truncate">{item.label}</span>
        </div>
      ))}
    </div>
  );
}

function TeamOverviewPanel({
  users,
  expanded,
  onToggle,
  onSelectTeam,
  dbTeams,
  isLoading,
}: {
  users: User[];
  expanded: boolean;
  onToggle: () => void;
  onSelectTeam: (team: Team | any) => void;
  dbTeams: TeamInfo[];
  isLoading: boolean;
}) {
  return (
    <div className="bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden">
      <PanelHeader
        title="Team Overview"
        icon={<FiUsers size={13} />}
        expanded={expanded}
        onToggle={onToggle}
        badge={dbTeams.length || undefined}
      />
      {expanded && (
        <div className="overflow-x-auto custom-scrollbar">
          {/* Loading skeleton */}
          {isLoading && (
            <div className="flex items-center justify-center gap-2 py-6">
              <div className="w-3.5 h-3.5 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
              <span className="text-slate-600 text-[10px]">Loading teams…</span>
            </div>
          )}

          {/* Empty state — backend responded but no teams configured */}
          {!isLoading && dbTeams.length === 0 && (
            <div className="flex flex-col items-center justify-center gap-1.5 py-6 text-slate-600">
              <FiUsers size={18} className="opacity-40" />
              <span className="text-[10px]">No teams in database</span>
              <span className="text-[9px] opacity-60">Create teams via the API or admin panel</span>
            </div>
          )}

          {/* Real team rows from DB */}
          {!isLoading && dbTeams.length > 0 && (
            <table className="w-full text-[10px] md:text-xs border-collapse">
              <thead>
                <tr className="border-b border-white/5">
                  {["Team", "A", "S", "O", "T"].map((h, i) => (
                    <th
                      key={i}
                      title={["Team Name", "Active (has live location)", "Stale (>30s)", "Offline (registered but no data)", "Total registered"][i]}
                      className={`px-1.5 md:px-2 py-1.5 text-slate-500 font-semibold cursor-help ${i === 0 ? "text-left" : "text-center"}`}
                    >
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {dbTeams.map(team => {
                  const locUsers = users.filter(u => u.group === team.name);
                  const a = locUsers.filter(u => u.status === "active").length;
                  const s = locUsers.filter(u => u.status === "stale").length;
                  // Offline = registered members minus those with active/stale locations
                  const o = Math.max(0, team.memberCount - a - s);
                  const total = team.memberCount;
                  return (
                    <tr
                      key={team.id}
                      className="border-b border-white/5 hover:bg-white/5 cursor-pointer transition-colors"
                      onClick={() => onSelectTeam(team.name)}
                    >
                      <td className="px-1.5 md:px-2 py-2">
                        <div className="flex items-center gap-1.5">
                          <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: team.color }} />
                          <span className="text-foreground font-semibold truncate">
                            {team.name.replace(/^Team /i, "")}
                          </span>
                        </div>
                      </td>
                      <td className="text-center text-green-500 font-bold">{a}</td>
                      <td className="text-center text-yellow-500 font-bold">{s}</td>
                      <td className="text-center text-red-400 font-bold">{o}</td>
                      <td className="text-center text-slate-400 font-semibold">{total}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  );
}

function SelectedUserPanel({
  user,
  expanded,
  onToggle,
  onFlag,
  onMessage,
  onCreateRoute,
}: {
  user: User | null;
  expanded: boolean;
  onToggle: () => void;
  onFlag: (userId: string, flag: FlagType | null) => void;
  onMessage: (userId: string) => void;
  onCreateRoute: (userId: string) => void;
}) {
  if (!user) {
    return (
      <div className="bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden">
        <PanelHeader title="Selected Soldier" icon={<FiUser size={13} />} expanded={expanded} onToggle={onToggle} />
        {expanded && (
          <div className="p-4 text-slate-500 text-[11px] text-center">
            <FiCrosshair size={20} className="mx-auto mb-2 opacity-50" />
            Click a soldier marker to select
          </div>
        )}
      </div>
    );
  }

  const col = TEAM_COLORS[user.group].primary;

  return (
    <div className="bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden">
      <PanelHeader title="Selected Soldier" icon={<FiUser size={13} />} expanded={expanded} onToggle={onToggle} />
      {expanded && (
        <div className="p-2.5 md:p-3 custom-scrollbar max-h-[400px] overflow-y-auto">
          <div className="flex items-center gap-2 md:gap-3 mb-3">
            <div
              className="w-9 h-9 md:w-10 md:h-10 rounded-full flex items-center justify-center text-xs md:text-sm font-bold flex-shrink-0"
              style={{ backgroundColor: TEAM_COLORS[user.group].bg, border: `2px solid ${col}`, color: col }}
            >
              {user.name.replace(" ", "").substring(0, 2).toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-foreground font-bold text-xs md:text-sm truncate">{user.name}</div>
              <div className="text-[10px] md:text-xs font-semibold truncate" style={{ color: col }}>
                {user.group} {user.role ? `· ${user.role.toUpperCase()}` : ""}
              </div>
            </div>
            <span
              className="px-1.5 md:px-2 py-0.5 md:py-1 rounded text-[9px] md:text-[10px] font-bold flex-shrink-0"
              style={{ backgroundColor: `${STATUS_COLORS[user.status]}20`, color: STATUS_COLORS[user.status] }}
            >
              {user.status.toUpperCase()}
            </span>
          </div>

          <div className="space-y-1.5 mb-3">
            {[
              { label: "Updated", value: formatElapsed(user.lastUpdate), icon: <FiClock size={11} /> },
              { label: "Speed", value: `${user.speed?.toFixed(1) || "0.0"} km/h`, icon: <FiActivity size={11} /> },
              { label: "Heading", value: `${user.heading || 0}°`, icon: <FiNavigation size={11} /> },
              { label: "Position", value: `${user.lat.toFixed(4)}, ${user.lng.toFixed(4)}`, icon: <FiMapPin size={11} /> },
              { label: "Status", value: user.message || "—", icon: <FiMessageSquare size={11} /> },
            ].map((row, i) => (
              <div key={i} className="flex gap-1.5 text-[10px] md:text-[11px]">
                <span className="text-slate-500 w-3 flex-shrink-0 pt-0.5">{row.icon}</span>
                <span className="text-slate-500 w-16 flex-shrink-0">{row.label}</span>
                <span className="text-slate-400 flex-1 break-all truncate">{row.value}</span>
              </div>
            ))}
          </div>

          {user.flag && (
            <div
              className="my-2 px-2 py-1.5 rounded-md flex items-center gap-1.5 text-[10px] md:text-xs font-semibold"
              style={{ backgroundColor: `${FLAG_COLORS[user.flag].color}20`, border: `1px solid ${FLAG_COLORS[user.flag].color}40`, color: FLAG_COLORS[user.flag].color }}
            >
              {FLAG_COLORS[user.flag].icon}
              <span>{FLAG_COLORS[user.flag].label}</span>
            </div>
          )}

          <div className="flex flex-wrap gap-1.5 mt-3">
            <ActionButton color="#3b82f6" icon={<FiMessageSquare size={10} />} label="MSG" onClick={() => onMessage(user.user_id)} />
            <ActionButton color="#22c55e" icon={<FiCheckCircle size={10} />} label="SAFE" onClick={() => onFlag(user.user_id, "safe")} />
            <ActionButton color="#f59e0b" icon={<FiAlertTriangle size={10} />} label="TBL" onClick={() => onFlag(user.user_id, "trouble")} />
            <ActionButton color="#ef4444" icon={<FiAlertCircle size={10} />} label="SOS" onClick={() => onFlag(user.user_id, "help")} />
            <ActionButton color="#8b5cf6" icon={<TbRoute size={10} />} label="RTE" onClick={() => onCreateRoute(user.user_id)} />
          </div>
        </div>
      )}
    </div>
  );
}

function ActionButton({ color, icon, label, onClick }: { color: string; icon: React.ReactNode; label: string; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="flex items-center gap-1 px-2 py-1.5 rounded text-[9px] md:text-[10px] font-semibold cursor-pointer transition-all hover:opacity-80"
      style={{ backgroundColor: `${color}18`, border: `1px solid ${color}40`, color }}
    >
      {icon} {label}
    </button>
  );
}

function AlertsPanel({
  users,
  expanded,
  onToggle,
  onAlertClick,
}: {
  users: User[];
  expanded: boolean;
  onToggle: () => void;
  onAlertClick?: (user: User) => void;
}) {
  const alerts = useMemo(() => {
    const result: { user: User; msg: string; elapsed: string; severity: "high" | "medium" }[] = [];
    // Only show alerts for users with real names (not raw UUIDs/IDs)
    const isKnownUser = (u: User) => u.name && u.name.length > 2 && !/^[0-9a-f-]{8,}$/i.test(u.name) && u.name !== "Unknown";

    users.filter(u => u.flag === "help" && isKnownUser(u)).forEach(u => {
      result.unshift({ user: u, msg: `${u.name} requested SOS`, elapsed: formatElapsed(u.flagTime || u.lastUpdate), severity: "high" });
    });
    users.filter(u => u.status === "offline" && isKnownUser(u)).forEach(u => {
      result.push({ user: u, msg: `${u.name} is OFFLINE`, elapsed: formatElapsed(u.lastUpdate), severity: "high" });
    });
    users.filter(u => u.status === "stale" && u.flag !== "help" && isKnownUser(u)).forEach(u => {
      const sec = Math.floor((Date.now() - u.lastUpdate.getTime()) / 1000);
      result.push({ user: u, msg: `${u.name} stale ${sec}s`, elapsed: `${sec}s`, severity: "medium" });
    });

    return result;
  }, [users]);

  return (
    <div className="bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden">
      <PanelHeader title="Alerts" icon={<FiBell size={13} />} expanded={expanded} onToggle={onToggle} badge={alerts.length} />
      {expanded && (
        <div className="max-h-52 overflow-y-auto custom-scrollbar">
          {alerts.length === 0 ? (
            <div className="p-4 text-slate-500 text-[11px] text-center">No active alerts</div>
          ) : alerts.map((a, i) => (
            <div key={i} className="px-2.5 py-2 border-b border-white/5 flex items-start gap-2 hover:bg-white/5 transition-colors cursor-pointer" onClick={() => onAlertClick?.(a.user)}>
              <FiAlertTriangle size={11} color={a.severity === "high" ? "#ef4444" : "#f59e0b"} className="mt-0.5 flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="text-foreground text-[11px] font-semibold truncate">{a.msg}</div>
                <div className="text-slate-500 text-[9px] mt-0.5 truncate">{a.user.message}</div>
              </div>
              <span className="text-[10px] font-bold flex-shrink-0" style={{ color: a.severity === "high" ? "#ef4444" : "#f59e0b" }}>
                {a.elapsed}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function SOSIncidentModal({
  incident,
  users,
  onClose,
  onOpenComms,
  onDispatchUnits,
  onFocus,
}: {
  incident: SOSIncident;
  users: User[];
  onClose: () => void;
  onOpenComms: (userId: string) => void;
  onDispatchUnits: (userIds: string[]) => void;
  onFocus: (lat: number, lng: number) => void;
}) {
  const sender = users.find(user => user.user_id === incident.userId) || null;
  const nearbyUnits = useMemo(() => {
    return users
      .filter(user => user.user_id !== incident.userId && user.status !== "offline")
      .map(user => ({
        user,
        distance: distanceKm(incident.lat, incident.lng, user.lat, user.lng),
      }))
      .sort((a, b) => a.distance - b.distance)
      .slice(0, 5);
  }, [incident.lat, incident.lng, incident.userId, users]);

  return (
    <div className="fixed inset-0 bg-black/70 z-5000 flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-slate-900 border border-red-500/40 rounded-xl w-full max-w-130 max-h-[85vh] overflow-y-auto p-5 md:p-6 shadow-2xl animate-fadeIn custom-scrollbar"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-start gap-3 mb-4">
          <div className="w-10 h-10 rounded-full bg-red-500/15 border border-red-500/40 flex items-center justify-center shrink-0">
            <FiAlertCircle size={18} color="#ef4444" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-red-400 text-xs font-semibold tracking-wide">ACTIVE SOS INCIDENT</div>
            <div className="text-foreground text-sm font-bold truncate mt-0.5">{sender?.name || incident.userId}</div>
            <div className="text-slate-400 text-[11px] mt-1">{incident.description}</div>
          </div>
          <button onClick={onClose} className="bg-transparent border-none text-slate-500 hover:text-foreground cursor-pointer text-lg">
            <FiX />
          </button>
        </div>

        <div className="rounded-lg border border-white/10 bg-slate-800/50 p-3 text-[11px] space-y-1.5 mb-4">
          <div className="flex items-center justify-between gap-2">
            <span className="text-slate-400">Sender</span>
            <span className="text-foreground font-semibold truncate">{sender?.name || incident.userId}</span>
          </div>
          <div className="flex items-center justify-between gap-2">
            <span className="text-slate-400">Team</span>
            <span className="text-foreground">{sender?.group || "Unknown"}</span>
          </div>
          <div className="flex items-center justify-between gap-2">
            <span className="text-slate-400">Location</span>
            <button
              onClick={() => onFocus(incident.lat, incident.lng)}
              className="bg-transparent border-none text-blue-400 hover:text-blue-300 cursor-pointer font-semibold"
            >
              {incident.lat.toFixed(5)}, {incident.lng.toFixed(5)}
            </button>
          </div>
          <div className="flex items-center justify-between gap-2">
            <span className="text-slate-400">Raised</span>
            <span className="text-foreground">{formatElapsed(incident.createdAt)}</span>
          </div>
        </div>

        <div className="mb-4">
          <div className="text-slate-300 text-xs font-semibold mb-2">Nearby Units</div>
          {nearbyUnits.length === 0 ? (
            <div className="text-slate-500 text-xs px-1 py-2">No available nearby units</div>
          ) : (
            <div className="space-y-1.5">
              {nearbyUnits.map(({ user, distance }) => (
                <div key={user.user_id} className="rounded-md border border-white/10 bg-slate-800/40 px-2.5 py-2 flex items-center gap-2">
                  <div className="flex-1 min-w-0">
                    <div className="text-foreground text-xs font-semibold truncate">{user.name}</div>
                    <div className="text-slate-400 text-[10px] truncate">{user.group} · {user.status.toUpperCase()}</div>
                  </div>
                  <div className="text-[10px] font-bold text-blue-300 shrink-0">{formatDistance(distance)}</div>
                  <button
                    onClick={() => onOpenComms(user.user_id)}
                    className="px-2 py-1 rounded text-[10px] font-semibold border border-blue-400/40 bg-blue-500/15 text-blue-300 hover:bg-blue-500/25 transition-colors"
                  >
                    Comms
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => onOpenComms(incident.userId)}
            className="flex-1 min-w-37.5 px-3 py-2 rounded-md text-xs font-semibold border border-blue-400/45 bg-blue-500/20 text-blue-300 hover:bg-blue-500/30 transition-colors"
          >
            Open Sender Comms
          </button>
          <button
            onClick={() => onDispatchUnits(nearbyUnits.slice(0, 2).map(item => item.user.user_id))}
            className="flex-1 min-w-37.5 px-3 py-2 rounded-md text-xs font-semibold border border-emerald-400/45 bg-emerald-500/20 text-emerald-300 hover:bg-emerald-500/30 transition-colors"
          >
            Auto-Assign Nearest
          </button>
          <button
            onClick={onClose}
            className="px-3 py-2 rounded-md text-xs font-medium border border-white/15 bg-slate-800 text-slate-300 hover:bg-slate-700/90 transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}

function RoutesPanel({
  routes,
  routeHistory,
  users,
  browserPosition,
  expanded,
  onToggle,
  onCompleteRoute,
}: {
  routes: Route[];
  routeHistory: RouteHistoryItem[];
  users: User[];
  browserPosition: { lat: number; lng: number } | null;
  expanded: boolean;
  onToggle: () => void;
  onCompleteRoute: (routeId: string) => void;
}) {
  const [view, setView] = useState<"active" | "history">("active");
  const activeRoutes = routes.filter(route => route.isActive !== false);

  const routeTarget = (route: Route) => route.waypoints[route.waypoints.length - 1];

  const routeDistance = (route: Route) => {
    const target = routeTarget(route);
    if (!target) return null;
    if (browserPosition) {
      return distanceKm(browserPosition.lat, browserPosition.lng, target.lat, target.lng);
    }
    const scopeUsers = route.assignedTeam && route.assignedTeam !== "ALL"
      ? users.filter(user => user.group === route.assignedTeam)
      : users;
    const nearest = scopeUsers.reduce<number | null>((best, user) => {
      const candidate = distanceKm(user.lat, user.lng, target.lat, target.lng);
      return best == null || candidate < best ? candidate : best;
    }, null);
    return nearest;
  };

  const closestMember = (route: Route) => {
    const target = routeTarget(route);
    if (!target) return null;
    const scopeUsers = route.assignedTeam && route.assignedTeam !== "ALL"
      ? users.filter(user => user.group === route.assignedTeam)
      : users;
    if (scopeUsers.length === 0) return null;
    return scopeUsers.reduce<{ user: User; distance: number } | null>((best, user) => {
      const candidate = distanceKm(user.lat, user.lng, target.lat, target.lng);
      if (!best || candidate < best.distance) return { user, distance: candidate };
      return best;
    }, null);
  };

  return (
    <div className="bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden">
      <PanelHeader title="Routes" icon={<TbRoute size={13} />} expanded={expanded} onToggle={onToggle} badge={activeRoutes.length + routeHistory.length} />
      {expanded && (
        <div className="max-h-64 overflow-y-auto custom-scrollbar p-2">
          <div className="mb-2 flex gap-1 rounded-md bg-white/5 p-1 text-[10px]">
            <button
              onClick={() => setView("active")}
              className="flex-1 rounded px-2 py-1 font-semibold transition-colors"
              style={{ backgroundColor: view === "active" ? "rgba(59,130,246,0.22)" : "transparent", color: view === "active" ? "#60a5fa" : "#94a3b8" }}
            >
              Active
            </button>
            <button
              onClick={() => setView("history")}
              className="flex-1 rounded px-2 py-1 font-semibold transition-colors"
              style={{ backgroundColor: view === "history" ? "rgba(245,158,11,0.22)" : "transparent", color: view === "history" ? "#f59e0b" : "#94a3b8" }}
            >
              History
            </button>
          </div>

          {view === "active" && (activeRoutes.length === 0 ? (
            <div className="p-4 text-slate-500 text-[11px] text-center">No active routes</div>
          ) : activeRoutes.map(route => {
            const target = routeTarget(route);
            const nearest = closestMember(route);
            const distance = routeDistance(route);
            const teamName = route.assignedTeam && route.assignedTeam !== "ALL" ? route.assignedTeam.replace(/^Team\s+/i, "") : "All teams";
            const routeStatus = String(route.routeStatus ?? route.route_status ?? (route.isActive === false ? "completed" : "assigned")).toUpperCase();
            return (
              <div key={route.id} className="mb-2 rounded-md border border-white/5 bg-slate-800/60 p-2 last:mb-0">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-[11px] font-semibold text-foreground truncate">{route.name}</div>
                    <div className="text-[9px] text-slate-500 mt-0.5 truncate">{teamName} · {route.waypoints.length} points</div>
                    <div className="mt-1 inline-flex rounded px-1.5 py-0.5 text-[8px] font-bold tracking-wide bg-blue-500/10 text-blue-300 border border-blue-500/20">{routeStatus}</div>
                  </div>
                  <button
                    onClick={() => onCompleteRoute(route.id)}
                    className="flex-shrink-0 rounded px-2 py-1 text-[9px] font-semibold text-green-300 border border-green-500/30 bg-green-500/10 hover:bg-green-500/20 transition-colors"
                  >
                    Done
                  </button>
                </div>
                <div className="mt-2 space-y-1 text-[9px] text-slate-400">
                  <div>Target: {target ? `${target.lat.toFixed(4)}, ${target.lng.toFixed(4)}` : "No destination"}</div>
                  <div>Distance: {formatDistance(distance)}</div>
                  <div>
                    Closest soldier: {nearest ? `${nearest.user.name} · ${formatDistance(nearest.distance)}` : "No tracked soldiers"}
                  </div>
                </div>
              </div>
            );
          }))}

          {view === "history" && (routeHistory.length === 0 ? (
            <div className="p-4 text-slate-500 text-[11px] text-center">No deleted routes yet</div>
          ) : routeHistory.map(route => {
            const target = routeTarget(route);
            return (
              <div key={`history-${route.id}`} className="mb-2 rounded-md border border-white/5 bg-slate-800/40 p-2 last:mb-0 opacity-90">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-[11px] font-semibold text-foreground truncate">{route.name}</div>
                    <div className="text-[9px] text-slate-500 mt-0.5 truncate">Deleted · {route.waypoints.length} points</div>
                  </div>
                  <span className="flex-shrink-0 rounded px-2 py-1 text-[9px] font-semibold text-amber-300 border border-amber-500/30 bg-amber-500/10">
                    History
                  </span>
                </div>
                <div className="mt-2 space-y-1 text-[9px] text-slate-400">
                  <div>Target: {target ? `${target.lat.toFixed(4)}, ${target.lng.toFixed(4)}` : "No destination"}</div>
                  <div>Deleted at: {route.deletedAt.toLocaleString()}</div>
                </div>
              </div>
            );
          }))}

          {!browserPosition && view === "active" && (
            <div className="mt-2 rounded-md border border-white/5 bg-white/5 p-2 text-[9px] text-slate-500">
              Browser location permission is needed to show commander distance.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function QuickActionsPanel({
  expanded,
  onToggle,
  onExport,
  onRefresh,
  onMessageAll,
  onTeamFilter,
  teamFilter,
  onRouteMode,
  routeDrawMode,
  poiType,
  onPOITypeChange,
  onZoneMode,
  zoneMode,
}: {
  expanded: boolean;
  onToggle: () => void;
  onExport: () => void;
  onRefresh: () => void;
  onMessageAll: () => void;
  onTeamFilter: () => void;
  teamFilter: Team | "All";
  onRouteMode: () => void;
  routeDrawMode: boolean;
  poiType: POIType;
  onPOITypeChange: (type: POIType) => void;
  onZoneMode: () => void;
  zoneMode: boolean;
}) {
  const btns = [
    { icon: <FiFilter size={13} />, label: `Filter: ${teamFilter === "All" ? "All" : teamFilter.replace("Team ", "")}`, action: onTeamFilter },
    { icon: <FiMessageSquare size={13} />, label: "MSG All", action: onMessageAll },
    { icon: <FiDownload size={13} />, label: "Export", action: onExport },
    { icon: <TbRoute size={13} />, label: routeDrawMode ? "Drawing..." : "Draw RTE", action: onRouteMode, active: routeDrawMode },
    { icon: <FiHexagon size={13} />, label: zoneMode ? "Zoning..." : "Zone", action: onZoneMode, active: zoneMode },
    { icon: <FiRefreshCw size={13} />, label: "Refresh", action: onRefresh },
  ];

  const poiTypes: POIType[] = ["checkpoint", "base", "hospital", "observation", "police", "supply", "vehicle", "meeting", "command", "medical", "extraction"];

  return (
    <div className="bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden">
      <PanelHeader title="Quick Actions" icon={<FiZap size={13} />} expanded={expanded} onToggle={onToggle} />
      {expanded && (
        <div className="p-2 custom-scrollbar">
          <div className="grid grid-cols-3 gap-1 mb-2">
            {btns.map((btn, i) => (
              <button
                key={i}
                onClick={btn.action}
                className="flex flex-col items-center gap-1 p-1.5 md:p-2 rounded-md text-[9px] md:text-[10px] font-medium transition-all cursor-pointer"
                style={{
                  backgroundColor: btn.active ? "rgba(59,130,246,0.25)" : "rgba(30,41,59,0.6)",
                  border: btn.active ? "1px solid rgba(59,130,246,0.5)" : "1px solid transparent",
                  color: btn.active ? "#60a5fa" : "#94a3b8",
                }}
              >
                {btn.icon}
                <span className="truncate w-full text-center">{btn.label}</span>
              </button>
            ))}
          </div>

          <div className="pt-2 border-t border-white/5">
            <div className="text-slate-500 text-[9px] md:text-[10px] font-semibold mb-1.5">DEPLOY POI</div>
            <div className="grid grid-cols-4 md:grid-cols-4 gap-1">
              {poiTypes.slice(0, 8).map(type => {
                const info = POI_ICONS_CONFIG[type];
                const isActive = routeDrawMode && poiType === type;
                return (
                  <button
                    key={type}
                    onClick={() => {
                      if (!routeDrawMode) onRouteMode();
                      onPOITypeChange(type);
                    }}
                    className="flex flex-col items-center gap-0.5 p-1.5 rounded-md text-[8px] md:text-[9px] font-medium transition-all cursor-pointer"
                    style={{
                      backgroundColor: isActive ? `${info.color}25` : "rgba(30,41,59,0.4)",
                      border: isActive ? `1px solid ${info.color}50` : "1px solid rgba(255,255,255,0.06)",
                      color: info.color,
                    }}
                    title={info.label}
                  >
                    {info.icon}
                    <span className="truncate w-full text-center">{info.tacticalIcon}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function EventsLog({ events, onViewAll }: { events: Event[]; onViewAll: () => void }) {
  const typeStyle: Record<string, { color: string; bg: string }> = {
    UPDATE: { color: "#22c55e", bg: "rgba(34,197,94,0.12)" },
    STALE: { color: "#f59e0b", bg: "rgba(245,158,11,0.12)" },
    OFFLINE: { color: "#ef4444", bg: "rgba(239,68,68,0.12)" },
    ONLINE: { color: "#22c55e", bg: "rgba(34,197,94,0.12)" },
    MESSAGE: { color: "#3b82f6", bg: "rgba(59,130,246,0.12)" },
    FLAG: { color: "#a855f7", bg: "rgba(168,85,247,0.12)" },
    ROUTE: { color: "#06b6d4", bg: "rgba(6,182,212,0.12)" },
    POI: { color: "#f97316", bg: "rgba(249,115,22,0.12)" },
    ZONE: { color: "#ec4899", bg: "rgba(236,72,153,0.12)" },
    ALERT: { color: "#ef4444", bg: "rgba(239,68,68,0.15)" },
  };

  return (
    <div className="bg-slate-900/95 border-t border-white/10 flex flex-col flex-shrink-0 max-h-48">
      <div className="flex items-center px-3 py-1.5 md:py-2 border-b border-white/5">
        <span className="text-foreground font-bold text-[10px] md:text-[11px] flex-1">Recent Events</span>
        <button onClick={onViewAll} className="bg-transparent border-none text-primary text-[9px] md:text-[10px] cursor-pointer font-semibold hover:underline">
          All Events →
        </button>
      </div>
      <div className="overflow-auto custom-scrollbar flex-1">
        <table className="w-full text-[9px] md:text-[10px] border-collapse">
          <thead>
            <tr className="border-b border-white/5 sticky top-0 bg-slate-900/95">
              {["Time", "Type", "Unit", "Team", "Event"].map((h, i) => (
                <th key={i} className="px-1.5 md:px-2 py-1 md:py-1.5 text-slate-500 font-semibold text-left whitespace-nowrap">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {[...events].reverse().slice(0, 20).map(ev => {
              const ts = typeStyle[ev.type] || { color: "#94a3b8", bg: "transparent" };
              return (
                <tr key={ev.id} className="border-b border-white/3 hover:bg-white/5 transition-colors">
                  <td className="px-1.5 md:px-2 py-1 md:py-1.5 text-slate-500 whitespace-nowrap">{formatTime(ev.time)}</td>
                  <td className="px-1.5 md:px-2 py-1 md:py-1.5">
                    <span className="px-1 py-0.5 rounded text-[8px] md:text-[9px] font-bold whitespace-nowrap" style={{ backgroundColor: ts.bg, color: ts.color }}>
                      {ev.type}
                    </span>
                  </td>
                  <td className="px-1.5 md:px-2 py-1 md:py-1.5 text-foreground font-semibold whitespace-nowrap">{ev.user}</td>
                  <td className="px-1.5 md:px-2 py-1 md:py-1.5 whitespace-nowrap truncate max-w-[60px]" style={{ color: TEAM_COLORS[ev.team].primary }}>{ev.team}</td>
                  <td className="px-1.5 md:px-2 py-1 md:py-1.5 text-slate-400 truncate max-w-[100px]">{ev.event}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function MessageModal({
  toUserId,
  users,
  messages,
  onSend,
  onClose,
}: {
  toUserId: string | null;
  users: User[];
  messages: Message[];
  onSend: (to: string, content: string, priority: "low" | "normal" | "high" | "urgent") => void;
  onClose: () => void;
}) {
  const [text, setText] = useState("");
  const [to, setTo] = useState(toUserId || "ALL");
  const [priority, setPriority] = useState<"low" | "normal" | "high" | "urgent">("normal");
  const relevant = messages.filter(m => m.to === to || m.from === to || m.to === "ALL").slice(-30);

  const priorityColors = {
    low: "text-slate-400",
    normal: "text-foreground",
    high: "text-yellow-500",
    urgent: "text-red-500",
  };

  return (
    <div className="fixed inset-0 bg-black/70 z-[5000] flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-slate-900 border border-white/10 rounded-xl w-full max-w-[460px] max-h-[80vh] flex flex-col shadow-2xl animate-fadeIn"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 px-4 py-3 border-b border-white/10">
          <FiMessageSquare color="#3b82f6" size={15} />
          <span className="text-foreground font-bold text-sm flex-1 truncate">
            {to === "ALL" ? "Broadcast" : users.find(u => u.user_id === to)?.name || to}
          </span>
          <button onClick={onClose} className="bg-transparent border-none text-slate-500 hover:text-foreground cursor-pointer text-lg">
            <FiX />
          </button>
        </div>

        <div className="px-4 py-2.5 border-b border-white/5 flex gap-2">
          <select
            value={to}
            onChange={e => setTo(e.target.value)}
            className="flex-1 bg-slate-800 border border-white/10 rounded-md px-2.5 py-1.5 text-foreground text-xs"
          >
            <option value="ALL">All Users (Broadcast)</option>
            {users.map(u => (
              <option key={u.user_id} value={u.user_id}>{u.name} — {u.group}</option>
            ))}
          </select>
          <select
            value={priority}
            onChange={e => setPriority(e.target.value as any)}
            className="w-20 bg-slate-800 border border-white/10 rounded-md px-1.5 py-1.5 text-xs"
            style={{ color: priorityColors[priority] ? undefined : "#94a3b8" }}
          >
            <option value="low">Low</option>
            <option value="normal">Normal</option>
            <option value="high">High</option>
            <option value="urgent">Urgent</option>
          </select>
        </div>

        <div className="flex-1 overflow-y-auto p-3 flex flex-col gap-2.5 min-h-[200px] max-h-[350px] custom-scrollbar">
          {relevant.length === 0 ? (
            <div className="text-slate-500 text-xs text-center mt-10">No messages</div>
          ) : relevant.map(m => {
            const isMine = m.from === "COMMANDER";
            const senderName = isMine ? "You" : (users.find(u => u.user_id === m.from || u.name === m.from)?.name ?? m.from);
            const initials = senderName.split(" ").map((w: string) => w[0] ?? "").join("").slice(0, 2).toUpperCase() || "??";
            return (
              <div key={m.id} className="flex items-end gap-1.5" style={{ flexDirection: isMine ? "row-reverse" : "row" }}>
                <div
                  className="w-6 h-6 rounded-full shrink-0 flex items-center justify-center text-[8px] font-bold"
                  style={{ backgroundColor: isMine ? "rgba(59,130,246,0.2)" : "rgba(100,116,139,0.3)", border: `1.5px solid ${isMine ? "rgba(59,130,246,0.5)" : "rgba(148,163,184,0.3)"}`, color: isMine ? "#60a5fa" : "#94a3b8" }}
                  title={senderName}
                >
                  {initials}
                </div>
                <div className="flex flex-col max-w-[82%]" style={{ alignItems: isMine ? "flex-end" : "flex-start" }}>
                  <div className="text-[9px] text-slate-500 mb-0.5 flex items-center gap-1">
                    <span className="font-medium" style={{ color: isMine ? "#60a5fa" : "#94a3b8" }}>{senderName}</span>
                    · {formatElapsed(m.time)}
                    {m.priority && m.priority !== "normal" && (
                      <span className={`text-[8px] font-bold ${m.priority === "urgent" ? "text-red-500" : m.priority === "high" ? "text-yellow-500" : "text-slate-400"}`}>
                        {m.priority.toUpperCase()}
                      </span>
                    )}
                  </div>
                  <div
                    className="px-3 py-2 rounded-lg text-xs"
                    style={{
                      backgroundColor: isMine ? "rgba(59,130,246,0.2)" : "rgba(51,65,85,0.6)",
                      border: `1px solid ${isMine ? "rgba(59,130,246,0.4)" : "rgba(255,255,255,0.08)"}`,
                      color: "#e2e8f0",
                    }}
                  >
                    {m.content}
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        <div className="p-3 border-t border-white/10 flex gap-2">
          <input
            value={text}
            onChange={e => setText(e.target.value)}
            onKeyDown={e => { if (e.key === "Enter" && text.trim()) { onSend(to, text.trim(), priority); setText(""); } }}
            placeholder="Type message..."
            className="flex-1 bg-slate-800 border border-white/10 rounded-md px-3 py-2 text-foreground text-xs"
          />
          <button
            onClick={() => { if (text.trim()) { onSend(to, text.trim(), priority); setText(""); } }}
            className="bg-primary border-none rounded-md px-3 py-2 text-white cursor-pointer flex items-center gap-1.5 text-xs font-semibold hover:opacity-90"
          >
            <FiSend size={12} /> Send
          </button>
        </div>
      </div>
    </div>
  );
}

function CommsPanel({
  messages,
  users,
  expanded,
  onToggle,
  onSend,
}: {
  messages: Message[];
  users: User[];
  expanded: boolean;
  onToggle: () => void;
  onSend: (to: string, content: string, priority: "low" | "normal" | "high" | "urgent") => void;
}) {
  const [text, setText] = useState("");
  const [to, setTo] = useState("ALL");
  const [priority, setPriority] = useState<"low" | "normal" | "high" | "urgent">("normal");
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const unread = messages.filter(m => !m.read).length;

  useEffect(() => {
    if (expanded && messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, expanded]);

  const handleSend = () => {
    if (!text.trim()) return;
    onSend(to, text.trim(), priority);
    setText("");
  };

  const priorityColors: Record<string, string> = {
    low: "#94a3b8",
    normal: "#e2e8f0",
    high: "#f59e0b",
    urgent: "#ef4444",
  };

  return (
    <div className="bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden">
      <PanelHeader
        title="COMMS"
        icon={<FiMessageSquare size={13} />}
        expanded={expanded}
        onToggle={onToggle}
        badge={unread}
      />
      {expanded && (
        <div className="flex flex-col" style={{ maxHeight: 340 }}>
          {/* Recipient + priority selectors */}
          <div className="flex gap-1.5 p-2 border-b border-white/5">
            <select
              value={to}
              onChange={e => setTo(e.target.value)}
              className="flex-1 bg-slate-800 border border-white/10 rounded px-2 py-1 text-foreground text-[10px] min-w-0"
            >
              <option value="ALL">Broadcast — All</option>
              {users.map(u => (
                <option key={u.user_id} value={u.user_id}>{u.name}</option>
              ))}
            </select>
            <select
              value={priority}
              onChange={e => setPriority(e.target.value as "low" | "normal" | "high" | "urgent")}
              className="w-16 bg-slate-800 border border-white/10 rounded px-1 py-1 text-[10px]"
              style={{ color: priorityColors[priority] }}
            >
              <option value="low">Low</option>
              <option value="normal">Norm</option>
              <option value="high">High</option>
              <option value="urgent">URGENT</option>
            </select>
          </div>

          {/* Messages list */}
          <div className="flex-1 overflow-y-auto custom-scrollbar p-2 flex flex-col gap-2 min-h-[120px]">
            {messages.length === 0 ? (
              <div className="text-slate-500 text-[10px] text-center mt-4">No messages</div>
            ) : (
              messages.slice(-40).map(m => {
                const isFromCommander = m.from === "COMMANDER";
                const sender = isFromCommander ? null : users.find(u => u.user_id === m.from || u.name === m.from);
                const senderName = isFromCommander ? "You" : (sender?.name ?? m.from);
                const initials = senderName.split(" ").map(w => w[0] ?? "").join("").slice(0, 2).toUpperCase() || "??";
                const teamColor = sender ? TEAM_COLORS[sender.group]?.primary : "#3b82f6";
                return (
                  <div key={m.id} className="flex items-end gap-1.5" style={{ flexDirection: isFromCommander ? "row-reverse" : "row" }}>
                    {/* Avatar */}
                    <div
                      className="w-6 h-6 rounded-full shrink-0 flex items-center justify-center text-[8px] font-bold"
                      style={{
                        backgroundColor: isFromCommander ? "rgba(59,130,246,0.2)" : `${teamColor}20`,
                        border: `1.5px solid ${isFromCommander ? "rgba(59,130,246,0.5)" : `${teamColor}60`}`,
                        color: isFromCommander ? "#60a5fa" : teamColor,
                      }}
                      title={senderName}
                    >
                      {initials}
                    </div>
                    <div className="flex flex-col max-w-[80%]" style={{ alignItems: isFromCommander ? "flex-end" : "flex-start" }}>
                      <div className="text-[8px] text-slate-500 mb-0.5 flex items-center gap-1">
                        <span className="font-medium" style={{ color: isFromCommander ? "#60a5fa" : teamColor }}>{senderName}</span>
                        <span>·</span>
                        <span>{formatElapsed(m.time)}</span>
                        {m.priority && m.priority !== "normal" && (
                          <span className="font-bold" style={{ color: priorityColors[m.priority] }}>
                            {m.priority.toUpperCase()}
                          </span>
                        )}
                      </div>
                      <div
                        className="px-2.5 py-1.5 rounded-lg text-[11px]"
                        style={{
                          backgroundColor: isFromCommander ? "rgba(59,130,246,0.18)" : "rgba(30,41,59,0.7)",
                          border: `1px solid ${isFromCommander ? "rgba(59,130,246,0.35)" : "rgba(255,255,255,0.07)"}`,
                          color: "#e2e8f0",
                        }}
                      >
                        {!isFromCommander && (
                          <span className="text-[8px] font-bold block mb-0.5" style={{ color: m.to === "ALL" ? "#94a3b8" : "#60a5fa" }}>
                            {m.to === "ALL" ? "→ ALL" : `→ ${users.find(u => u.user_id === m.to)?.name ?? m.to}`}
                          </span>
                        )}
                        {m.content}
                      </div>
                    </div>
                  </div>
                );
              })
            )}
            <div ref={messagesEndRef} />
          </div>

          {/* Send bar */}
          <div className="flex gap-1.5 p-2 border-t border-white/5">
            <input
              value={text}
              onChange={e => setText(e.target.value)}
              onKeyDown={e => { if (e.key === "Enter") handleSend(); }}
              placeholder="Message units…"
              className="flex-1 bg-slate-800 border border-white/10 rounded px-2.5 py-1.5 text-foreground text-[11px] min-w-0"
            />
            <button
              onClick={handleSend}
              className="bg-primary border-none rounded px-2.5 py-1.5 text-white cursor-pointer flex items-center gap-1 text-[10px] font-semibold hover:opacity-90 flex-shrink-0"
            >
              <FiSend size={11} />
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function POIVisibilityModal({
  poi,
  users,
  dbTeams,
  onSave,
  onClose,
}: {
  poi: POI;
  users: User[];
  dbTeams: TeamInfo[];
  onSave: (poi: POI) => void;
  onClose: () => void;
}) {
  const [visibleTo, setVisibleTo] = useState<string[]>(poi.visibleTo);
  const [shape, setShape] = useState<TacticalShape>(poi.shape || "diamond");
  const shapes: TacticalShape[] = ["circle", "square", "triangle", "diamond", "hexagon", "star", "cross"];

  const toggleVisibility = (value: string) => {
    if (visibleTo.includes(value)) {
      setVisibleTo(visibleTo.filter(v => v !== value));
    } else {
      setVisibleTo([...visibleTo, value]);
    }
  };

  const handleSave = () => {
    onSave({ ...poi, visibleTo, shape });
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-black/70 z-[5000] flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-slate-900 border border-white/10 rounded-xl w-full max-w-[460px] max-h-[80vh] overflow-y-auto p-5 md:p-6 shadow-2xl animate-fadeIn custom-scrollbar"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 mb-4">
          <FiEye color="#3b82f6" size={16} />
          <span className="text-foreground font-bold text-sm">POI Configuration</span>
        </div>

        <div className="mb-4">
          <div className="text-slate-400 text-xs mb-1">
            {POI_ICONS_CONFIG[poi.type].icon} {poi.label}
          </div>
          <div className="text-slate-500 text-[10px]">Position: {poi.lat.toFixed(4)}, {poi.lng.toFixed(4)}</div>
        </div>

        <div className="mb-4">
          <div className="text-slate-400 text-[11px] mb-2 font-medium">Tactical Shape</div>
          <div className="flex flex-wrap gap-1.5">
            {shapes.map(s => (
              <button
                key={s}
                onClick={() => setShape(s)}
                className="w-9 h-9 rounded flex items-center justify-center cursor-pointer transition-all"
                style={{
                  backgroundColor: shape === s ? "rgba(59,130,246,0.25)" : "rgba(30,41,59,0.4)",
                  border: shape === s ? "2px solid rgba(59,130,246,0.6)" : "1px solid rgba(255,255,255,0.1)",
                }}
                dangerouslySetInnerHTML={{ __html: getTacticalShapeSVG(s, shape === s ? "#60a5fa" : "#94a3b8", 24) }}
              />
            ))}
          </div>
        </div>

        {dbTeams.length > 0 && (
          <div className="mb-4">
            <div className="text-slate-400 text-[11px] mb-2 font-medium">Visible To Teams</div>
            <div className="flex flex-wrap gap-1.5">
              {dbTeams.map(team => (
                <button
                  key={team.id}
                  onClick={() => toggleVisibility(team.id)}
                  className="px-2.5 py-1.5 rounded-md text-[10px] md:text-[11px] font-semibold cursor-pointer transition-all"
                  style={{
                    backgroundColor: visibleTo.includes(team.id) ? "rgba(59,130,246,0.25)" : "rgba(30,41,59,0.6)",
                    border: visibleTo.includes(team.id) ? "1px solid rgba(59,130,246,0.5)" : "1px solid rgba(255,255,255,0.1)",
                    color: visibleTo.includes(team.id) ? "#60a5fa" : "#94a3b8",
                  }}
                >
                  {team.name.replace(/^Team\s+/i, "")}
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="mb-4">
          <div className="text-slate-400 text-[11px] mb-2 font-medium">Visible To Individuals</div>
          <div className="flex flex-wrap gap-1.5 max-h-28 overflow-y-auto custom-scrollbar">
            {users.map(user => (
              <button
                key={user.user_id}
                onClick={() => toggleVisibility(user.user_id)}
                className="px-2 py-1 rounded-md text-[9px] md:text-[10px] font-medium cursor-pointer transition-all"
                style={{
                  backgroundColor: visibleTo.includes(user.user_id) ? "rgba(34,197,94,0.2)" : "rgba(30,41,59,0.4)",
                  border: visibleTo.includes(user.user_id) ? "1px solid rgba(34,197,94,0.5)" : "1px solid rgba(255,255,255,0.08)",
                  color: visibleTo.includes(user.user_id) ? "#22c55e" : "#94a3b8",
                }}
              >
                {user.name}
              </button>
            ))}
          </div>
        </div>

        <div className="flex gap-2">
          <button
            onClick={onClose}
            className="flex-1 px-3 py-2.5 bg-slate-800 border border-white/10 rounded-md text-slate-400 cursor-pointer text-xs font-medium hover:bg-slate-700"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            className="flex-1 px-4 py-2.5 bg-primary border-none rounded-md text-white cursor-pointer text-xs font-semibold hover:opacity-90"
          >
            <FiCheck size={12} className="inline mr-1" /> Save
          </button>
        </div>
      </div>
    </div>
  );
}

function RouteModal({
  pendingRoute,
  users,
  dbTeams,
  onAssign,
  onCancel,
}: {
  pendingRoute: Waypoint[];
  users: User[];
  dbTeams: TeamInfo[];
  onAssign: (name: string, assignedTo: string, assignedTeam: string, meetingPoint: boolean, visibleTo: string[], isZone: boolean, zoneType: Route["zoneType"]) => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState("Route Alpha");
  const [assignedTo, setAssignedTo] = useState("ALL");
  const [assignedTeam, setAssignedTeam] = useState<string>("ALL");
  const [meetingPoint, setMeetingPoint] = useState(false);
  const [visibleTo, setVisibleTo] = useState<string[]>(["ALL"]);
  const [isZone, setIsZone] = useState(false);
  const [zoneType, setZoneType] = useState<Route["zoneType"]>("perimeter");
  const [meetingTeams, setMeetingTeams] = useState<string[]>([]);

  const zoneTypes: Route["zoneType"][] = ["perimeter", "sector", "corridor", "extraction"];

  const toggleVisibility = (value: string) => {
    if (visibleTo.includes(value)) setVisibleTo(visibleTo.filter(v => v !== value));
    else setVisibleTo([...visibleTo, value]);
  };

  const toggleMeetingTeam = (team: string) => {
    if (meetingTeams.includes(team)) setMeetingTeams(meetingTeams.filter(t => t !== team));
    else setMeetingTeams([...meetingTeams, team]);
  };

  return (
    <div className="fixed inset-0 bg-black/70 z-[5000] flex items-center justify-center p-4" onClick={onCancel}>
      <div
        className="bg-slate-900 border border-white/10 rounded-xl w-full max-w-[480px] max-h-[85vh] overflow-y-auto p-5 md:p-6 shadow-2xl animate-fadeIn custom-scrollbar"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 mb-4">
          {isZone ? <FiHexagon color="#ec4899" size={18} /> : <TbRoute color="#3b82f6" size={18} />}
          <span className="text-foreground font-bold text-sm">{isZone ? "Define Zone" : "Assign Route"}</span>
        </div>

        <div className="text-slate-500 text-xs mb-4">{pendingRoute.length} waypoints</div>

        <div className="mb-3">
          <label className="flex items-center gap-2 text-slate-400 text-xs cursor-pointer mb-3">
            <input
              type="checkbox"
              checked={isZone}
              onChange={e => setIsZone(e.target.checked)}
              className="w-4 h-4 accent-pink-500"
            />
            <FiHexagon size={14} color="#ec4899" />
            <span>This is a Zone (area control)</span>
          </label>

          {isZone && (
            <div className="mb-3 pl-6">
              <label className="text-slate-400 text-[11px] block mb-1.5 font-medium">Zone Type</label>
              <div className="flex flex-wrap gap-1.5">
                {zoneTypes.map(zt => (
                  <button
                    key={zt}
                    onClick={() => setZoneType(zt)}
                    className="px-3 py-1.5 rounded-md text-[11px] font-semibold cursor-pointer capitalize transition-all"
                    style={{
                      backgroundColor: zoneType === zt ? "rgba(236,72,153,0.25)" : "rgba(30,41,59,0.6)",
                      border: zoneType === zt ? "1px solid rgba(236,72,153,0.5)" : "1px solid rgba(255,255,255,0.06)",
                      color: zoneType === zt ? "#ec4899" : "#94a3b8",
                    }}
                  >
                    {zt}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="mb-3">
          <label className="text-slate-400 text-[11px] block mb-1.5 font-medium">Name</label>
          <input
            value={name}
            onChange={e => setName(e.target.value)}
            className="w-full bg-slate-800 border border-white/10 rounded-md px-3 py-2 text-foreground text-xs"
          />
        </div>

        {dbTeams.length > 0 && (
          <div className="mb-3">
            <label className="text-slate-400 text-[11px] block mb-1.5 font-medium">Assign To Team</label>
            <div className="flex flex-wrap gap-1.5">
              <button
                onClick={() => setAssignedTeam("ALL")}
                className="px-2.5 py-1.5 rounded-md text-[10px] md:text-[11px] font-semibold cursor-pointer transition-all"
                style={{
                  backgroundColor: assignedTeam === "ALL" ? "rgba(59,130,246,0.25)" : "rgba(30,41,59,0.6)",
                  border: assignedTeam === "ALL" ? "1px solid rgba(59,130,246,0.5)" : "1px solid rgba(255,255,255,0.06)",
                  color: assignedTeam === "ALL" ? "#60a5fa" : "#94a3b8",
                }}
              >
                All
              </button>
              {dbTeams.map(team => (
                <button
                  key={team.id}
                  onClick={() => setAssignedTeam(team.id)}
                  className="px-2.5 py-1.5 rounded-md text-[10px] md:text-[11px] font-semibold cursor-pointer transition-all"
                  style={{
                    backgroundColor: assignedTeam === team.id ? "rgba(59,130,246,0.25)" : "rgba(30,41,59,0.6)",
                    border: assignedTeam === team.id ? "1px solid rgba(59,130,246,0.5)" : "1px solid rgba(255,255,255,0.06)",
                    color: assignedTeam === team.id ? "#60a5fa" : "#94a3b8",
                  }}
                >
                  {team.name.replace(/^Team\s+/i, "")}
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="mb-3">
          <label className="text-slate-400 text-[11px] block mb-1.5 font-medium">Assign To Soldier</label>
          <select
            value={assignedTo}
            onChange={e => setAssignedTo(e.target.value)}
            className="w-full bg-slate-800 border border-white/10 rounded-md px-3 py-2 text-foreground text-xs"
          >
            <option value="ALL">All Soldiers</option>
            {users.map(u => (
              <option key={u.user_id} value={u.user_id}>{u.name} — {u.group}</option>
            ))}
          </select>
        </div>

        <div className="mb-3">
          <label className="flex items-center gap-2 text-slate-400 text-xs cursor-pointer">
            <input
              type="checkbox"
              checked={meetingPoint}
              onChange={e => setMeetingPoint(e.target.checked)}
              className="w-4 h-4 accent-blue-500"
            />
            <FiUsers size={14} color="#ec4899" />
            <span>Meeting Point (multiple teams converge)</span>
          </label>
        </div>

        {meetingPoint && (
          <div className="mb-3 pl-6">
            <div className="flex flex-wrap gap-1.5">
              {dbTeams.map(team => (
                <button
                  key={team.id}
                  onClick={() => toggleMeetingTeam(team.id)}
                  className="px-2.5 py-1.5 rounded-md text-[10px] font-semibold cursor-pointer transition-all"
                  style={{
                    backgroundColor: meetingTeams.includes(team.id) ? "rgba(236,72,153,0.25)" : "rgba(30,41,59,0.6)",
                    border: meetingTeams.includes(team.id) ? "1px solid rgba(236,72,153,0.5)" : "1px solid rgba(255,255,255,0.06)",
                    color: meetingTeams.includes(team.id) ? "#ec4899" : "#94a3b8",
                  }}
                >
                  {team.name.replace(/^Team\s+/i, "")}
                </button>
              ))}
            </div>
          </div>
        )}

        {dbTeams.length > 0 && (
          <div className="mb-4">
            <label className="text-slate-400 text-[11px] block mb-1.5 font-medium">Visible To</label>
            <div className="flex flex-wrap gap-1.5">
              <button
                onClick={() => toggleVisibility("ALL")}
                className="px-2.5 py-1.5 rounded-md text-[10px] font-semibold cursor-pointer transition-all"
                style={{
                  backgroundColor: visibleTo.includes("ALL") ? "rgba(59,130,246,0.25)" : "rgba(30,41,59,0.6)",
                  border: visibleTo.includes("ALL") ? "1px solid rgba(59,130,246,0.5)" : "1px solid rgba(255,255,255,0.1)",
                  color: visibleTo.includes("ALL") ? "#60a5fa" : "#94a3b8",
                }}
              >
                All
              </button>
              {dbTeams.map(team => (
                <button
                  key={team.id}
                  onClick={() => toggleVisibility(team.id)}
                  className="px-2.5 py-1.5 rounded-md text-[10px] font-semibold cursor-pointer transition-all"
                  style={{
                    backgroundColor: visibleTo.includes(team.id) ? "rgba(59,130,246,0.25)" : "rgba(30,41,59,0.6)",
                    border: visibleTo.includes(team.id) ? "1px solid rgba(59,130,246,0.5)" : "1px solid rgba(255,255,255,0.1)",
                    color: visibleTo.includes(team.id) ? "#60a5fa" : "#94a3b8",
                  }}
                >
                  {team.name.replace(/^Team\s+/i, "")}
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="flex gap-2">
          <button onClick={onCancel} className="flex-1 px-3 py-2.5 bg-slate-800 border border-white/10 rounded-md text-slate-400 cursor-pointer text-xs font-medium hover:bg-slate-700">
            Cancel
          </button>
          <button
            onClick={() => onAssign(name, assignedTo, assignedTeam, meetingPoint, visibleTo, isZone, isZone ? zoneType : undefined)}
            className="flex-1 px-4 py-2.5 bg-primary border-none rounded-md text-white cursor-pointer text-xs font-semibold hover:opacity-90"
          >
            <FiCheck size={12} className="inline mr-1" />
            {isZone ? "Define Zone" : "Assign Route"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────── FORCE MANAGEMENT ───────────────────────────

const ROLE_LABELS: Record<string, string> = {
  super_admin: "Super Admin", admin: "Admin", commander: "Commander",
  operator: "Operator", field_unit: "Field Unit", viewer: "Viewer",
};
const ROLE_COLORS: Record<string, string> = {
  super_admin: "#ef4444", admin: "#f97316", commander: "#8b5cf6",
  operator: "#3b82f6", field_unit: "#22c55e", viewer: "#94a3b8",
};
const ROLE_GUIDE = [
  { role: "field_unit", color: "#22c55e", icon: <FiUser size={16} />, label: "Soldier", desc: "Deployed soldier. Sends live GPS every 5 s, can trigger SOS, mark enemy positions, receive routes from command." },
  { role: "commander", color: "#8b5cf6", icon: <FiShield size={16} />, label: "Commander", desc: "Full operational control. Draws routes & zones, manages teams, assigns missions, broadcasts messages, views all units." },
  { role: "operator", color: "#3b82f6", icon: <FiSettings size={16} />, label: "Operator", desc: "Mission operations. Assigns tasks, monitors unit status, manages communications, generates reports." },
  { role: "admin", color: "#f97316", icon: <FiLock size={16} />, label: "Admin", desc: "System administrator. Creates & manages all user accounts, system configuration, access control." },
  { role: "super_admin", color: "#ef4444", icon: <FiShield size={16} />, label: "Super Admin", desc: "Unrestricted access. All admin + commander + operator capabilities combined." },
  { role: "viewer", color: "#94a3b8", icon: <FiEye size={16} />, label: "Viewer", desc: "Read-only. Can see the map, unit positions, events and reports — cannot interact or send any commands." },
];

function RolesGuideModal({ onClose }: { onClose: () => void }) {
  return (
    <div className="fixed inset-0 bg-black/75 z-[5000] flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-slate-900 border border-white/10 rounded-xl w-full max-w-[480px] max-h-[85vh] overflow-y-auto shadow-2xl"
        onClick={e => e.stopPropagation()}
        style={{ fontFamily: "'Poppins', sans-serif" }}
      >
        <div className="flex items-center gap-2 px-5 py-4 border-b border-white/8 sticky top-0 bg-slate-900">
          <FiShield size={15} color="#3b82f6" />
          <span className="text-foreground font-bold text-sm flex-1">User Roles Guide</span>
          <button onClick={onClose} className="text-slate-500 hover:text-white transition-colors bg-transparent border-none cursor-pointer">
            <FiX size={16} />
          </button>
        </div>
        <div className="p-4 flex flex-col gap-3">
          {ROLE_GUIDE.map(({ role, color, icon, label, desc }) => (
            <div key={role} className="flex gap-3 p-3 rounded-lg"
              style={{ backgroundColor: `${color}0c`, border: `1px solid ${color}22` }}>
              <div className="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center text-base"
                style={{ backgroundColor: `${color}18`, border: `1.5px solid ${color}50` }}>
                {icon}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs font-bold" style={{ color }}>{label}</span>
                  <span className="text-[9px] font-bold px-1.5 py-0.5 rounded tracking-wide"
                    style={{ backgroundColor: `${color}18`, color, letterSpacing: "0.5px" }}>
                    {role.toUpperCase().replace("_", " ")}
                  </span>
                </div>
                <p className="text-slate-400 text-[10px] leading-relaxed">{desc}</p>
              </div>
            </div>
          ))}
          <div className="mt-1 px-3 py-2.5 rounded-lg text-[10px] text-slate-500 leading-relaxed"
            style={{ backgroundColor: "rgba(30,41,59,0.6)", border: "1px solid rgba(255,255,255,0.05)" }}>
            <strong className="text-slate-400">Tip:</strong> Always assign soldiers as <span className="text-green-400 font-semibold">Soldier</span> role so they appear on the tactical map and can send real-time location data. Commanders and operators do not transmit GPS.
          </div>
        </div>
      </div>
    </div>
  );
}

function ForceManagementPanel({
  expanded, onToggle, allUsers, dbTeams, isLoading,
  onCreateUser, onCreateTeam, onAssignTeam, onRemoveFromTeam, onLocate,
}: {
  expanded: boolean; onToggle: () => void;
  allUsers: UserRecord[]; dbTeams: TeamInfo[]; isLoading: boolean;
  onCreateUser: () => void; onCreateTeam: () => void;
  onAssignTeam: (userId: string) => void;
  onRemoveFromTeam: (userId: string, teamId: string) => void;
  onLocate: (userId: string) => void;
}) {
  const [search, setSearch] = useState("");
  const [showRolesGuide, setShowRolesGuide] = useState(false);

  const fieldUnits = allUsers.filter(u => {
    const q = search.toLowerCase();
    const matchSearch = !q || u.full_name.toLowerCase().includes(q) || u.username.toLowerCase().includes(q);
    return u.role === "field_unit" && matchSearch;
  });

  const unassigned = fieldUnits.filter(u => !u.teamId);

  return (
    <div className="bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden">
      <PanelHeader
        title="Force Management"
        icon={<FiShield size={13} />}
        expanded={expanded}
        onToggle={onToggle}
        badge={fieldUnits.length || undefined}
      />
      {expanded && (
        <div className="flex flex-col gap-2 p-2 custom-scrollbar max-h-[500px] overflow-y-auto">
          {showRolesGuide && <RolesGuideModal onClose={() => setShowRolesGuide(false)} />}

          {/* Action buttons */}
          <div className="flex gap-1.5">
            <button
              onClick={onCreateUser}
              className="flex-1 flex items-center justify-center gap-1 px-2 py-1.5 rounded text-[10px] font-semibold cursor-pointer transition-all hover:opacity-80"
              style={{ backgroundColor: "rgba(34,197,94,0.15)", border: "1px solid rgba(34,197,94,0.4)", color: "#22c55e" }}
            >
              <FiPlus size={11} /> ADD SOLDIER
            </button>
            <button
              onClick={onCreateTeam}
              className="flex-1 flex items-center justify-center gap-1 px-2 py-1.5 rounded text-[10px] font-semibold cursor-pointer transition-all hover:opacity-80"
              style={{ backgroundColor: "rgba(59,130,246,0.15)", border: "1px solid rgba(59,130,246,0.4)", color: "#3b82f6" }}
            >
              <FiPlus size={11} /> NEW TEAM
            </button>
            <button
              onClick={() => setShowRolesGuide(true)}
              title="View roles guide"
              className="flex items-center justify-center w-8 rounded text-[11px] font-bold cursor-pointer transition-all hover:opacity-80 flex-shrink-0"
              style={{ backgroundColor: "rgba(148,163,184,0.1)", border: "1px solid rgba(148,163,184,0.2)", color: "#94a3b8" }}
            >
              ?
            </button>
          </div>

          {unassigned.length > 0 && (
            <div className="rounded-md px-2 py-2" style={{ backgroundColor: "rgba(34,197,94,0.08)", border: "1px solid rgba(34,197,94,0.18)" }}>
              <div className="flex items-center justify-between gap-2 mb-1.5">
                <div className="text-[10px] font-semibold text-green-400 uppercase tracking-wider">Available Soldiers</div>
                <div className="text-[9px] text-slate-500">Ready to assign</div>
              </div>
              <div className="flex flex-wrap gap-1">
                {unassigned.slice(0, 12).map(u => (
                  <button
                    key={u.id}
                    onClick={() => onAssignTeam(u.id)}
                    className="px-2 py-1 rounded text-[10px] font-semibold cursor-pointer transition-colors hover:opacity-90"
                    style={{ backgroundColor: "rgba(15,23,42,0.9)", border: "1px solid rgba(34,197,94,0.25)", color: "#d1fae5" }}
                    title="Assign to team"
                  >
                    {u.full_name}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Unassigned alert */}
          {unassigned.length > 0 && (
            <div className="flex items-center gap-1.5 px-2 py-1.5 rounded text-[10px]"
              style={{ backgroundColor: "rgba(245,158,11,0.1)", border: "1px solid rgba(245,158,11,0.25)", color: "#f59e0b" }}>
              <FiAlertTriangle size={11} />
              {unassigned.length} soldier{unassigned.length > 1 ? "s" : ""} unassigned
            </div>
          )}

          {/* Search */}
          <div className="flex gap-1">
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Search field units…"
              className="flex-1 bg-slate-800 border border-white/8 rounded px-2 py-1 text-foreground text-[10px] focus:outline-none focus:border-primary/40"
            />
          </div>

          {isLoading ? (
            <div className="text-center py-4 text-slate-600 text-[10px]">Loading soldiers…</div>
          ) : fieldUnits.length === 0 ? (
            <div className="text-center py-4 text-slate-600 text-[10px]">No soldiers found</div>
          ) : (
            <div className="flex flex-col gap-1">
              {fieldUnits.map(u => {
                const roleColor = ROLE_COLORS[u.role] ?? "#94a3b8";
                const teamColor = dbTeams.find(t => t.id === u.teamId)?.color;
                return (
                  <div key={u.id} className="flex items-center gap-2 px-2 py-2 rounded border border-white/5 hover:bg-white/4 transition-colors"
                    style={{ backgroundColor: "rgba(30,41,59,0.5)" }}>
                    {/* Avatar */}
                    <div className="w-7 h-7 rounded-full flex-shrink-0 flex items-center justify-center text-[9px] font-bold"
                      style={{ backgroundColor: `${roleColor}18`, border: `1.5px solid ${roleColor}50`, color: roleColor }}>
                      {u.full_name.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase()}
                    </div>
                    {/* Info */}
                    <div className="flex-1 min-w-0">
                      <div className="text-foreground text-[10px] font-semibold truncate">{u.full_name}</div>
                      <div className="flex items-center gap-1 mt-0.5">
                        <span className="text-[8px] font-bold px-1 rounded" style={{ backgroundColor: `${roleColor}18`, color: roleColor }}>
                          {ROLE_LABELS[u.role] ?? u.role}
                        </span>
                        {u.teamName && (
                          <span className="text-[8px] font-bold px-1 rounded truncate"
                            style={{ backgroundColor: `${teamColor ?? "#94a3b8"}18`, color: teamColor ?? "#94a3b8" }}>
                            {u.teamName.replace("Team ", "")}
                          </span>
                        )}
                        {!u.is_active && (
                          <span className="text-[8px] px-1 rounded" style={{ backgroundColor: "rgba(239,68,68,0.1)", color: "#ef4444" }}>
                            INACTIVE
                          </span>
                        )}
                      </div>
                    </div>
                    {/* Actions */}
                    <div className="flex gap-1">
                      <button onClick={() => onLocate(u.id)} title="Locate on map"
                        className="w-5 h-5 flex items-center justify-center text-slate-500 hover:text-primary transition-colors">
                        <FiCrosshair size={11} />
                      </button>
                      {!u.teamId ? (
                        <button onClick={() => onAssignTeam(u.id)} title="Assign to team"
                          className="w-5 h-5 flex items-center justify-center text-slate-500 hover:text-green-400 transition-colors">
                          <FiPlus size={11} />
                        </button>
                      ) : (
                        <button onClick={() => onRemoveFromTeam(u.id, u.teamId!)} title="Remove from team"
                          className="w-5 h-5 flex items-center justify-center text-slate-500 hover:text-red-400 transition-colors">
                          <FiMinus size={11} />
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function CreateUserModal({
  dbTeams, onClose, onSaved,
}: {
  dbTeams: TeamInfo[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    username: "", full_name: "", email: "", password: "",
    role: "field_unit", phone: "", team_id: "",
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const handleSave = async () => {
    if (!form.username || !form.full_name || !form.email || !form.password) {
      setError("Username, name, email and password are required."); return;
    }
    setSaving(true); setError("");
    try {
      await api.createUser({
        username: form.username, full_name: form.full_name,
        email: form.email, password: form.password,
        role: "field_unit", phone: form.phone || undefined,
        team_id: form.team_id || undefined,
        team_role: form.team_id ? "support" : undefined,
      });
      onSaved(); onClose();
    } catch (e: unknown) {
      // Log full error for debugging and show a more informative message
      // eslint-disable-next-line no-console
      console.error("createUser error:", e);
      const resp = (e as { response?: { data?: any } })?.response?.data;
      const detail = resp?.detail ?? resp ?? null;
      setError(String(detail ?? "Failed to create soldier."));
    }
    setSaving(false);
  };

  const field = (label: string, key: keyof typeof form, type = "text", placeholder = "") => (
    <div>
      <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1">{label}</label>
      <input
        type={type} value={form[key]} placeholder={placeholder}
        onChange={e => setForm(p => ({ ...p, [key]: e.target.value }))}
        className="w-full bg-slate-800 border border-white/8 rounded-md px-2.5 py-2 text-foreground text-xs focus:outline-none focus:border-primary/50"
      />
    </div>
  );

  return (
    <div className="fixed inset-0 bg-black/75 z-[5000] flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-slate-900 border border-white/10 rounded-xl w-full max-w-[420px] shadow-2xl p-5 flex flex-col gap-3"
        onClick={e => e.stopPropagation()} style={{ fontFamily: "'Poppins', sans-serif" }}>
        <div className="flex items-center gap-2 mb-1">
          <FiUser size={14} color="#22c55e" />
          <span className="text-foreground font-bold text-sm flex-1">Add New Soldier</span>
          <button onClick={onClose} className="text-slate-500 hover:text-white transition-colors bg-transparent border-none cursor-pointer"><FiX size={16} /></button>
        </div>
        {error && <div className="text-xs text-red-400 px-2 py-1.5 bg-red-500/10 rounded border border-red-500/20">{error}</div>}
        {field("FULL NAME", "full_name", "text", "John Doe")}
        {field("USERNAME", "username", "text", "john.doe")}
        {field("EMAIL", "email", "email", "john@drd.mil")}
        {field("PASSWORD", "password", "password", "Min. 8 characters")}
        {field("PHONE", "phone", "text", "+250 7XX XXX XXX")}
        <div>
          <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1">ROLE</label>
          <div className="w-full bg-slate-800 border border-white/8 rounded-md px-2.5 py-2 text-green-400 text-xs font-semibold">
            Field Unit
          </div>
        </div>
        {dbTeams.length > 0 && (
          <div>
            <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1">ASSIGN TO TEAM (optional)</label>
            <select value={form.team_id} onChange={e => setForm(p => ({ ...p, team_id: e.target.value }))}
              className="w-full bg-slate-800 border border-white/8 rounded-md px-2.5 py-2 text-foreground text-xs">
              <option value="">— No team —</option>
              {dbTeams.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
          </div>
        )}
        <div className="flex gap-2 mt-1">
          <button onClick={onClose} className="flex-1 py-2 bg-slate-800 border border-white/8 rounded-md text-slate-400 text-xs cursor-pointer hover:bg-slate-700">Cancel</button>
          <button onClick={handleSave} disabled={saving}
            className="flex-1 py-2 bg-green-600 border-none rounded-md text-white text-xs font-semibold cursor-pointer hover:opacity-90 disabled:opacity-50 flex items-center justify-center gap-1.5">
            {saving ? <span className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin" /> : <FiCheck size={12} />}
            {saving ? "Creating…" : "Create Soldier"}
          </button>
        </div>
      </div>
    </div>
  );
}

function CreateTeamModal({
  onClose, onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [color, setColor] = useState("#3b82f6");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const presets = ["#22c55e", "#f59e0b", "#ef4444", "#8b5cf6", "#06b6d4", "#3b82f6", "#f97316", "#ec4899"];

  const handleSave = async () => {
    if (!name.trim() || !code.trim()) { setError("Name and code are required."); return; }
    setSaving(true); setError("");
    try {
      await api.createTeam({ name: name.trim(), code: code.trim().toUpperCase(), color });
      onSaved(); onClose();
    } catch (e: unknown) {
      setError((e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ?? "Failed to create team.");
    }
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 bg-black/75 z-[5000] flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-slate-900 border border-white/10 rounded-xl w-full max-w-[380px] shadow-2xl p-5 flex flex-col gap-3"
        onClick={e => e.stopPropagation()} style={{ fontFamily: "'Poppins', sans-serif" }}>
        <div className="flex items-center gap-2 mb-1">
          <FiUsers size={14} color="#3b82f6" />
          <span className="text-foreground font-bold text-sm flex-1">New Team</span>
          <button onClick={onClose} className="text-slate-500 hover:text-white transition-colors bg-transparent border-none cursor-pointer"><FiX size={16} /></button>
        </div>
        {error && <div className="text-xs text-red-400 px-2 py-1.5 bg-red-500/10 rounded border border-red-500/20">{error}</div>}
        <div>
          <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1">TEAM NAME</label>
          <input value={name} onChange={e => setName(e.target.value)} placeholder="Team Alpha"
            className="w-full bg-slate-800 border border-white/8 rounded-md px-2.5 py-2 text-foreground text-xs focus:outline-none focus:border-primary/50" />
        </div>
        <div>
          <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1">CODE (short identifier)</label>
          <input value={code} onChange={e => setCode(e.target.value)} placeholder="ALPHA"
            className="w-full bg-slate-800 border border-white/8 rounded-md px-2.5 py-2 text-foreground text-xs focus:outline-none focus:border-primary/50" />
        </div>
        <div>
          <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1.5">TEAM COLOR</label>
          <div className="flex items-center gap-2">
            <div className="flex gap-1.5 flex-wrap flex-1">
              {presets.map(c => (
                <button key={c} onClick={() => setColor(c)}
                  className="w-6 h-6 rounded-full border-2 cursor-pointer transition-transform hover:scale-110"
                  style={{ backgroundColor: c, borderColor: color === c ? "white" : "transparent" }} />
              ))}
            </div>
            <input type="color" value={color} onChange={e => setColor(e.target.value)}
              className="w-8 h-8 rounded cursor-pointer bg-transparent border border-white/10" />
          </div>
        </div>
        <div className="flex gap-2 mt-1">
          <button onClick={onClose} className="flex-1 py-2 bg-slate-800 border border-white/8 rounded-md text-slate-400 text-xs cursor-pointer hover:bg-slate-700">Cancel</button>
          <button onClick={handleSave} disabled={saving}
            className="flex-1 py-2 bg-primary border-none rounded-md text-white text-xs font-semibold cursor-pointer hover:opacity-90 disabled:opacity-50 flex items-center justify-center gap-1.5">
            {saving ? <span className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin" /> : <FiCheck size={12} />}
            {saving ? "Creating…" : "Create Team"}
          </button>
        </div>
      </div>
    </div>
  );
}

function AssignTeamModal({
  userId, dbTeams, allUsers, onClose, onSaved,
}: {
  userId?: string | null; dbTeams: TeamInfo[]; allUsers: UserRecord[];
  onClose: () => void; onSaved: () => void;
}) {
  const fieldUnits = allUsers.filter(user => user.role === "field_unit");
  const availableUnits = fieldUnits.filter(user => !user.teamId);
  const [selectedUserId, setSelectedUserId] = useState(userId ?? "");
  const [teamId, setTeamId] = useState("");
  const [role, setRole] = useState("support");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const teamRoles = ["lead", "medic", "scout", "support", "sniper"];

  const handleSave = async () => {
    const targetUserId = userId ?? selectedUserId;
    if (!targetUserId) { setError("Select a soldier."); return; }
    if (!teamId) { setError("Select a team."); return; }
    setSaving(true); setError("");
    try {
      await api.addTeamMember(teamId, { user_id: targetUserId, role });
      onSaved(); onClose();
    } catch (e: unknown) {
      setError((e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ?? "Failed to assign.");
    }
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 bg-black/75 z-[5000] flex items-center justify-center p-4" onClick={onClose}>
      <div className="bg-slate-900 border border-white/10 rounded-xl w-full max-w-[340px] shadow-2xl p-5 flex flex-col gap-3"
        onClick={e => e.stopPropagation()} style={{ fontFamily: "'Poppins', sans-serif" }}>
        <div className="flex items-center gap-2 mb-1">
          <FiUsers size={14} color="#22c55e" />
          <span className="text-foreground font-bold text-sm flex-1">Assign Field Unit</span>
          <button onClick={onClose} className="text-slate-500 hover:text-white transition-colors bg-transparent border-none cursor-pointer"><FiX size={16} /></button>
        </div>
        {error && <div className="text-xs text-red-400 px-2 py-1.5 bg-red-500/10 rounded border border-red-500/20">{error}</div>}
        {!userId && (
          <div>
            <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1">SOLDIER</label>
            <select value={selectedUserId} onChange={e => setSelectedUserId(e.target.value)}
              className="w-full bg-slate-800 border border-white/8 rounded-md px-2.5 py-2 text-foreground text-xs">
              <option value="">— Select soldier —</option>
              {availableUnits.map(unit => (
                <option key={unit.id} value={unit.id}>{unit.full_name}</option>
              ))}
            </select>
          </div>
        )}
        <div>
          <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1">TEAM</label>
          <select value={teamId} onChange={e => setTeamId(e.target.value)}
            className="w-full bg-slate-800 border border-white/8 rounded-md px-2.5 py-2 text-foreground text-xs">
            <option value="">— Select team —</option>
            {dbTeams.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        </div>
        <div>
          <label className="text-slate-500 text-[9px] font-bold tracking-wider block mb-1">ROLE IN TEAM</label>
          <div className="flex flex-wrap gap-1.5">
            {teamRoles.map(r => (
              <button key={r} onClick={() => setRole(r)}
                className="px-2.5 py-1.5 rounded text-[10px] font-semibold cursor-pointer transition-all capitalize"
                style={{
                  backgroundColor: role === r ? "rgba(34,197,94,0.2)" : "rgba(30,41,59,0.6)",
                  border: role === r ? "1px solid rgba(34,197,94,0.5)" : "1px solid rgba(255,255,255,0.06)",
                  color: role === r ? "#22c55e" : "#94a3b8",
                }}>
                {r}
              </button>
            ))}
          </div>
        </div>
        <div className="flex gap-2 mt-1">
          <button onClick={onClose} className="flex-1 py-2 bg-slate-800 border border-white/8 rounded-md text-slate-400 text-xs cursor-pointer hover:bg-slate-700">Cancel</button>
          <button onClick={handleSave} disabled={saving}
            className="flex-1 py-2 bg-green-600 border-none rounded-md text-white text-xs font-semibold cursor-pointer hover:opacity-90 disabled:opacity-50 flex items-center justify-center gap-1.5">
            {saving ? <span className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin" /> : <FiCheck size={12} />}
            {saving ? "Assigning…" : "Assign"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────── ALL EVENTS MODAL ───────────────────────────
const EVENT_TYPES = ["ALL", "UPDATE", "STALE", "OFFLINE", "ONLINE", "MESSAGE", "FLAG", "ROUTE", "POI", "ZONE", "ALERT"] as const;
const TYPE_COLORS: Record<string, { color: string; bg: string }> = {
  UPDATE: { color: "#22c55e", bg: "rgba(34,197,94,0.12)" },
  STALE: { color: "#f59e0b", bg: "rgba(245,158,11,0.12)" },
  OFFLINE: { color: "#ef4444", bg: "rgba(239,68,68,0.12)" },
  ONLINE: { color: "#22c55e", bg: "rgba(34,197,94,0.12)" },
  MESSAGE: { color: "#3b82f6", bg: "rgba(59,130,246,0.12)" },
  FLAG: { color: "#a855f7", bg: "rgba(168,85,247,0.12)" },
  ROUTE: { color: "#06b6d4", bg: "rgba(6,182,212,0.12)" },
  POI: { color: "#f97316", bg: "rgba(249,115,22,0.12)" },
  ZONE: { color: "#ec4899", bg: "rgba(236,72,153,0.12)" },
  ALERT: { color: "#ef4444", bg: "rgba(239,68,68,0.15)" },
};

function AllEventsModal({ onClose }: { onClose: () => void }) {
  const [rows, setRows] = useState<Event[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [filter, setFilter] = useState<string>("ALL");
  const [loading, setLoading] = useState(false);
  const PAGE_SIZE = 50;

  useEffect(() => {
    let cancelled = false;
    const fetch = async () => {
      setLoading(true);
      try {
        const params: Record<string, unknown> = { page, size: PAGE_SIZE };
        if (filter !== "ALL") params.event_type = filter.toLowerCase();
        const res = await api.listEvents(params);
        if (cancelled) return;
        const items = res.data.items as Array<{
          id: string; event_type: string; user_id?: string;
          description?: string; created_at: string;
          location_lat?: number; location_lng?: number; severity?: string;
        }>;
        setRows(items.map(e => ({
          id: String(e.id),
          time: new Date(e.created_at),
          type: (e.event_type ?? "UPDATE").toUpperCase() as Event["type"],
          user: e.user_id ? String(e.user_id).slice(0, 8) : "System",
          team: "Team Alpha" as Team,
          event: e.description ?? "",
          location: e.location_lat != null
            ? `${Number(e.location_lat).toFixed(4)}, ${Number(e.location_lng).toFixed(4)}`
            : "Command",
        })));
        setTotal(res.data.total);
      } catch {
        setRows([]);
        setTotal(0);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    fetch();
    return () => { cancelled = true; };
  }, [page, filter]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <div className="fixed inset-0 bg-black/75 z-[5000] flex items-center justify-center p-3 md:p-6" onClick={onClose}>
      <div
        className="bg-slate-900 border border-white/10 rounded-xl w-full max-w-[900px] max-h-[90vh] flex flex-col shadow-2xl"
        onClick={e => e.stopPropagation()}
        style={{ fontFamily: "'Poppins', sans-serif" }}
      >
        {/* Header */}
        <div className="flex items-center gap-2 px-4 py-3 border-b border-white/10 flex-shrink-0">
          <FiActivity size={14} color="#3b82f6" />
          <span className="text-foreground font-bold text-sm flex-1">Activity Log</span>
          <span className="text-slate-500 text-xs mr-2">{total} events</span>
          <button onClick={onClose} className="text-slate-500 hover:text-foreground transition-colors bg-transparent border-none cursor-pointer">
            <FiX size={16} />
          </button>
        </div>

        {/* Filter chips */}
        <div className="px-4 py-2.5 border-b border-white/5 flex flex-wrap gap-1.5 flex-shrink-0">
          {EVENT_TYPES.map(t => {
            const active = filter === t;
            const ts = TYPE_COLORS[t] ?? { color: "#94a3b8", bg: "transparent" };
            return (
              <button
                key={t}
                onClick={() => { setFilter(t); setPage(1); }}
                className="px-2 py-1 rounded text-[9px] md:text-[10px] font-semibold cursor-pointer transition-all"
                style={{
                  backgroundColor: active ? ts.bg : "rgba(30,41,59,0.6)",
                  border: active ? `1px solid ${ts.color}40` : "1px solid rgba(255,255,255,0.06)",
                  color: active ? ts.color : "#64748b",
                }}
              >
                {t}
              </button>
            );
          })}
        </div>

        {/* Table */}
        <div className="flex-1 overflow-y-auto custom-scrollbar">
          {loading ? (
            <div className="flex items-center justify-center h-32 gap-2">
              <div className="w-4 h-4 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
              <span className="text-slate-500 text-xs">Loading events…</span>
            </div>
          ) : rows.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-32 gap-2 text-slate-600">
              <FiActivity size={22} />
              <span className="text-xs">No events found</span>
            </div>
          ) : (
            <table className="w-full text-[9px] md:text-[10px] border-collapse">
              <thead>
                <tr className="border-b border-white/5 sticky top-0 bg-slate-900">
                  {["Time", "Type", "Severity", "Unit", "Event", "Location"].map((h, i) => (
                    <th key={i} className="px-2 py-2 text-slate-500 font-semibold text-left whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map(ev => {
                  const ts = TYPE_COLORS[ev.type] ?? { color: "#94a3b8", bg: "transparent" };
                  return (
                    <tr key={ev.id} className="border-b border-white/3 hover:bg-white/4 transition-colors">
                      <td className="px-2 py-1.5 text-slate-500 whitespace-nowrap">
                        {ev.time.toLocaleDateString()} {formatTime(ev.time)}
                      </td>
                      <td className="px-2 py-1.5">
                        <span className="px-1.5 py-0.5 rounded text-[8px] font-bold whitespace-nowrap" style={{ backgroundColor: ts.bg, color: ts.color }}>
                          {ev.type}
                        </span>
                      </td>
                      <td className="px-2 py-1.5 text-slate-400">{ev.location === "Command" ? "—" : "field"}</td>
                      <td className="px-2 py-1.5 text-foreground font-semibold whitespace-nowrap">{ev.user}</td>
                      <td className="px-2 py-1.5 text-slate-300 max-w-[200px] truncate">{ev.event}</td>
                      <td className="px-2 py-1.5 text-slate-500 whitespace-nowrap truncate max-w-[120px]">{ev.location}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>

        {/* Pagination */}
        <div className="flex items-center justify-between px-4 py-2.5 border-t border-white/8 flex-shrink-0">
          <button
            disabled={page <= 1}
            onClick={() => setPage(p => p - 1)}
            className="flex items-center gap-1 px-2.5 py-1.5 rounded text-[10px] font-semibold transition-all cursor-pointer disabled:opacity-30"
            style={{ backgroundColor: "rgba(30,41,59,0.6)", border: "1px solid rgba(255,255,255,0.08)", color: "#94a3b8" }}
          >
            <FiChevronLeft size={11} /> Prev
          </button>
          <span className="text-slate-500 text-[10px]">Page {page} / {totalPages} &nbsp;·&nbsp; {total} total</span>
          <button
            disabled={page >= totalPages}
            onClick={() => setPage(p => p + 1)}
            className="flex items-center gap-1 px-2.5 py-1.5 rounded text-[10px] font-semibold transition-all cursor-pointer disabled:opacity-30"
            style={{ backgroundColor: "rgba(30,41,59,0.6)", border: "1px solid rgba(255,255,255,0.08)", color: "#94a3b8" }}
          >
            Next <FiChevronRight size={11} />
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────── MAIN COMPONENT ───────────────────────────
export default function DODMap() {
  const [users, setUsers] = useState<User[]>([]);
  const [events, setEvents] = useState<Event[]>([]);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [teamFilter, setTeamFilter] = useState<Team | "All">("All");
  const [messages, setMessages] = useState<Message[]>([]);
  const [msgModal, setMsgModal] = useState<string | null>(null);
  const [sosIncident, setSosIncident] = useState<SOSIncident | null>(null);
  const [routes, setRoutes] = useState<Route[]>([]);
  const [routeHistory, setRouteHistory] = useState<RouteHistoryItem[]>([]);
  const [routeDrawMode, setRouteDrawMode] = useState(false);
  const [zoneMode, setZoneMode] = useState(false);
  const [pendingRoute, setPendingRoute] = useState<Waypoint[]>([]);
  const [showRouteModal, setShowRouteModal] = useState(false);
  const [pois, setPois] = useState<POI[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [dbTeams, setDbTeams] = useState<TeamInfo[]>([]);
  const [showAllEvents, setShowAllEvents] = useState(false);
  const [dbAllUsers, setDbAllUsers] = useState<UserRecord[]>([]);
  const [showCreateUser, setShowCreateUser] = useState(false);
  const [showCreateTeam, setShowCreateTeam] = useState(false);
  const [forceExpanded, setForceExpanded] = useState(false);
  const [assigningUserId, setAssigningUserId] = useState<string | null>(null);
  const [showAssignPicker, setShowAssignPicker] = useState(false);
  const [currentUserRole, setCurrentUserRole] = useState<any>(null);
  const [currentUser, setCurrentUser] = useState<{ username?: string; full_name?: string; email?: string; role?: string } | null>(null);
  const [mapFlyTarget, setMapFlyTarget] = useState<{ lat: number; lng: number } | null>(null);
  const [selectedPOIType, setSelectedPOIType] = useState<POIType>("checkpoint");
  const [pendingPOI, setPendingPOI] = useState<POI | null>(null);
  const [showPOIModal, setShowPOIModal] = useState(false);
  const [mapView, setMapView] = useState<MapViewType>("standard");
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isConnected, setIsConnected] = useState(false);
  const [browserPosition, setBrowserPosition] = useState<{ lat: number; lng: number } | null>(null);
  const isConnectedRef = useRef(false);
  const teamsMapRef = useRef<Map<string, string>>(new Map());
  const usersInfoRef = useRef<Map<string, { name: string; role?: string }>>(new Map());

  const [panels, setPanels] = useState({
    teamOverview: false,
    selectedUser: false,
    alerts: false,
    quickActions: false,
    routes: false,
    comms: false,
  });
  if (window.innerWidth >= 128000) {
    setIsFullscreen(false);
  }
  const togglePanel = (key: keyof typeof panels) => {
    setPanels(p => ({ ...p, [key]: !p[key] }));
  };

  const focusUserOnMap = useCallback((user: User) => {
    setMapFlyTarget({ lat: user.lat, lng: user.lng });
    setSelectedUser(user);
    setSidebarOpen(true);
    setPanels(p => ({ ...p, selectedUser: true }));
  }, []);

  const openSOSIncident = useCallback((user: User, description?: string, createdAt?: Date, lat?: number, lng?: number) => {
    focusUserOnMap(user);
    setSosIncident({
      userId: user.user_id,
      description: description || `${user.name} requested immediate support`,
      createdAt: createdAt || new Date(),
      lat: lat ?? user.lat,
      lng: lng ?? user.lng,
    });
  }, [focusUserOnMap]);

  const refreshRoutesAndPois = useCallback(async () => {
    try {
      const [routesRes, historyRes, poisRes] = await Promise.all([
        api.listRoutes({ is_active: true }),
        api.listRouteHistory(),
        api.listPOIs(),
      ]);

      const refreshedRoutes: Route[] = ((routesRes.data ?? []) as Array<{
        is_active: any;
        id: string; name: string; assigned_user_id?: string; assigned_team_id?: string;
        waypoints: Array<{ latitude: number; longitude: number; label?: string; poi_type?: string }>;
        created_at: string; color: string; meeting_point: boolean;
        is_zone: boolean; zone_type?: string;
      }>).map(r => ({
        id: String(r.id),
        name: r.name,
        assignedTo: r.assigned_user_id ? String(r.assigned_user_id) : "ALL",
        assignedTeam: r.assigned_team_id ? String(r.assigned_team_id) : "ALL",
        waypoints: (r.waypoints ?? []).map(wp => ({
          lat: wp.latitude,
          lng: wp.longitude,
          label: wp.label ?? "WP",
          type: wp.poi_type as POIType | undefined,
        })),
        createdAt: new Date(r.created_at),
        color: r.color ?? "#3b82f6",
        meetingPoint: r.meeting_point ?? false,
        visibleTo: ["ALL"],
        coordinates: (r.waypoints ?? []).map(wp => [wp.latitude, wp.longitude] as [number, number]),
        isZone: r.is_zone ?? false,
        zoneType: r.zone_type as Route["zoneType"],
        isActive: r.is_active,
      }));
      setRoutes(refreshedRoutes);

      const refreshedHistory: RouteHistoryItem[] = ((historyRes.data ?? []) as Array<{
        id: string; route_id?: string; name: string; assigned_user_id?: string; assigned_team_id?: string;
        waypoints: Array<{ latitude: number; longitude: number; label?: string; poi_type?: string }>;
        deleted_at: string; color: string; meeting_point: boolean;
        is_zone: boolean; zone_type?: string;
      }>).map(r => ({
        id: String(r.route_id ?? r.id),
        name: r.name,
        assignedTo: r.assigned_user_id ? String(r.assigned_user_id) : "ALL",
        assignedTeam: r.assigned_team_id ? String(r.assigned_team_id) : "ALL",
        waypoints: (r.waypoints ?? []).map(wp => ({
          lat: wp.latitude,
          lng: wp.longitude,
          label: wp.label ?? "WP",
          type: wp.poi_type as POIType | undefined,
        })),
        createdAt: new Date(r.deleted_at),
        deletedAt: new Date(r.deleted_at),
        color: r.color ?? "#3b82f6",
        meetingPoint: r.meeting_point ?? false,
        visibleTo: ["ALL"],
        coordinates: (r.waypoints ?? []).map(wp => [wp.latitude, wp.longitude] as [number, number]),
        isZone: r.is_zone ?? false,
        zoneType: r.zone_type as Route["zoneType"],
        isActive: false,
      }));
      setRouteHistory(refreshedHistory);

      const refreshedPOIs: POI[] = ((poisRes.data ?? []) as Array<{
        id: string; poi_type: string; latitude: number; longitude: number;
        name: string; status: string; visible_to_all: boolean; tactical_shape: string;
      }>).map(p => ({
        id: String(p.id),
        type: (p.poi_type in POI_ICONS_CONFIG ? p.poi_type : "checkpoint") as POIType,
        lat: p.latitude,
        lng: p.longitude,
        label: p.name,
        status: p.status as POI["status"],
        visibleTo: p.visible_to_all ? ["ALL"] : [],
        shape: (p.tactical_shape || "diamond") as TacticalShape,
      }));
      setPois(refreshedPOIs);
    } catch {
      // Keep current state if refresh fails.
    }
  }, []);

  const loadData = useCallback(async () => {
    setIsLoading(true);
    setEvents([
      { id: "init_1", time: new Date(), type: "ONLINE", user: "System", team: "Team Alpha", event: "Dashboard initialized", location: "Command" },
    ]);

    const token = localStorage.getItem("access_token");
    if (!token) {
      window.location.href = "/login";
      return;
    }

    try {
      const [meRes, teamsRes, locsRes, poisRes, routesRes, historyRes, msgsRes, eventsRes, allUsersRes] = await Promise.allSettled([
        api.getMe(),
        api.listTeams(),
        api.getActiveLocations(),
        api.listPOIs(),
        api.listRoutes({ is_active: true }),
        api.listRouteHistory(),
        api.listMessages({ size: 50 }),
        api.listEvents({ size: 50 }),
        api.listUsers({ size: 500 }),
      ]);

      if (meRes.status === "fulfilled") {
        const me = meRes.value.data as { role?: string; username?: string; full_name?: string; email?: string };
        setCurrentUserRole(me?.role ?? null);
        setCurrentUser(me ?? null);
      }

      // Build team + user info maps
      const teamsMap = new Map<string, string>();
      const usersInfo = new Map<string, { name: string; role?: string }>();
      if (teamsRes.status === "fulfilled") {
        const teamData = teamsRes.value.data as Array<{
          id: string; name: string; color?: string; member_count?: number;
          members?: Array<{ user_id: string; user_name: string; role: string }>;
        }>;
        setDbTeams(teamData.map(t => ({
          id: String(t.id),
          name: t.name,
          color: t.color || "#3b82f6",
          memberCount: t.member_count || 0,
        })));
        for (const t of teamData) {
          teamsMap.set(t.id, t.name);
          for (const m of t.members ?? []) {
            usersInfo.set(String(m.user_id), { name: m.user_name, role: m.role });
          }
        }
        teamsMapRef.current = teamsMap;
        usersInfoRef.current = usersInfo;
      }

      // Locations → users (show real data; empty = no units deployed yet)
      if (locsRes.status === "fulfilled") {
        const frontendUsers: User[] = (locsRes.value.data as Array<{
          user_id: string; team_id: string; latitude: number; longitude: number;
          status: string; recorded_at: string; speed?: number; heading?: number;
        }>).map(loc => {
          const uInfo = usersInfo.get(String(loc.user_id)) ?? { name: String(loc.user_id).slice(0, 8) };
          const teamName = teamsMap.get(String(loc.team_id)) ?? "Team Alpha";
          const validTeam: Team = (Object.keys(TEAM_COLORS) as Team[]).includes(teamName as Team)
            ? (teamName as Team)
            : "Team Alpha";
          return {
            user_id: String(loc.user_id),
            name: uInfo.name,
            group: validTeam,
            lat: loc.latitude,
            lng: loc.longitude,
            status: (loc.status ?? "active") as Status,
            lastUpdate: new Date(loc.recorded_at ?? Date.now()),
            message: "Field position",
            speed: loc.speed ?? 0,
            heading: loc.heading ?? 0,
            flag: null,
            role: uInfo.role as User["role"] | undefined,
          };
        });

        // Add offline field units with their last known location
        if (allUsersRes.status === "fulfilled") {
          const locatedUserIds = new Set(frontendUsers.map(u => u.user_id));
          const unlocatedUsers = (allUsersRes.value.data.items as Array<{
            id: string; full_name: string; role: string;
          }>).filter(u => u.role === "field_unit" && !locatedUserIds.has(String(u.id)));

          const locationFetches = await Promise.allSettled(
            unlocatedUsers.map(u => api.getUserLocation(String(u.id)))
          );

          locationFetches.forEach((res, i) => {
            if (res.status === "fulfilled" && res.value.data?.latitude != null) {
              const loc = res.value.data;
              const u = unlocatedUsers[i];
              const uInfo = usersInfo.get(String(u.id)) ?? { name: u.full_name };
              // const teamName = "Team Alpha";
              frontendUsers.push({
                user_id: String(u.id),
                name: uInfo.name,
                group: "Team Alpha" as Team,
                lat: loc.latitude,
                lng: loc.longitude,
                status: "offline",
                lastUpdate: new Date(loc.recorded_at ?? Date.now()),
                message: "Last known position",
                speed: 0,
                heading: 0,
                flag: null,
                role: uInfo.role as User["role"] | undefined,
              });
            }
          });
        }

        setUsers(frontendUsers);
      }

      // POIs (empty = no POIs deployed yet)
      if (poisRes.status === "fulfilled") {
        const frontendPOIs: POI[] = (poisRes.value.data as Array<{
          id: string; poi_type: string; latitude: number; longitude: number;
          name: string; status: string; visible_to_all: boolean; tactical_shape: string;
        }>).map(p => ({
          id: String(p.id),
          type: (p.poi_type in POI_ICONS_CONFIG ? p.poi_type : "checkpoint") as POIType,
          lat: p.latitude,
          lng: p.longitude,
          label: p.name,
          status: p.status as POI["status"],
          visibleTo: p.visible_to_all ? ["ALL"] : [],
          shape: (p.tactical_shape || "diamond") as TacticalShape,
        }));
        setPois(frontendPOIs);
      }

      // Routes
      if (routesRes.status === "fulfilled" && (routesRes.value.data as unknown[]).length > 0) {
        const frontendRoutes: Route[] = (routesRes.value.data as Array<{
          id: string; name: string; assigned_user_id?: string; assigned_team_id?: string; assigned_team_name?: string;
          waypoints: Array<{ latitude: number; longitude: number; label?: string; poi_type?: string }>;
          created_at: string; color: string; meeting_point: boolean;
          is_zone: boolean; zone_type?: string; is_active: boolean;
        }>).map(r => ({
          id: String(r.id),
          name: r.name,
          assignedTo: r.assigned_user_id ? String(r.assigned_user_id) : "ALL",
          assignedTeam: r.assigned_team_id ? String(r.assigned_team_id) : "ALL",
          waypoints: (r.waypoints ?? []).map(wp => ({
            lat: wp.latitude, lng: wp.longitude,
            label: wp.label ?? "WP",
            type: wp.poi_type as POIType | undefined,
          })),
          createdAt: new Date(r.created_at),
          color: r.color ?? "#3b82f6",
          meetingPoint: r.meeting_point ?? false,
          visibleTo: ["ALL"],
          coordinates: (r.waypoints ?? []).map(wp => [wp.latitude, wp.longitude] as [number, number]),
          isZone: r.is_zone ?? false,
          zoneType: r.zone_type as Route["zoneType"],
          isActive: r.is_active,
        }));
        setRoutes(frontendRoutes);
      }

      if (historyRes.status === "fulfilled") {
        const frontendHistory: RouteHistoryItem[] = (historyRes.value.data as Array<{
          id: string; route_id?: string; name: string; assigned_user_id?: string; assigned_team_id?: string;
          waypoints: Array<{ latitude: number; longitude: number; label?: string; poi_type?: string }>;
          deleted_at: string; color: string; meeting_point: boolean;
          is_zone: boolean; zone_type?: string;
        }>).map(r => ({
          id: String(r.route_id ?? r.id),
          name: r.name,
          assignedTo: r.assigned_user_id ? String(r.assigned_user_id) : "ALL",
          assignedTeam: r.assigned_team_id ? String(r.assigned_team_id) : "ALL",
          waypoints: (r.waypoints ?? []).map(wp => ({
            lat: wp.latitude,
            lng: wp.longitude,
            label: wp.label ?? "WP",
            type: wp.poi_type as POIType | undefined,
          })),
          createdAt: new Date(r.deleted_at),
          deletedAt: new Date(r.deleted_at),
          color: r.color ?? "#3b82f6",
          meetingPoint: r.meeting_point ?? false,
          visibleTo: ["ALL"],
          coordinates: (r.waypoints ?? []).map(wp => [wp.latitude, wp.longitude] as [number, number]),
          isZone: r.is_zone ?? false,
          zoneType: r.zone_type as Route["zoneType"],
          isActive: false,
        }));
        setRouteHistory(frontendHistory);
      }

      // Messages
      if (msgsRes.status === "fulfilled") {
        const frontendMsgs: Message[] = (msgsRes.value.data.items as Array<{
          id: string; from_user_name?: string; to_all: boolean; to_user_id?: string;
          content: string; created_at: string; is_read: boolean; priority?: string;
        }>).map(m => ({
          id: String(m.id),
          from: m.from_user_name ?? "Unknown",
          to: m.to_all ? "ALL" : (m.to_user_id ? String(m.to_user_id) : "ALL"),
          content: m.content,
          time: new Date(m.created_at),
          read: m.is_read,
          priority: (m.priority ?? "normal") as Message["priority"],
        }));
        setMessages(frontendMsgs);
      }

      // Events + flag alerts
      if (eventsRes.status === "fulfilled") {
        const rawEvents = eventsRes.value.data.items as Array<{
          severity: string;
          id: string; event_type: string; user_id?: string;
          description: string; created_at: string;
          location_lat?: number; location_lng?: number;
          event_metadata?: Record<string, unknown>;
        }>;
        const frontendEvents: Event[] = rawEvents.map(e => ({
          id: String(e.id),
          time: new Date(e.created_at),
          type: (e.event_type ?? "UPDATE").toUpperCase() as Event["type"],
          user: e.user_id ? (usersInfo.get(String(e.user_id))?.name ?? String(e.user_id).slice(0, 8)) : "System",
          team: "Team Alpha" as Team,
          event: e.description ?? "",
          location: e.location_lat != null
            ? `${Number(e.location_lat).toFixed(4)}, ${Number(e.location_lng).toFixed(4)}`
            : "Command",
        }));
        if (frontendEvents.length > 0) setEvents(prev => [...prev, ...frontendEvents]);

        // Apply FLAG events to user flags (SOS alerts from mobile)
        const flagEvents = rawEvents.filter(e => e.event_type?.toUpperCase() === "FLAG" && e.user_id);
        if (flagEvents.length > 0) {
          setUsers(prev => {
            const next = [...prev];
            flagEvents.forEach(fe => {
              const idx = next.findIndex(u => u.user_id === String(fe.user_id));
              if (idx >= 0) {
                const desc = (fe.description ?? "").toLowerCase();
                const isSOS = fe.severity === "high" || fe.event_metadata?.sos_type;
                let flag: FlagType | null = null;
                if (isSOS || desc.includes("sos") || desc.includes("help")) flag = "help";
                else if (desc.includes("trouble")) flag = "trouble";
                else if (desc.includes("safe")) flag = "safe";
                if (flag) {
                  const updatedUser = { ...next[idx], flag, flagTime: new Date(fe.created_at) };
                  next[idx] = updatedUser;
                  if (flag === "help") {
                    setSosIncident({
                      userId: updatedUser.user_id,
                      description: fe.description || `${updatedUser.name} requested immediate support`,
                      createdAt: new Date(fe.created_at),
                      lat: fe.location_lat ?? updatedUser.lat,
                      lng: fe.location_lng ?? updatedUser.lng,
                    });
                  }
                }
              }
            });
            return next;
          });
        }
      }

      // All registered soldiers (with team cross-reference)
      if (allUsersRes.status === "fulfilled") {
        const userTeamMap = new Map<string, { teamId: string; teamName: string; teamRole: string }>();
        if (teamsRes.status === "fulfilled") {
          for (const t of teamsRes.value.data as Array<{ id: string; name: string; members?: Array<{ user_id: string; role: string }> }>) {
            for (const m of t.members ?? []) {
              userTeamMap.set(String(m.user_id), { teamId: t.id, teamName: t.name, teamRole: m.role });
            }
          }
        }
        const rawUsers = allUsersRes.value.data.items as Array<{
          id: string; username: string; full_name: string; email: string;
          role: string; is_active: boolean;
        }>;
        // Debug: log listUsers payload to help diagnose missing field_unit records
        try {
          // eslint-disable-next-line no-console
          console.debug("listUsers response (first 30)", rawUsers.slice(0, 30));
          // eslint-disable-next-line no-console
          console.debug("userTeamMap keys", Array.from(userTeamMap.keys()).slice(0, 50));
        } catch (e) {
          // ignore
        }
        setDbAllUsers(rawUsers.map(u => ({
          id: String(u.id),
          username: u.username,
          full_name: u.full_name,
          email: u.email,
          role: u.role,
          is_active: u.is_active,
          ...userTeamMap.get(String(u.id)),
        })));
      }

      setIsConnected(true);
      isConnectedRef.current = true;
      connectAll(token);

    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 401) {
        localStorage.removeItem("access_token");
        localStorage.removeItem("refresh_token");
        window.location.href = "/login";
        return;
      }
      console.warn("[DRD] Backend unavailable, showing demo data", err);
      setUsers(INITIAL_USERS);
      setPois(INITIAL_POIS);
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Initial load + cleanup
  useEffect(() => {
    loadData();
    return () => {
      disconnectAll();
      isConnectedRef.current = false;
    };
  }, [loadData]);

  useEffect(() => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      position => {
        setBrowserPosition({
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        });
      },
      () => {
        setBrowserPosition(null);
      },
      {
        enableHighAccuracy: true,
        timeout: 8000,
        maximumAge: 30000,
      },
    );
  }, []);

  // Real-time WebSocket subscriptions
  useEffect(() => {
    if (!isConnected) return;

    const unsubLoc = locationWS.subscribe((msg: unknown) => {
      const m = msg as { type?: string; data?: Record<string, unknown> } & Record<string, unknown>;
      const d = (m.data ?? m) as {
        team_id(team_id: any): string;
        user_id?: string; latitude?: number; longitude?: number;
        speed?: number; heading?: number; status?: string; recorded_at?: string;
      };
      if (!d.user_id) return;
      setUsers(prev => {
        const userId = String(d.user_id);
        const existingIndex = prev.findIndex(u => u.user_id === userId);
        if (existingIndex >= 0) {
          return prev.map(u => {
            if (u.user_id !== userId) return u;
            return {
              ...u,
              lat: d.latitude ?? u.lat,
              lng: d.longitude ?? u.lng,
              speed: d.speed ?? u.speed,
              heading: d.heading ?? u.heading,
              status: (d.status ?? u.status) as Status,
              lastUpdate: new Date(d.recorded_at ?? Date.now()),
            };
          });
        }

        const teamName = teamsMapRef.current.get(String(d.team_id)) ?? "Team Alpha";
        const userInfo = usersInfoRef.current.get(userId);
        return [
          ...prev,
          {
            user_id: userId,
            name: userInfo?.name ?? userId.slice(0, 8),
            group: (teamName as Team) || "Team Alpha",
            lat: d.latitude ?? 0,
            lng: d.longitude ?? 0,
            status: (d.status ?? "active") as Status,
            lastUpdate: new Date(d.recorded_at ?? Date.now()),
            message: "Field position",
            speed: d.speed ?? 0,
            heading: d.heading ?? 0,
            flag: null,
            role: userInfo?.role as User["role"] | undefined,
          },
        ];
      });
    });

    const unsubMsg = messageWS.subscribe((msg: unknown) => {
      const m = msg as { type?: string; data?: Record<string, unknown> } & Record<string, unknown>;
      const d = (m.data ?? m) as {
        id?: string; from_user_name?: string; to_all?: boolean;
        to_user_id?: string; content?: string; created_at?: string; priority?: string;
      };
      if (!d.content) return;
      setMessages(prev => {
        if (prev.find(x => String(x.id) === String(d.id))) return prev;
        return [...prev, {
          id: String(d.id ?? Date.now()),
          from: d.from_user_name ?? "Unknown",
          to: d.to_all ? "ALL" : (d.to_user_id ? String(d.to_user_id) : "ALL"),
          content: d.content ?? "",
          time: new Date(d.created_at ?? Date.now()),
          read: false,
          priority: (d.priority ?? "normal") as Message["priority"],
        }];
      });
    });

    const unsubEvt = eventWS.subscribe((msg: unknown) => {
      const m = msg as { type?: string; data?: Record<string, unknown> } & Record<string, unknown>;
      const d = (m.data ?? m) as {
        id?: string; event_type?: string; user_id?: string;
        description?: string; created_at?: string;
        location_lat?: number; location_lng?: number;
        event_metadata?: Record<string, unknown>;
      };
      if (!d.description && !d.event_type) return;
      const newEvt: Event = {
        id: String(d.id ?? Date.now()),
        time: new Date(d.created_at ?? Date.now()),
        type: ((d.event_type ?? "UPDATE").toUpperCase()) as Event["type"],
        user: d.user_id ? (usersInfoRef.current.get(String(d.user_id))?.name ?? String(d.user_id).slice(0, 8)) : "System",
        team: "Team Alpha" as Team,
        event: d.description ?? "",
        location: d.location_lat != null ? `${Number(d.location_lat).toFixed(4)}, ${Number(d.location_lng).toFixed(4)}` : "Command",
      };
      setEvents(prev => {
        if (prev.find(e => e.id === newEvt.id)) return prev;
        return [newEvt, ...prev.slice(0, 199)];
      });

      const eventType = (d.event_type ?? "").toUpperCase();
      if (eventType === "ROUTE" || eventType === "ZONE" || eventType === "POI" || eventType.startsWith("ROUTE_FOLLOW")) {
        refreshRoutesAndPois();
      }

      // Apply FLAG event as user flag alert
      if ((d.event_type ?? "").toUpperCase() === "FLAG" && d.user_id) {
        const desc = (d.description ?? "").toLowerCase();
        const isSOS = (d as { severity?: string; event_metadata?: Record<string, unknown> }).severity === "high"
          || (d as { event_metadata?: Record<string, unknown> }).event_metadata?.sos_type;
        let flag: FlagType | null = null;
        if (isSOS || desc.includes("sos") || desc.includes("help")) flag = "help";
        else if (desc.includes("trouble")) flag = "trouble";
        else if (desc.includes("safe")) flag = "safe";
        if (flag) {
          setUsers(prev => {
            let sosUser: User | null = null;
            const next = prev.map(u => {
              if (u.user_id !== String(d.user_id)) return u;
              const updated = { ...u, flag, flagTime: new Date(d.created_at ?? Date.now()) };
              if (flag === "help") sosUser = updated;
              return updated;
            });
            if (flag === "help" && sosUser) {
              openSOSIncident(
                sosUser,
                d.description,
                new Date(d.created_at ?? Date.now()),
                d.location_lat,
                d.location_lng,
              );
            }
            return next;
          });
        }
      }
    });

    return () => { unsubLoc(); unsubMsg(); unsubEvt(); };
  }, [isConnected, refreshRoutesAndPois, openSOSIncident]);

  useEffect(() => {
    const interval = setInterval(() => {
      setUsers(prev => {
        const now = Date.now();
        return prev.map(u => {
          const elapsed = now - u.lastUpdate.getTime();
          let newStatus: Status = "active";
          if (elapsed > 90000) newStatus = "offline";
          else if (elapsed > 30000) newStatus = "stale";

          if (!isConnectedRef.current && Math.random() < 0.3 && u.status === "active") {
            return {
              ...u,
              lat: u.lat + (Math.random() - 0.5) * 0.0008,
              lng: u.lng + (Math.random() - 0.5) * 0.0008,
              lastUpdate: new Date(now),
              status: newStatus,
              heading: (u.heading || 0) + (Math.random() - 0.5) * 12,
              speed: Math.max(0, Math.min(5, (u.speed || 2) + (Math.random() - 0.5) * 0.4)),
            };
          }
          return { ...u, status: newStatus };
        });
      });
    }, 2000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (selectedUser) {
      const updated = users.find(u => u.user_id === selectedUser.user_id);
      if (updated) setSelectedUser(updated);
    }
  }, [users]);

  const handleFlag = (userId: string, flag: FlagType | null) => {
    setUsers(prev => prev.map(u => u.user_id === userId ? { ...u, flag, flagTime: flag ? new Date() : null } : u));
    const user = users.find(u => u.user_id === userId);
    if (user && flag) {
      setEvents(prev => [...prev, {
        id: `flag_${Date.now()}`, time: new Date(),
        type: "FLAG", user: user.name, team: user.group,
        event: `Flagged ${FLAG_COLORS[flag].label}`,
        location: user.message,
      }]);
      if (isConnectedRef.current) {
        api.createEvent({
          event_type: "FLAG",
          user_id: userId,
          description: `${user.name} flagged as ${FLAG_COLORS[flag].label}`,
          severity: flag === "help" ? "high" : flag === "trouble" ? "medium" : "low",
          location_lat: user.lat,
          location_lng: user.lng,
        }).catch(console.warn);
      }
    }
  };

  const handleSendMessage = (to: string, content: string, priority: "low" | "normal" | "high" | "urgent") => {
    const newMsg: Message = {
      id: `msg_${Date.now()}`, from: "COMMANDER", to, content, time: new Date(), read: false, priority,
    };
    setMessages(prev => [...prev, newMsg]);
    setEvents(prev => [...prev, {
      id: `msg_ev_${Date.now()}`, time: new Date(), type: "MESSAGE",
      user: "Commander", team: "Team Alpha",
      event: `MSG to ${to === "ALL" ? "all" : users.find(u => u.user_id === to)?.name || to} [${priority}]`,
      location: "Command",
    }]);
    if (isConnectedRef.current) {
      const payload = to === "ALL"
        ? { to_all: true, content, priority }
        : { to_user_id: to, to_all: false, content, priority };
      api.sendMessage(payload).catch(console.warn);
    }
  };

  const handleOpenSOSComms = (userId: string) => {
    setMsgModal(userId);
  };

  const handleAutoDispatchSOSUnits = (userIds: string[]) => {
    if (!sosIncident || userIds.length === 0) return;
    const sender = users.find(user => user.user_id === sosIncident.userId);
    const senderName = sender?.name || sosIncident.userId;
    const dispatchMessage = `AUTO-DISPATCH: Support ${senderName} at ${sosIncident.lat.toFixed(5)}, ${sosIncident.lng.toFixed(5)} immediately.`;

    userIds.forEach(userId => {
      handleSendMessage(userId, dispatchMessage, "urgent");
    });

    setEvents(prev => [
      {
        id: `dispatch_${Date.now()}`,
        time: new Date(),
        type: "ALERT",
        user: "Commander",
        team: sender?.group || "Team Alpha",
        event: `Auto-assigned support units (${userIds.length}) to ${senderName}`,
        location: `${sosIncident.lat.toFixed(4)}, ${sosIncident.lng.toFixed(4)}`,
      },
      ...prev,
    ]);

    if (isConnectedRef.current) {
      api.createEvent({
        event_type: "ALERT",
        user_id: sosIncident.userId,
        description: `Commander auto-assigned ${userIds.length} nearby unit(s) for ${senderName}`,
        severity: "high",
        location_lat: sosIncident.lat,
        location_lng: sosIncident.lng,
        event_metadata: { assigned_unit_ids: userIds },
      }).catch(console.warn);
    }
  };

  const handleMapClick = useCallback((lat: number, lng: number) => {
    if (routeDrawMode || zoneMode) {
      const label = zoneMode ? `ZP${pendingRoute.length + 1}` : `${POI_ICONS_CONFIG[selectedPOIType].tacticalIcon}${pendingRoute.length + 1}`;
      setPendingRoute(prev => [...prev, { lat, lng, label, type: selectedPOIType }]);

      if (pendingRoute.length === 0 && routeDrawMode) {
        const newPOI: POI = {
          id: `poi_${Date.now()}`,
          type: selectedPOIType,
          lat, lng, label,
          visibleTo: ["ALL"],
        };
        setPendingPOI(newPOI);
        setShowPOIModal(true);
      }
    }
  }, [routeDrawMode, zoneMode, selectedPOIType, pendingRoute]);

  const handleSavePOIVisibility = (updatedPOI: POI) => {
    const tempId = updatedPOI.id;
    setPois(prev => [...prev, updatedPOI]);
    setEvents(prev => [...prev, {
      id: `poi_${Date.now()}`, time: new Date(), type: "POI",
      user: "Commander", team: "Team Alpha",
      event: `Added ${POI_ICONS_CONFIG[updatedPOI.type].label}: ${updatedPOI.label}`,
      location: `${updatedPOI.lat.toFixed(4)}, ${updatedPOI.lng.toFixed(4)}`,
    }]);
    if (isConnectedRef.current) {
      const visibleToTeams = updatedPOI.visibleTo.filter(id => dbTeams.some(team => team.id === id));
      const visibleToUsers = updatedPOI.visibleTo.filter(id => users.some(user => user.user_id === id));
      api.createPOI({
        name: updatedPOI.label,
        poi_type: updatedPOI.type,
        latitude: updatedPOI.lat,
        longitude: updatedPOI.lng,
        tactical_shape: updatedPOI.shape || "diamond",
        status: updatedPOI.status || "active",
        visible_to_all: updatedPOI.visibleTo.includes("ALL"),
        visible_to_teams: visibleToTeams,
        visible_to_users: visibleToUsers,
      }).then((res: { data: { id: string } }) => {
        setPois(prev => prev.map(p => p.id === tempId ? { ...p, id: String(res.data.id) } : p));
      }).catch(console.warn);
    }
    setPendingPOI(null);
  };

  const handleTeamFilter = () => {
    if (dbTeams.length === 0) return;
    const teamNames: string[] = ["All", ...dbTeams.map(t => t.name)];
    const idx = teamNames.indexOf(teamFilter);
    setTeamFilter(teamNames[(idx + 1) % teamNames.length] as Team | "All");
  };

  const handleSelectTeam = (team: Team) => {
    setTeamFilter(team);
  };

  const handleRouteMode = () => {
    if ((routeDrawMode || zoneMode) && pendingRoute.length >= 2) {
      setShowRouteModal(true);
    } else if (routeDrawMode || zoneMode) {
      setRouteDrawMode(false);
      setZoneMode(false);
      setPendingRoute([]);
    } else {
      setRouteDrawMode(true);
      setZoneMode(false);
      setPendingRoute([]);
    }
  };

  const handleZoneMode = () => {
    if (zoneMode && pendingRoute.length >= 2) {
      setShowRouteModal(true);
    } else if (zoneMode) {
      setZoneMode(false);
      setPendingRoute([]);
    } else {
      setZoneMode(true);
      setRouteDrawMode(false);
      setPendingRoute([]);
    }
  };

  const handleCreateRouteForUser = (userId: string) => {
    setRouteDrawMode(true);
    setZoneMode(false);
    setPendingRoute([]);
    // Pre-select the user's current position as first waypoint
    const user = users.find(u => u.user_id === userId);
    if (user) {
      setPendingRoute([{ lat: user.lat, lng: user.lng, label: "START" }]);
    }
  };

  const handleAssignRoute = (
    name: string,
    assignedTo: string,
    assignedTeam: string,
    meetingPoint: boolean,
    visibleTo: string[],
    isZone: boolean,
    zoneType: Route["zoneType"]
  ) => {
    const coordinates = pendingRoute.map(wp => [wp.lat, wp.lng] as [number, number]);
    const tempId = `route_${Date.now()}`;
    const newRoute: Route = {
      id: tempId,
      name,
      assignedTo,
      assignedTeam,
      waypoints: pendingRoute,
      createdAt: new Date(),
      color: isZone ? "#ec4899" : ["#3b82f6", "#06b6d4", "#8b5cf6", "#f97316", "#84cc16"][routes.length % 5],
      meetingPoint,
      visibleTo,
      coordinates,
      isZone,
      zoneType,
      isActive: true,
    };

    setRoutes(prev => [...prev, newRoute]);
    setEvents(prev => [...prev, {
      id: `route_ev_${Date.now()}`, time: new Date(), type: isZone ? "ZONE" : "ROUTE",
      user: "Commander", team: "Team Alpha",
      event: `${isZone ? "Zone" : "Route"} "${name}" assigned to ${assignedTeam === "ALL" ? "all teams" : (dbTeams.find(t => t.id === assignedTeam)?.name ?? assignedTeam)}`,
      location: "Command",
    }]);

    if (isConnectedRef.current) {
      const assignedTeamId = assignedTeam === "ALL" ? undefined : assignedTeam;
      const visibleToTeams = visibleTo.filter(id => dbTeams.some(team => team.id === id));
      const visibleToUsers = visibleTo.filter(id => users.some(user => user.user_id === id));
      api.createRoute({
        name,
        is_zone: isZone,
        zone_type: isZone ? zoneType : undefined,
        meeting_point: meetingPoint,
        color: newRoute.color,
        assigned_team_id: assignedTeamId,
        assigned_user_id: assignedTo !== "ALL" ? assignedTo : undefined,
        visible_to_all: visibleTo.includes("ALL"),
        visible_to_teams: visibleToTeams,
        visible_to_users: visibleToUsers,
        waypoints: pendingRoute.map((wp, i) => ({
          latitude: wp.lat,
          longitude: wp.lng,
          label: wp.label,
          poi_type: wp.type,
          sequence_order: i,
        })),
      }).then((res: { data: { id: string } }) => {
        setRoutes(prev => prev.map(r => r.id === tempId ? { ...r, id: String(res.data.id) } : r));
      }).catch(console.warn);
    }

    setShowRouteModal(false);
    setRouteDrawMode(false);
    setZoneMode(false);
    setPendingRoute([]);
  };

  const handleCompleteRoute = async (routeId: string) => {
    try {
      const activeSessionResponse = await api.listRouteFollowSessions({ route_id: routeId, status: "active" });
      const activeSessions = (activeSessionResponse.data ?? []) as Array<{ id: string }>;
      if (activeSessions.length === 0) return;
      await api.completeRouteFollowSession(activeSessions[0].id, { completion_note: "Confirmed by commander" });
      await refreshRoutesAndPois();
    } catch (error) {
      console.warn("Failed to complete route", error);
    }
  };

  const handleDeactivatePOI = async (poiId: string) => {
    setPois(prev => prev.filter(p => p.id !== poiId));
    if (isConnectedRef.current) {
      try {
        await api.deletePOI(poiId);
      } catch (error) {
        console.warn("Failed to deactivate POI", error);
      }
    }
  };

  // ── Force management handlers ────────────────────────────────────────────
  const handleLocateUser = (userId: string) => {
    const user = users.find(u => u.user_id === userId);
    if (user) {
      setMapFlyTarget({ lat: user.lat, lng: user.lng });
      setSelectedUser(user);
    }
  };

  const handleRemoveFromTeam = async (userId: string, teamId: string) => {
    try {
      await api.removeTeamMember(teamId, userId);
      setDbAllUsers(prev => prev.map(u => u.id === userId ? { ...u, teamId: undefined, teamName: undefined, teamRole: undefined } : u));
    } catch { /* silent */ }
  };

  const handleForceRefresh = async () => {
    await loadData();
  };

  const handlePrimaryForceAction = () => {
    if (currentUserRole === "admin" || currentUserRole === "super_admin") {
      setShowCreateUser(true);
      return;
    }
    setShowAssignPicker(true);
  };

  const handleExport = () => {
    const data = JSON.stringify({ users, events, routes, pois, exportedAt: new Date().toISOString() }, null, 2);
    const blob = new Blob([data], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `drd_field_export_${Date.now()}.json`; a.click();
    URL.revokeObjectURL(url);
  };

  const filteredUsers = teamFilter === "All" ? users : users.filter(u => u.group === teamFilter);
  const alertCount = users.filter(u => u.status === "offline" || u.flag === "help").length;
  const mapTileConfig = MAP_TILES[mapView];

  return (
    <div className={`w-screen h-screen bg-background flex flex-col overflow-hidden ${isFullscreen ? "fixed inset-0 z-[3000]" : ""}`}>
      {isLoading && (
        <div className="fixed inset-0 bg-slate-950/80 z-9999 flex flex-col items-center justify-center gap-3" style={{ fontFamily: "'Poppins', sans-serif" }}>
          <div className="w-10 h-10 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
          <div className="text-slate-400 text-xs tracking-widest">LOADING FIELD DATA...</div>
        </div>
      )}
      <TopBar
        users={users}
        sidebarOpen={sidebarOpen}
        onToggleSidebar={() => setSidebarOpen(!sidebarOpen)}
        isConnected={isConnected}
        currentUser={currentUser}
        onLogout={() => {
          api.logout().catch(() => { });
          localStorage.removeItem("access_token");
          localStorage.removeItem("refresh_token");
          disconnectAll();
          window.location.href = "/login";
        }}
      />

      <div className="flex-1 flex overflow-hidden relative">
        {/* Map Area */}
        <div className="flex-1 flex flex-col overflow-hidden">
          <div className="flex-1 relative">
            <MapContainer
              center={browserPosition ? [browserPosition.lat, browserPosition.lng] : MAP_CENTER}
              zoom={13}
              className="w-full h-full"
              zoomControl={false}
              key={mapView}
            >
              <TileLayer
                attribution={mapTileConfig.attribution}
                url={mapTileConfig.url}
              />

              <MapEventsHandler onMapClick={handleMapClick} routeDrawMode={routeDrawMode || zoneMode} />
              <MapFlyController target={mapFlyTarget} />

              {/* POI Markers */}
              {pois.map(poi => (
                <Marker
                  key={poi.id}
                  position={[poi.lat, poi.lng]}
                  icon={createPOIIcon(poi)}
                >
                  <Popup>
                    <div className="text-xs" style={{ fontFamily: "'Poppins', sans-serif" }}>
                      <div className="font-bold text-sm">{POI_ICONS_CONFIG[poi.type].icon} {poi.label}</div>
                      <div className="text-slate-500 mt-1">Type: {POI_ICONS_CONFIG[poi.type].label}</div>
                      <div className="text-slate-500">Status: {poi.status || "N/A"}</div>
                      {poi.team && <div className="text-slate-500">Team: {poi.team}</div>}
                      <button
                        onClick={() => handleDeactivatePOI(poi.id)}
                        className="mt-2 w-full px-2 py-1 bg-red-500/20 border border-red-500/50 rounded text-[10px] text-red-400 hover:bg-red-500/30 transition-colors"
                      >
                        Deactivate
                      </button>
                    </div>
                  </Popup>
                </Marker>
              ))}

              {/* Team grouping lines — connect same-team members within ~400m */}
              {(() => {
                const lines: React.ReactNode[] = [];
                const teamGroups = new Map<string, typeof filteredUsers>();
                for (const u of filteredUsers) {
                  const key = u.group;
                  if (!teamGroups.has(key)) teamGroups.set(key, []);
                  teamGroups.get(key)!.push(u);
                }
                teamGroups.forEach((members, team) => {
                  if (members.length < 2) return;
                  const col = TEAM_COLORS[team as Team]?.primary ?? "#3b82f6";
                  for (let i = 0; i < members.length; i++) {
                    for (let j = i + 1; j < members.length; j++) {
                      const a = members[i], b = members[j];
                      const dist = distanceKm(a.lat, a.lng, b.lat, b.lng);
                      if (dist <= 0.4) {
                        lines.push(
                          <Polyline
                            key={`grp-${a.user_id}-${b.user_id}`}
                            positions={[[a.lat, a.lng], [b.lat, b.lng]]}
                            color={col}
                            weight={1.5}
                            opacity={0.45}
                            dashArray="4 6"
                          />
                        );
                      }
                    }
                  }
                });
                return lines;
              })()}

              {/* User Markers */}
              {filteredUsers.map(user => (
                <Marker
                  key={user.user_id}
                  position={[user.lat, user.lng]}
                  icon={createUserIcon(user, selectedUser?.user_id === user.user_id)}
                  eventHandlers={{ click: () => focusUserOnMap(user) }}
                >
                  <Tooltip direction="top" offset={[0, -18]} opacity={0.95}>
                    <div className="text-[9px] md:text-[10px] text-center" style={{ fontFamily: "'Poppins', sans-serif" }}>
                      <div className="font-bold">{user.name}</div>
                      <div className="text-slate-500">{user.group} · {formatElapsed(user.lastUpdate)}</div>
                      {user.speed != null && <div className="text-slate-400">{user.speed.toFixed(1)} km/h · {user.heading || 0}°</div>}
                    </div>
                  </Tooltip>
                </Marker>
              ))}

              {/* Routes */}
              {routes.map(route => (
                <RoutePath key={route.id} route={route} />
              ))}

              {/* Zone polygons */}
              {routes.filter(r => r.isZone).map(zone => (
                <Polygon
                  key={`zone-${zone.id}`}
                  positions={zone.coordinates}
                  pathOptions={{
                    color: zone.color,
                    fillColor: zone.color,
                    fillOpacity: 0.1,
                    weight: 2,
                    dashArray: "5 10",
                  }}
                >
                  <Popup>
                    <div className="text-xs" style={{ fontFamily: "'Poppins', sans-serif" }}>
                      <div className="font-bold">{zone.name}</div>
                      <div className="text-slate-500">Type: {zone.zoneType}</div>
                      <div className="text-slate-500">Team: {zone.assignedTeam ? (dbTeams.find(t => t.id === zone.assignedTeam)?.name ?? "All") : "All"}</div>
                    </div>
                  </Popup>
                </Polygon>
              ))}

              {/* Pending route */}
              {pendingRoute.length >= 2 && (
                zoneMode ? (
                  <Polygon
                    positions={pendingRoute.map(wp => [wp.lat, wp.lng] as [number, number])}
                    pathOptions={{
                      color: "#ec4899",
                      fillColor: "#ec4899",
                      fillOpacity: 0.1,
                      weight: 2,
                      dashArray: "5 10",
                    }}
                  />
                ) : (
                  <Polyline
                    positions={pendingRoute.map(wp => [wp.lat, wp.lng] as [number, number])}
                    color="#60a5fa"
                    weight={3}
                    dashArray="8 4"
                    opacity={0.8}
                  />
                )
              )}

              {/* Pending waypoints */}
              {pendingRoute.map((wp, i) => (
                <CircleMarker
                  key={i}
                  center={[wp.lat, wp.lng]}
                  radius={5}
                  pathOptions={{
                    color: zoneMode ? "#ec4899" : "#3b82f6",
                    fillColor: zoneMode ? "#ec4899" : "#3b82f6",
                    fillOpacity: 1,
                  }}
                >
                  <Tooltip permanent direction="top">
                    <span className="text-[9px] font-bold" style={{ fontFamily: "'Poppins', sans-serif" }}>{wp.label}</span>
                  </Tooltip>
                </CircleMarker>
              ))}
            </MapContainer>

            {/* Map Controls */}
            <div className="absolute top-3 left-3 z-[1000] bg-slate-900/95 border border-white/10 rounded-lg overflow-hidden shadow-lg">
              <button onClick={() => { }} className="w-9 h-9 flex items-center justify-center text-slate-400 hover:text-foreground border-b border-white/5 transition-colors" title="Zoom In">
                <FiPlus size={14} />
              </button>
              <button onClick={() => { }} className="w-9 h-9 flex items-center justify-center text-slate-400 hover:text-foreground border-b border-white/5 transition-colors" title="Zoom Out">
                <FiMinus size={14} />
              </button>
              <button onClick={() => { }} className="w-9 h-9 flex items-center justify-center text-slate-400 hover:text-foreground border-b border-white/5 transition-colors" title="Fullscreen">
                <FiMaximize2 size={14} />
              </button>
              <button onClick={() => setMapView(prev => {
                const views: MapViewType[] = ["standard", "satellite", "terrain", "dark"];
                const idx = views.indexOf(prev);
                return views[(idx + 1) % views.length];
              })} className="w-9 h-9 flex items-center justify-center text-slate-400 hover:text-foreground transition-colors" title="Change Map View">
                {MAP_TILES[mapView].icon}
              </button>
            </div>

            {/* Map View Selector */}
            <div className="absolute top-3 left-[52px] z-[1000] bg-slate-900/95 border border-white/10 rounded-lg p-1.5 flex gap-1 shadow-lg">
              {(Object.entries(MAP_TILES) as [MapViewType, typeof MAP_TILES[MapViewType]][]).map(([key, config]) => (
                <button
                  key={key}
                  onClick={() => setMapView(key)}
                  className="px-2 py-1.5 rounded text-[10px] font-medium transition-all flex items-center gap-1"
                  style={{
                    backgroundColor: mapView === key ? "rgba(59,130,246,0.25)" : "transparent",
                    color: mapView === key ? "#60a5fa" : "#94a3b8",
                  }}
                  title={config.label}
                >
                  {config.icon}
                  <span className="hidden md:inline">{config.label}</span>
                </button>
              ))}
            </div>

            {/* Mode indicators */}
            {(routeDrawMode || zoneMode) && (
              <div className="absolute top-14 left-1/2 -translate-x-1/2 z-[1000] bg-slate-900/95 border border-white/10 rounded-lg px-3 py-2 text-white text-[11px] md:text-xs font-semibold flex items-center gap-2 shadow-lg animate-fadeIn flex-wrap">
                {zoneMode ? (
                  <>
                    <FiHexagon size={14} color="#ec4899" />
                    <span>Zone Mode: Click to define area ({pendingRoute.length} points)</span>
                  </>
                ) : (
                  <>
                    <TbRoute size={14} color="#3b82f6" />
                    <span>Route Mode: Click to add waypoints ({pendingRoute.length})</span>
                  </>
                )}
                {pendingRoute.length >= 2 && (
                  <button onClick={handleRouteMode} className="px-2 py-0.5 bg-primary/20 rounded text-[10px] hover:bg-primary/30 transition-colors">
                    Finish
                  </button>
                )}
                <button onClick={() => { setRouteDrawMode(false); setZoneMode(false); setPendingRoute([]); }} className="px-2 py-0.5 bg-white/10 rounded text-[10px] hover:bg-white/20 transition-colors">
                  Cancel
                </button>
              </div>
            )}

            {/* Alert badge */}
            {alertCount > 0 && (
              <div className="absolute top-3 right-3 z-[1000] bg-red-500/95 rounded-full px-2.5 py-1 text-white text-[10px] md:text-xs font-bold flex items-center gap-1.5 shadow-lg">
                <FiAlertTriangle size={12} />
                {alertCount}
              </div>
            )}
          </div>

          <MapLegend />
          <EventsLog events={events} onViewAll={() => setShowAllEvents(true)} />
        </div>

        {/* Sidebar */}
        <div
          className={`sidebar-panel w-[300px] md:w-[320px] flex-shrink-0 bg-slate-950 border-l border-white/10 flex flex-col
            ${sidebarOpen ? "translate-x-0" : "translate-x-full md:translate-x-0"}
            transition-transform duration-300 z-[2000] md:z-auto`}
          style={{ height: 'calc(100vh - 48px)' }}
        >
          <div className="flex-1 overflow-y-auto custom-scrollbar space-y-2 p-2">
            <TeamOverviewPanel
              users={users}
              dbTeams={dbTeams}
              isLoading={isLoading}
              expanded={panels.teamOverview}
              onToggle={() => togglePanel("teamOverview")}
              onSelectTeam={handleSelectTeam}
            />
            <SelectedUserPanel
              user={selectedUser}
              expanded={panels.selectedUser}
              onToggle={() => togglePanel("selectedUser")}
              onFlag={handleFlag}
              onMessage={(uid) => setMsgModal(uid)}
              onCreateRoute={handleCreateRouteForUser}
            />
            <AlertsPanel
              users={users}
              expanded={panels.alerts}
              onToggle={() => togglePanel("alerts")}
              onAlertClick={(u) => {
                focusUserOnMap(u);
                if (u.flag === "help") {
                  openSOSIncident(u, `${u.name} requested SOS support`, u.flagTime || new Date());
                }
              }}
            />
            <RoutesPanel
              routes={routes}
              routeHistory={routeHistory}
              users={users}
              browserPosition={browserPosition}
              expanded={panels.routes}
              onToggle={() => togglePanel("routes")}
              onCompleteRoute={handleCompleteRoute}
            />
            <QuickActionsPanel
              expanded={panels.quickActions}
              onToggle={() => togglePanel("quickActions")}
              onExport={handleExport}
              onRefresh={loadData}
              onMessageAll={() => setMsgModal("ALL")}
              onTeamFilter={handleTeamFilter}
              teamFilter={teamFilter}
              onRouteMode={handleRouteMode}
              routeDrawMode={routeDrawMode}
              poiType={selectedPOIType}
              onPOITypeChange={setSelectedPOIType}
              onZoneMode={handleZoneMode}
              zoneMode={zoneMode}
            />
            <CommsPanel
              messages={messages}
              users={users}
              expanded={panels.comms}
              onToggle={() => togglePanel("comms")}
              onSend={handleSendMessage}
            />
            <ForceManagementPanel
              expanded={forceExpanded}
              onToggle={() => setForceExpanded(p => !p)}
              allUsers={dbAllUsers}
              dbTeams={dbTeams}
              isLoading={isLoading}
              onCreateUser={handlePrimaryForceAction}
              onCreateTeam={() => setShowCreateTeam(true)}
              onAssignTeam={(uid) => setAssigningUserId(uid)}
              onRemoveFromTeam={handleRemoveFromTeam}
              onLocate={handleLocateUser}
            // currentRole={currentUserRole}
            />
          </div>
        </div>

        {/* Mobile sidebar overlay */}
        {sidebarOpen && (
          <div
            className="fixed inset-0 bg-black/50 z-[1999] md:hidden"
            onClick={() => setSidebarOpen(false)}
          />
        )}
      </div>

      {/* Modals */}
      {sosIncident !== null && (
        <SOSIncidentModal
          incident={sosIncident}
          users={users}
          onClose={() => setSosIncident(null)}
          onOpenComms={handleOpenSOSComms}
          onDispatchUnits={handleAutoDispatchSOSUnits}
          onFocus={(lat, lng) => setMapFlyTarget({ lat, lng })}
        />
      )}

      {msgModal !== null && (
        <MessageModal
          toUserId={msgModal === "ALL" ? null : msgModal}
          users={users}
          messages={messages}
          onSend={handleSendMessage}
          onClose={() => setMsgModal(null)}
        />
      )}

      {showRouteModal && (
        <RouteModal
          pendingRoute={pendingRoute}
          users={users}
          dbTeams={dbTeams}
          onAssign={handleAssignRoute}
          onCancel={() => { setShowRouteModal(false); setRouteDrawMode(false); setZoneMode(false); setPendingRoute([]); }}
        />
      )}

      {showPOIModal && pendingPOI && (
        <POIVisibilityModal
          poi={pendingPOI}
          users={users}
          dbTeams={dbTeams}
          onSave={handleSavePOIVisibility}
          onClose={() => { setShowPOIModal(false); }}
        />
      )}

      {showAllEvents && (
        <AllEventsModal onClose={() => setShowAllEvents(false)} />
      )}

      {showCreateUser && (
        <CreateUserModal
          dbTeams={dbTeams}
          onClose={() => setShowCreateUser(false)}
          onSaved={handleForceRefresh}
        />
      )}

      {showCreateTeam && (
        <CreateTeamModal
          onClose={() => setShowCreateTeam(false)}
          onSaved={handleForceRefresh}
        />
      )}

      {(assigningUserId || showAssignPicker) && (
        <AssignTeamModal
          userId={assigningUserId}
          dbTeams={dbTeams}
          allUsers={dbAllUsers}
          onClose={() => {
            setAssigningUserId(null);
            setShowAssignPicker(false);
          }}
          onSaved={handleForceRefresh}
        />
      )}
    </div>
  );
}