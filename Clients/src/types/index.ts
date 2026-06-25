export type UserRole = "operations_coordinator" | "planning_officer" | "team_leader" | "field_user";
export type LocationStatus = "active" | "stale" | "offline";
export type MissionStatus = "draft" | "planned" | "active" | "suspended" | "completed" | "archived";

export interface User {
  id: string;
  email: string;
  username: string;
  full_name: string;
  role: UserRole;
  phone?: string;
  avatar_url?: string;
  is_active: boolean;
  is_verified: boolean;
  last_seen?: string;
  created_at: string;
}

export interface Team {
  id: string;
  name: string;
  description?: string;
  leader_id?: string;
  color: string;
  icon?: string;
  is_active: boolean;
  created_at: string;
  member_count?: number;
}

export interface TeamMember {
  id: string;
  team_id: string;
  user_id: string;
  role_in_team: string;
  joined_at: string;
  user?: User;
}

export interface Location {
  user_id: string;
  latitude: number;
  longitude: number;
  altitude?: number;
  heading?: number;
  speed?: number;
  status: LocationStatus;
  last_updated: string;
}

export interface Invite {
  id: string;
  code: string;
  invite_type: "qr" | "voucher";
  assigned_role: UserRole;
  is_active: boolean;
  max_uses: number;
  use_count: number;
  expires_at?: string;
  note?: string;
  created_at: string;
}

export interface AuditLog {
  id: string;
  user_id?: string;
  action: string;
  entity_type?: string;
  entity_id?: string;
  path?: string;
  method?: string;
  status_code?: number;
  ip_address?: string;
  timestamp: string;
}

export interface AuthState {
  user: User | null;
  access_token: string | null;
  refresh_token: string | null;
  isAuthenticated: boolean;
}

export type MissionStatusType = "draft" | "planned" | "active" | "suspended" | "completed" | "archived";

export interface MissionObjective {
  id: string;
  title: string;
  description?: string;
  is_completed: boolean;
  order_index: number;
}

export interface Mission {
  id: string;
  name: string;
  description?: string;
  status: MissionStatusType;
  created_by?: string;
  start_date?: string;
  end_date?: string;
  briefing_notes?: string;
  area_of_operations?: string;
  created_at: string;
  updated_at: string;
  objectives: MissionObjective[];
  assignments: { id: string; team_id?: string; user_id?: string; role_in_mission?: string }[];
}

export interface Message {
  id: string;
  content: string;
  sender_id: string;
  sender?: User;
  channel: string;
  message_type: string;
  sent_at: string;
  is_read?: boolean;
}

export interface Notification {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body?: string;
  ref_id?: string;
  ref_type?: string;
  is_read: boolean;
  priority: string;
  created_at: string;
}

export interface LiveLocation {
  user_id: string;
  latitude: number;
  longitude: number;
  altitude?: number;
  heading?: number;
  speed?: number;
  accuracy?: number;
  status: LocationStatus;
  last_updated: string;
  user?: User & { team?: string };
}

export interface Contact {
  id: string;
  name: string;
  contact_type: "confirmed" | "suspected" | "unknown" | "neutral" | "obstacle" | "poi";
  latitude: number;
  longitude: number;
  altitude?: number;
  description?: string;
  callsign?: string;
  team_id?: string;
  mission_id?: string;
  created_by?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Route {
  id: string;
  name: string;
  description?: string;
  route_type: string;
  created_by?: string;
  created_at: string;
  waypoints?: { id: string; latitude: number; longitude: number; order_index: number; name?: string }[];
}
