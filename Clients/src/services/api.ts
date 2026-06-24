import axios from "axios";
import type { AxiosInstance } from "axios";

const BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:1104";

export const mediaUrl = (path: string | null | undefined): string | undefined => {
  if (!path) return undefined;
  if (path.startsWith("http")) return path;
  return `${BASE_URL}${path}`;
};

const api: AxiosInstance = axios.create({
  baseURL: `${BASE_URL}/api/v1`,
  headers: { "Content-Type": "application/json" },
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem("access_token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  (res) => res,
  async (error) => {
    if (error.response?.status === 401) {
      const refresh = localStorage.getItem("refresh_token");
      if (refresh) {
        try {
          const { data } = await axios.post(`${BASE_URL}/api/v1/auth/refresh`, { refresh_token: refresh });
          localStorage.setItem("access_token", data.access_token);
          localStorage.setItem("refresh_token", data.refresh_token);
          error.config.headers.Authorization = `Bearer ${data.access_token}`;
          return api(error.config);
        } catch {
          localStorage.clear();
          window.location.href = "/login";
        }
      } else {
        localStorage.clear();
        window.location.href = "/login";
      }
    }
    return Promise.reject(error);
  }
);

export default api;

export const authApi = {
  login: (email: string, password: string) => api.post("/auth/login", { email, password }),
  verifyOtp: (otp_session: string, otp_code: string) =>
    api.post("/auth/verify-otp", { otp_session, otp_code }),
  resendOtp: (otp_session: string) => api.post("/auth/resend-otp", { otp_session }),
  register: (data: object) => api.post("/auth/register", data),
  me: () => api.get("/auth/me"),
  logout: (refresh_token: string) => api.post("/auth/logout", { refresh_token }),
  forgotPassword: (email: string) => api.post("/auth/forgot-password", { email }),
  resetPassword: (token: string, new_password: string) => api.post("/auth/reset-password", { token, new_password }),
};

export const userApi = {
  list: (params?: object) => api.get("/users", { params }),
  getById: (id: string) => api.get(`/users/${id}`),
  update: (id: string, data: object) => api.put(`/users/${id}`, data),
  updateRole: (id: string, role: string) => api.put(`/users/${id}/role`, { role }),
  uploadAvatar: (id: string, file: File) => {
    const fd = new FormData();
    fd.append("file", file);
    return api.post(`/users/${id}/avatar`, fd, { headers: { "Content-Type": "multipart/form-data" } });
  },
  delete: (id: string) => api.delete(`/users/${id}`),
};

export const teamApi = {
  list: () => api.get("/teams"),
  create: (data: object) => api.post("/teams", data),
  getById: (id: string) => api.get(`/teams/${id}`),
  update: (id: string, data: object) => api.put(`/teams/${id}`, data),
  delete: (id: string) => api.delete(`/teams/${id}`),
  getMembers: (id: string) => api.get(`/teams/${id}/members`),
  addMember: (id: string, data: object) => api.post(`/teams/${id}/members`, data),
  removeMember: (teamId: string, userId: string) => api.delete(`/teams/${teamId}/members/${userId}`),
  getLocations: (id: string) => api.get(`/teams/${id}/locations`),
};

export const adminApi = {
  getUsers: (params?: object) => api.get("/admin/users", { params }),
  createUser: (data: object) => api.post("/admin/users", data),
  updateUser: (id: string, data: object) => api.patch(`/admin/users/${id}`, data),
  deleteUser: (id: string) => api.delete(`/admin/users/${id}`),
  resetPassword: (id: string, new_password: string) => api.post(`/admin/users/${id}/reset-password`, { new_password }),
  getStats: () => api.get("/admin/stats"),
  createInvite: (data: object) => api.post("/admin/invites", data),
  listInvites: () => api.get("/admin/invites"),
  revokeInvite: (id: string) => api.delete(`/admin/invites/${id}`),
  getInviteQR: (id: string) => api.get(`/admin/invites/${id}/qr`),
  getAuditLogs: (params?: object) => api.get("/admin/audit-logs", { params }),
};

export const missionApi = {
  list: (params?: object) => api.get("/missions", { params }),
  getById: (id: string) => api.get(`/missions/${id}`),
  create: (data: object) => api.post("/missions", data),
  update: (id: string, data: object) => api.put(`/missions/${id}`, data),
  delete: (id: string) => api.delete(`/missions/${id}`),
  assign: (id: string, data: object) => api.post(`/missions/${id}/assignments`, data),
  notify: (id: string, data: object) => api.post(`/missions/${id}/notify`, data),
  completeObjective: (missionId: string, objId: string) =>
    api.post(`/missions/${missionId}/objectives/${objId}/complete`),
  startBriefing: (id: string) => api.post(`/missions/${id}/start-briefing`),
  // Incidents
  listIncidents: (id: string) => api.get(`/missions/${id}/incidents`),
  reportIncident: (id: string, data: object) => api.post(`/missions/${id}/incidents`, data),
  resolveIncident: (missionId: string, incidentId: string) =>
    api.patch(`/missions/${missionId}/incidents/${incidentId}/resolve`),
  // Casualties
  listCasualties: (id: string) => api.get(`/missions/${id}/casualties`),
  reportCasualty: (id: string, data: object) => api.post(`/missions/${id}/casualties`, data),
  // Evidence approval
  listEvidence: (id: string) => api.get(`/missions/${id}/evidence`),
  approveEvidence: (missionId: string, evidenceId: string, action: "approve" | "reject") =>
    api.patch(`/missions/${missionId}/evidence/${evidenceId}/approve`, { action }),
  // Package download
  downloadPackage: (id: string) => api.get(`/missions/${id}/package`),
};

export const locationApi = {
  getLive: () => api.get("/locations/live"),
  getUser: (uid: string) => api.get(`/locations/${uid}`),
  getHistory: (uid: string, params?: object) => api.get(`/locations/${uid}/history`, { params }),
  updateLocation: (data: object) => api.post("/locations", data),
};

export const contactApi = {
  list: (params?: object) => api.get("/contacts", { params }),
  getById: (id: string) => api.get(`/contacts/${id}`),
  create: (data: object) => api.post("/contacts", data),
  update: (id: string, data: object) => api.put(`/contacts/${id}`, data),
  delete: (id: string) => api.delete(`/contacts/${id}`),
};

export const drawingApi = {
  list: (params?: object) => api.get("/drawings", { params }),
  create: (data: object) => api.post("/drawings", data),
  delete: (id: string) => api.delete(`/drawings/${id}`),
};

export const notificationApi = {
  list: (params?: object) => api.get("/notifications", { params }),
  unreadCount: () => api.get("/notifications/unread-count"),
  markRead: (id: string) => api.put(`/notifications/${id}/read`),
  markAllRead: () => api.put("/notifications/read-all"),
};

export const messageApi = {
  getGlobal: () => api.get("/messages/channels/global"),
  getTeam: (teamId: string) => api.get(`/messages/channels/team/${teamId}`),
  getDM: (uid: string) => api.get(`/messages/channels/dm/${uid}`),
  send: (data: object) => api.post("/messages", data),
  markRead: (id: string) => api.put(`/messages/${id}/read`),
};

export const sosApi = {
  list: () => api.get("/sos"),
  trigger: (data: object) => api.post("/sos", data),
  acknowledge: (id: string) => api.put(`/sos/${id}/acknowledge`),
  resolve: (id: string) => api.put(`/sos/${id}/resolve`),
};

export const geofenceApi = {
  list: () => api.get("/geofences"),
  create: (data: object) => api.post("/geofences", data),
  delete: (id: string) => api.delete(`/geofences/${id}`),
};

export const routeApi = {
  list: () => api.get("/routes"),
  getById: (id: string) => api.get(`/routes/${id}`),
  create: (data: object) => api.post("/routes", data),
  delete: (id: string) => api.delete(`/routes/${id}`),
};

export const evidenceApi = {
  list: () => api.get("/evidence"),
  upload: (formData: FormData) => api.post("/evidence", formData, { headers: { "Content-Type": "multipart/form-data" } }),
  delete: (id: string) => api.delete(`/evidence/${id}`),
};

export const liveFeedApi = {
  list: () => api.get("/live-sessions"),
  listPast: (params?: object) => api.get("/live-sessions/past", { params }),
  create: (data: object) => api.post("/live-sessions", data),
  end: (id: string) => api.post(`/live-sessions/${id}/end`),
};

export const evidenceApi2 = {
  list: () => api.get("/evidence"),
  upload: (formData: FormData) => api.post("/evidence", formData, { headers: { "Content-Type": "multipart/form-data" } }),
  delete: (id: string) => api.delete(`/evidence/${id}`),
};

export const postsApi = {
  list: (params?: object) => api.get("/posts", { params }),
  create: (data: object) => api.post("/posts", data),
  getById: (id: string) => api.get(`/posts/${id}`),
  update: (id: string, data: object) => api.put(`/posts/${id}`, data),
  delete: (id: string) => api.delete(`/posts/${id}`),
  togglePublish: (id: string) => api.post(`/posts/${id}/publish`),
  grantAccess: (id: string, user_id: string) => api.post(`/posts/${id}/grant-access`, { user_id }),
  revokeAccess: (id: string, userId: string) => api.delete(`/posts/${id}/grant-access/${userId}`),
  mapPosts: () => api.get("/posts/map/published"),
  setThreatLevel: (id: string, threat_level: string) => api.patch(`/posts/${id}/threat-level`, { threat_level }),
  searchCommanders: (q: string) => api.get("/posts/search/commanders", { params: { q } }),
};

export const zonesApi = {
  list: () => api.get("/zones"),
  create: (data: object) => api.post("/zones", data),
  update: (id: string, data: object) => api.put(`/zones/${id}`, data),
  delete: (id: string) => api.delete(`/zones/${id}`),
  assignTeam: (id: string, team_id: string | null, status?: string) =>
    api.put(`/zones/${id}/assign-team`, { team_id, assignment_status: status ?? "assigned" }),
  getAssignments: (id: string) => api.get(`/zones/${id}/assignments`),
  createAssignment: (id: string, data: object) => api.post(`/zones/${id}/assignments`, data),
  updateAssignmentStatus: (zoneId: string, userId: string, status: string) =>
    api.put(`/zones/${zoneId}/assignments/${userId}/status`, { status }),
  removeAssignment: (zoneId: string, userId: string) =>
    api.delete(`/zones/${zoneId}/assignments/${userId}`),
  patrolReport: (id: string, data: object) => api.post(`/zones/${id}/patrol-report`, data),
  myAssignments: () => api.get("/zones/my/assignments"),
};
