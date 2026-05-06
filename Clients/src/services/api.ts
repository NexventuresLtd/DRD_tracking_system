import axios from 'axios';

const BASE_URL = import.meta.env.VITE_API_URL || 'https://drd.nexventures.net/';
console.log(`API Base URL: ${BASE_URL}`);
const api = axios.create({
  baseURL: BASE_URL,
  headers: { 'Content-Type': 'application/json' },
  timeout: 10000,
});

api.interceptors.request.use(config => {
  const token = localStorage.getItem('access_token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  res => res,
  async err => {
    const original = err.config;
    if (err.response?.status === 401 && !original._retry) {
      original._retry = true;
      const refresh = localStorage.getItem('refresh_token');
      if (refresh) {
        try {
          const { data } = await axios.post(`${BASE_URL}/api/v1/auth/refresh`, { refresh_token: refresh });
          localStorage.setItem('access_token', data.access_token);
          if (data.refresh_token) localStorage.setItem('refresh_token', data.refresh_token);
          original.headers.Authorization = `Bearer ${data.access_token}`;
          return api.request(original);
        } catch {
          localStorage.removeItem('access_token');
          localStorage.removeItem('refresh_token');
        }
      }
    }
    return Promise.reject(err);
  }
);

// ── Auth ──────────────────────────────────────────────────────────────────────
// Backend accepts username OR email in the `username` field
export const login = (identifier: string, password: string) =>
  api.post('/api/v1/auth/login', { username: identifier, password });

export const register = (data: object) => api.post('/api/v1/auth/register', data);
export const getMe = () => api.get('/api/v1/auth/me');
export const logout = () => api.post('/api/v1/auth/logout');
export const changePassword = (data: object) => api.put('/api/v1/auth/change-password', data);

// ── Users ─────────────────────────────────────────────────────────────────────
export const listUsers = (params?: object) => api.get('/api/v1/users', { params });
export const createUser = (data: object) => api.post('/api/v1/users', data);
export const getUser = (id: string) => api.get(`/api/v1/users/${id}`);
export const updateUser = (id: string, data: object) => api.put(`/api/v1/users/${id}`, data);
export const deleteUser = (id: string) => api.delete(`/api/v1/users/${id}`);

// ── Teams ─────────────────────────────────────────────────────────────────────
export const listTeams = (params?: object) => api.get('/api/v1/teams', { params });
export const createTeam = (data: object) => api.post('/api/v1/teams', data);
export const getTeam = (id: string) => api.get(`/api/v1/teams/${id}`);
export const updateTeam = (id: string, data: object) => api.put(`/api/v1/teams/${id}`, data);
export const addTeamMember = (teamId: string, data: object) =>
  api.post(`/api/v1/teams/${teamId}/members`, data);
export const removeTeamMember = (teamId: string, userId: string) =>
  api.delete(`/api/v1/teams/${teamId}/members/${userId}`);

// ── Locations ─────────────────────────────────────────────────────────────────
export const getActiveLocations = (teamId?: string) =>
  api.get('/api/v1/locations', { params: teamId ? { team_id: teamId } : undefined });
export const getUserLocation = (userId: string) => api.get(`/api/v1/locations/${userId}`);
export const getUserLocationHistory = (userId: string, params?: object) =>
  api.get(`/api/v1/locations/${userId}/history`, { params });
export const updateLocation = (data: object) => api.post('/api/v1/locations', data);
export const getLocationsInBounds = (data: object) => api.post('/api/v1/locations/geofence', data);

// ── Routes ────────────────────────────────────────────────────────────────────
export const listRoutes = (params?: object) => api.get('/api/v1/routes', { params });
export const listRouteHistory = (params?: object) => api.get('/api/v1/routes/history', { params });
export const createRoute = (data: object) => api.post('/api/v1/routes', data);
export const getRoute = (id: string) => api.get(`/api/v1/routes/${id}`);
export const updateRoute = (id: string, data: object) => api.put(`/api/v1/routes/${id}`, data);
export const deleteRoute = (id: string) => api.delete(`/api/v1/routes/${id}`);
export const addWaypoint = (routeId: string, data: object) =>
  api.post(`/api/v1/routes/${routeId}/waypoints`, data);
export const listRouteFollowSessions = (params?: object) => api.get('/api/v1/route-follow-sessions', { params });
export const getMyRouteFollowSession = () => api.get('/api/v1/route-follow-sessions/me');
export const completeRouteFollowSession = (sessionId: string, data?: object) =>
  api.post(`/api/v1/route-follow-sessions/${sessionId}/complete`, data ?? {});

// ── POIs ──────────────────────────────────────────────────────────────────────
export const listPOIs = (params?: object) => api.get('/api/v1/pois', { params });
export const createPOI = (data: object) => api.post('/api/v1/pois', data);
export const getPOI = (id: string) => api.get(`/api/v1/pois/${id}`);
export const updatePOI = (id: string, data: object) => api.put(`/api/v1/pois/${id}`, data);
export const deletePOI = (id: string) => api.delete(`/api/v1/pois/${id}`);
export const updatePOIVisibility = (id: string, data: object) =>
  api.put(`/api/v1/pois/${id}/visibility`, data);

// ── Messages ──────────────────────────────────────────────────────────────────
export const listMessages = (params?: object) => api.get('/api/v1/messages', { params });
export const sendMessage = (data: object) => api.post('/api/v1/messages', data);
export const broadcastMessage = (data: object) => api.post('/api/v1/messages/broadcast', data);
export const markMessageRead = (id: string) => api.put(`/api/v1/messages/${id}/read`);
export const markAllRead = () => api.put('/api/v1/messages/read-all');

// ── Events ────────────────────────────────────────────────────────────────────
export const listEvents = (params?: object) => api.get('/api/v1/events', { params });
export const createEvent = (data: object) => api.post('/api/v1/events', data);
export const getEventStats = (days?: number) =>
  api.get('/api/v1/events/stats', { params: days ? { days } : undefined });

// ── Zones ─────────────────────────────────────────────────────────────────────
export const listZones = (params?: object) => api.get('/api/v1/zones', { params });
export const createZone = (data: object) => api.post('/api/v1/zones', data);
export const updateZone = (id: string, data: object) => api.put(`/api/v1/zones/${id}`, data);
export const deleteZone = (id: string) => api.delete(`/api/v1/zones/${id}`);
export const assignZone = (zoneId: string, data: object) =>
  api.post(`/api/v1/zones/${zoneId}/assign`, data);

// ── Evidence ──────────────────────────────────────────────────────────────────
export const getPOIEvidence = (poiId: string) => api.get(`/api/v1/evidence/poi/${poiId}`);
export const getMessageEvidence = (messageId: string) => api.get(`/api/v1/evidence/message/${messageId}`);
export const deleteEvidence = (id: string) => api.delete(`/api/v1/evidence/${id}`);

export default api;
