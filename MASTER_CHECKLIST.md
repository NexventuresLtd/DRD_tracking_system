# DRD FIELD COORDINATION PLATFORM — MASTER IMPLEMENTATION CHECKLIST
**Version:** 1.0 | **Created:** 2026-06-23 | **Status:** PLANNING

---

## SESSION STATUS HEADER
```
Total Tasks    : 312
Completed      : ~230  (P1 + P2 full + P3 core)
Remaining      : ~82
Current Phase  : PHASE 3 COMPLETE (core) → Phase 4 remaining
Last Updated   : 2026-06-23

PHASE 2 + 3 COMPLETED (this session):
  Backend  : SOS API (trigger/ack/resolve + WS broadcast), Geofence API ✅
  React    : Routes (leaflet builder), Evidence (grid+upload), TeamDetail (members+map),
             SOS (broadcast+list+WS), Geofences (circles on map), LiveFeed (WebRTC) ✅
  Flutter  : SOSScreen (countdown+pulse), RouteFollowScreen (HUD+bearing arrow) ✅
  api.ts   : sosApi, geofenceApi, routeApi, evidenceApi, liveFeedApi added ✅
  tsc      : 0 errors   flutter analyze: 0 new issues ✅

PHASE 4 REMAINING:
  Backend  : Reticulum sidecar, Offline queue sync, Mission packages, Playback snapshots
  React    : Playback (/playback), Analytics (/analytics), Packages (/packages)
  Flutter  : Teams screen, Route list → RouteFollowScreen navigation
  Infra    : Docker Compose prod config, Nginx, Alembic migrations finalized
```

---

## EXISTING BASELINE

| Layer | Path | State |
|-------|------|-------|
| FastAPI skeleton | `Server/app/main.py` | Exists (all imports deleted) |
| FastAPI env | `Server/.env` | Exists |
| React Vite shell | `Clients/src/` | Bare (App.tsx + main.tsx only) |
| Flutter shell | `mobile/lib/main.dart` | Exists (providers/services missing) |
| Reticulum folder | `reticulum/` | Empty |

---

# PART 1 — DATABASE INVENTORY (39 Tables)

| ID | Table | Description | Phase | Status |
|----|-------|-------------|-------|--------|
| DB-01 | `users` | User accounts, roles, profile | 1 | Not Started |
| DB-02 | `user_sessions` | JWT refresh token sessions | 1 | Not Started |
| DB-03 | `user_devices` | Registered devices for push | 1 | Not Started |
| DB-04 | `invites` | QR/voucher enrollment tokens | 1 | Not Started |
| DB-05 | `teams` | Team groups with leader | 1 | Not Started |
| DB-06 | `team_members` | User–team membership | 1 | Not Started |
| DB-07 | `locations` | Live GPS location per user | 1 | Not Started |
| DB-08 | `location_history` | Historical GPS trail (PostGIS) | 1 | Not Started |
| DB-09 | `missions` | Mission records | 2 | Not Started |
| DB-10 | `mission_objectives` | Per-mission objectives | 2 | Not Started |
| DB-11 | `mission_assignments` | Team/user assignments per mission | 2 | Not Started |
| DB-12 | `routes` | Named routes with metadata | 2 | Not Started |
| DB-13 | `route_waypoints` | Ordered waypoints (PostGIS geometry) | 2 | Not Started |
| DB-14 | `route_assignments` | Route → user/team assignment + deadline | 2 | Not Started |
| DB-15 | `route_follow_sessions` | Active route-following telemetry | 2 | Not Started |
| DB-16 | `contacts` | Tactical contacts (POI/enemy/neutral) | 2 | Not Started |
| DB-17 | `drawings` | Map drawings (lines/polygons/circles) | 2 | Not Started |
| DB-18 | `drawing_points` | Ordered geometry points for drawings | 2 | Not Started |
| DB-19 | `geofences` | Geofence zone definitions (PostGIS) | 2 | Not Started |
| DB-20 | `geofence_events` | Entry/exit events per user/zone | 3 | Not Started |
| DB-21 | `pois` | Points of interest on map | 2 | Not Started |
| DB-22 | `evidence` | Evidence records (images/video/audio/notes) | 3 | Not Started |
| DB-23 | `messages` | Chat messages (all channel types) | 2 | Not Started |
| DB-24 | `message_reads` | Read receipts per message/user | 2 | Not Started |
| DB-25 | `message_attachments` | File attachments to messages | 2 | Not Started |
| DB-26 | `calls` | Voice/video call records | 3 | Not Started |
| DB-27 | `call_participants` | Participants per call | 3 | Not Started |
| DB-28 | `notifications` | In-app notification records | 2 | Not Started |
| DB-29 | `audit_logs` | System-wide audit trail | 1 | Not Started |
| DB-30 | `sos_events` | SOS broadcasts with acknowledgement | 3 | Not Started |
| DB-31 | `mission_packages` | Exportable mission data bundles | 4 | Not Started |
| DB-32 | `mission_package_items` | Items within a mission package | 4 | Not Started |
| DB-33 | `checkpoints` | Terrain checkpoints/reference points | 3 | Not Started |
| DB-34 | `zones` | Named operational zones | 2 | Not Started |
| DB-35 | `live_sessions` | WebRTC live stream sessions | 3 | Not Started |
| DB-36 | `resource_items` | Equipment/vehicle/resource tracking | 4 | Not Started |
| DB-37 | `playback_snapshots` | Periodic position snapshots for replay | 4 | Not Started |
| DB-38 | `reticulum_peers` | Known Reticulum mesh peers | 4 | Not Started |
| DB-39 | `offline_queue` | Queued operations for sync | 4 | Not Started |

---

# PART 2 — API INVENTORY (~160 Endpoints)

## Auth Module `/api/v1/auth`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-001 | POST | `/auth/register` | Register new user | 1 | Not Started |
| API-002 | POST | `/auth/login` | Login, get JWT pair | 1 | Not Started |
| API-003 | POST | `/auth/refresh` | Refresh access token | 1 | Not Started |
| API-004 | POST | `/auth/logout` | Invalidate session | 1 | Not Started |
| API-005 | POST | `/auth/forgot-password` | Send reset email | 1 | Not Started |
| API-006 | POST | `/auth/reset-password` | Apply new password | 1 | Not Started |
| API-007 | POST | `/auth/register-device` | Register push device | 1 | Not Started |
| API-008 | POST | `/auth/enroll/qr` | QR code enrollment | 1 | Not Started |
| API-009 | POST | `/auth/enroll/voucher` | Voucher enrollment | 1 | Not Started |
| API-010 | GET | `/auth/me` | Get current user | 1 | Not Started |

## Users Module `/api/v1/users`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-011 | GET | `/users` | List all users (admin/coord) | 1 | Not Started |
| API-012 | GET | `/users/{id}` | Get user profile | 1 | Not Started |
| API-013 | PUT | `/users/{id}` | Update user profile | 1 | Not Started |
| API-014 | DELETE | `/users/{id}` | Delete user (admin) | 1 | Not Started |
| API-015 | PUT | `/users/{id}/role` | Change user role | 1 | Not Started |
| API-016 | POST | `/users/{id}/avatar` | Upload avatar | 1 | Not Started |
| API-017 | GET | `/users/online` | List online users | 1 | Not Started |

## Teams Module `/api/v1/teams`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-018 | GET | `/teams` | List teams | 1 | Not Started |
| API-019 | POST | `/teams` | Create team | 1 | Not Started |
| API-020 | GET | `/teams/{id}` | Get team | 1 | Not Started |
| API-021 | PUT | `/teams/{id}` | Update team | 1 | Not Started |
| API-022 | DELETE | `/teams/{id}` | Delete team | 1 | Not Started |
| API-023 | POST | `/teams/{id}/members` | Add member | 1 | Not Started |
| API-024 | DELETE | `/teams/{id}/members/{uid}` | Remove member | 1 | Not Started |
| API-025 | GET | `/teams/{id}/members` | List members | 1 | Not Started |
| API-026 | GET | `/teams/{id}/locations` | Team live locations | 2 | Not Started |

## Locations Module `/api/v1/locations`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-027 | POST | `/locations` | Submit location update | 2 | Not Started |
| API-028 | GET | `/locations/live` | Get all live positions | 2 | Not Started |
| API-029 | GET | `/locations/{uid}` | Get user position | 2 | Not Started |
| API-030 | GET | `/locations/{uid}/history` | User location history | 2 | Not Started |
| API-031 | GET | `/locations/nearby` | Find nearby users (PostGIS) | 3 | Not Started |
| API-032 | GET | `/locations/team/{tid}` | Team location snapshot | 2 | Not Started |

## Missions Module `/api/v1/missions`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-033 | GET | `/missions` | List missions | 2 | Not Started |
| API-034 | POST | `/missions` | Create mission | 2 | Not Started |
| API-035 | GET | `/missions/{id}` | Get mission | 2 | Not Started |
| API-036 | PUT | `/missions/{id}` | Update mission | 2 | Not Started |
| API-037 | DELETE | `/missions/{id}` | Archive mission | 2 | Not Started |
| API-038 | PUT | `/missions/{id}/status` | Change mission state | 2 | Not Started |
| API-039 | POST | `/missions/{id}/objectives` | Add objective | 2 | Not Started |
| API-040 | PUT | `/missions/{id}/objectives/{oid}` | Update objective | 2 | Not Started |
| API-041 | POST | `/missions/{id}/assign` | Assign team/user | 2 | Not Started |
| API-042 | GET | `/missions/{id}/assignments` | List assignments | 2 | Not Started |

## Routes Module `/api/v1/routes`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-043 | GET | `/routes` | List routes | 2 | Not Started |
| API-044 | POST | `/routes` | Create route | 2 | Not Started |
| API-045 | GET | `/routes/{id}` | Get route with waypoints | 2 | Not Started |
| API-046 | PUT | `/routes/{id}` | Update route | 2 | Not Started |
| API-047 | DELETE | `/routes/{id}` | Delete route | 2 | Not Started |
| API-048 | POST | `/routes/{id}/waypoints` | Add/replace waypoints | 2 | Not Started |
| API-049 | GET | `/routes/{id}/gpx` | Export GPX | 2 | Not Started |
| API-050 | POST | `/routes/import/gpx` | Import GPX | 2 | Not Started |
| API-051 | POST | `/routes/import/kml` | Import KML | 2 | Not Started |
| API-052 | GET | `/routes/{id}/kml` | Export KML | 2 | Not Started |
| API-053 | POST | `/routes/{id}/assign` | Assign route | 2 | Not Started |
| API-054 | GET | `/routes/{id}/assignments` | List route assignments | 2 | Not Started |
| API-055 | POST | `/routes/{id}/follow` | Start follow session | 2 | Not Started |
| API-056 | PUT | `/routes/{id}/follow/{sid}` | Update follow progress | 2 | Not Started |
| API-057 | POST | `/routes/{id}/follow/{sid}/complete` | Complete follow session | 2 | Not Started |

## Contacts Module `/api/v1/contacts`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-058 | GET | `/contacts` | List contacts | 2 | Not Started |
| API-059 | POST | `/contacts` | Create contact | 2 | Not Started |
| API-060 | GET | `/contacts/{id}` | Get contact | 2 | Not Started |
| API-061 | PUT | `/contacts/{id}` | Update contact | 2 | Not Started |
| API-062 | DELETE | `/contacts/{id}` | Delete/clear contact | 2 | Not Started |
| API-063 | POST | `/contacts/{id}/share` | Share contact | 2 | Not Started |

## Drawings Module `/api/v1/drawings`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-064 | GET | `/drawings` | List drawings | 2 | Not Started |
| API-065 | POST | `/drawings` | Create drawing | 2 | Not Started |
| API-066 | GET | `/drawings/{id}` | Get drawing | 2 | Not Started |
| API-067 | PUT | `/drawings/{id}` | Update drawing | 2 | Not Started |
| API-068 | DELETE | `/drawings/{id}` | Delete drawing | 2 | Not Started |

## Geofences Module `/api/v1/geofences`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-069 | GET | `/geofences` | List geofences | 3 | Not Started |
| API-070 | POST | `/geofences` | Create geofence | 3 | Not Started |
| API-071 | GET | `/geofences/{id}` | Get geofence | 3 | Not Started |
| API-072 | PUT | `/geofences/{id}` | Update geofence | 3 | Not Started |
| API-073 | DELETE | `/geofences/{id}` | Delete geofence | 3 | Not Started |
| API-074 | GET | `/geofences/{id}/events` | Get zone entry/exit events | 3 | Not Started |
| API-075 | POST | `/geofences/check` | Check point in zones | 3 | Not Started |

## Evidence Module `/api/v1/evidence`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-076 | GET | `/evidence` | List evidence | 3 | Not Started |
| API-077 | POST | `/evidence` | Upload evidence (multipart) | 3 | Not Started |
| API-078 | GET | `/evidence/{id}` | Get evidence | 3 | Not Started |
| API-079 | PUT | `/evidence/{id}` | Update metadata | 3 | Not Started |
| API-080 | DELETE | `/evidence/{id}` | Delete evidence | 3 | Not Started |
| API-081 | GET | `/evidence/{id}/file` | Serve evidence file | 3 | Not Started |

## Messages Module `/api/v1/messages`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-082 | GET | `/messages/channels` | List user's channels | 2 | Not Started |
| API-083 | GET | `/messages/global` | Global channel history | 2 | Not Started |
| API-084 | GET | `/messages/team/{tid}` | Team channel history | 2 | Not Started |
| API-085 | GET | `/messages/mission/{mid}` | Mission channel | 2 | Not Started |
| API-086 | GET | `/messages/dm/{uid}` | Direct message history | 2 | Not Started |
| API-087 | POST | `/messages` | Send message | 2 | Not Started |
| API-088 | PUT | `/messages/{id}/read` | Mark as read | 2 | Not Started |
| API-089 | DELETE | `/messages/{id}` | Delete message | 2 | Not Started |
| API-090 | POST | `/messages/{id}/attachment` | Attach file | 2 | Not Started |

## SOS Module `/api/v1/sos`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-091 | POST | `/sos` | Trigger SOS | 3 | Not Started |
| API-092 | GET | `/sos/active` | List active SOS events | 3 | Not Started |
| API-093 | POST | `/sos/{id}/acknowledge` | Acknowledge SOS | 3 | Not Started |
| API-094 | POST | `/sos/{id}/resolve` | Resolve SOS | 3 | Not Started |

## Calls Module `/api/v1/calls`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-095 | POST | `/calls/initiate` | Start call (get ICE/TURN config) | 3 | Not Started |
| API-096 | GET | `/calls/{id}` | Get call state | 3 | Not Started |
| API-097 | POST | `/calls/{id}/join` | Join call | 3 | Not Started |
| API-098 | POST | `/calls/{id}/leave` | Leave call | 3 | Not Started |
| API-099 | POST | `/calls/{id}/end` | End call | 3 | Not Started |
| API-100 | GET | `/calls/history` | Call history | 3 | Not Started |

## Zones/POIs Module `/api/v1/zones` `/api/v1/pois`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-101 | GET | `/zones` | List operational zones | 2 | Not Started |
| API-102 | POST | `/zones` | Create zone | 2 | Not Started |
| API-103 | PUT | `/zones/{id}` | Update zone | 2 | Not Started |
| API-104 | DELETE | `/zones/{id}` | Delete zone | 2 | Not Started |
| API-105 | GET | `/pois` | List POIs | 2 | Not Started |
| API-106 | POST | `/pois` | Create POI | 2 | Not Started |
| API-107 | PUT | `/pois/{id}` | Update POI | 2 | Not Started |
| API-108 | DELETE | `/pois/{id}` | Delete POI | 2 | Not Started |

## Notifications `/api/v1/notifications`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-109 | GET | `/notifications` | Get user notifications | 2 | Not Started |
| API-110 | PUT | `/notifications/{id}/read` | Mark read | 2 | Not Started |
| API-111 | PUT | `/notifications/read-all` | Mark all read | 2 | Not Started |

## Playback `/api/v1/playback`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-112 | GET | `/playback/snapshot` | Get positions at timestamp | 4 | Not Started |
| API-113 | GET | `/playback/trail/{uid}` | User trail between times | 4 | Not Started |
| API-114 | GET | `/playback/events` | Events in time range | 4 | Not Started |

## Mission Packages `/api/v1/packages`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-115 | POST | `/packages` | Create package from mission | 4 | Not Started |
| API-116 | GET | `/packages/{id}` | Get package manifest | 4 | Not Started |
| API-117 | GET | `/packages/{id}/export` | Download package zip | 4 | Not Started |
| API-118 | POST | `/packages/import` | Import package zip | 4 | Not Started |

## Admin `/api/v1/admin`
| ID | Method | Path | Description | Phase | Status |
|----|--------|------|-------------|-------|--------|
| API-119 | GET | `/admin/users` | All users (paginated) | 1 | Not Started |
| API-120 | GET | `/admin/audit-logs` | Audit log (paginated) | 2 | Not Started |
| API-121 | GET | `/admin/stats` | System statistics | 2 | Not Started |
| API-122 | POST | `/admin/invites` | Generate invite/QR | 1 | Not Started |
| API-123 | GET | `/admin/invites` | List invites | 1 | Not Started |
| API-124 | DELETE | `/admin/invites/{id}` | Revoke invite | 1 | Not Started |

## WebSocket Events `/ws`
| ID | WS Path | Events | Phase | Status |
|----|---------|--------|-------|--------|
| WS-001 | `/ws/location/{uid}` | location_update, status_change | 2 | Not Started |
| WS-002 | `/ws/events` | sos, geofence, mission, route | 2 | Not Started |
| WS-003 | `/ws/messages/{channel}` | new_message, read_receipt, typing | 2 | Not Started |
| WS-004 | `/ws/video/{call_id}` | WebRTC signaling (offer/answer/ice) | 3 | Not Started |
| WS-005 | `/ws/drawing/{room}` | collaborative drawing sync | 3 | Not Started |
| WS-006 | `/ws/notifications/{uid}` | push notifications delivery | 2 | Not Started |

---

# PART 3 — FEATURE INVENTORY (25 Modules)

| ID | Module | Platform | Phase | Status |
|----|--------|----------|-------|--------|
| F-01 | JWT Authentication + Sessions | BE+FL+RE | 1 | Not Started |
| F-02 | RBAC (4 roles, all endpoints enforced) | BE | 1 | Not Started |
| F-03 | QR Enrollment / Voucher Enrollment | BE+FL+RE | 1 | Not Started |
| F-04 | Live GPS Tracking (WebSocket) | BE+FL+RE | 2 | Not Started |
| F-05 | Background location tracking | FL | 2 | Not Started |
| F-06 | ATAK-style Map Engine | FL+RE | 2 | Not Started |
| F-07 | Team Management | BE+FL+RE | 1 | Not Started |
| F-08 | Mission Management (6 states) | BE+RE | 2 | Not Started |
| F-09 | Route Builder (freehand, GPX, KML) | BE+FL+RE | 2 | Not Started |
| F-10 | Route Assignment Workflow | BE+FL+RE | 2 | Not Started |
| F-11 | ATAK Drawing Tools (collab) | BE+FL+RE | 3 | Not Started |
| F-12 | Contact Management | BE+FL+RE | 2 | Not Started |
| F-13 | Coordinate System (GPS/DMS/MGRS) | FL+RE | 2 | Not Started |
| F-14 | Terrain Reference Points | BE+FL+RE | 3 | Not Started |
| F-15 | SOS System (1-tap, broadcast) | BE+FL+RE | 3 | Not Started |
| F-16 | Evidence Collection (media+GPS meta) | BE+FL | 3 | Not Started |
| F-17 | Chat (5 channel types, offline sync) | BE+FL+RE | 2 | Not Started |
| F-18 | Voice Calling (WebRTC) | BE+FL | 3 | Not Started |
| F-19 | Video Calling (WebRTC, conf) | BE+FL | 3 | Not Started |
| F-20 | Geofencing (entry/exit alerts) | BE+FL+RE | 3 | Not Started |
| F-21 | Proximity Finder (PostGIS) | BE+RE | 3 | Not Started |
| F-22 | Playback Engine (historical replay) | BE+RE | 4 | Not Started |
| F-23 | Mission Packages (export/import) | BE+RE | 4 | Not Started |
| F-24 | Reticulum Mesh (P2P offline) | BE+FL | 4 | Not Started |
| F-25 | Offline Operations (queue + sync) | FL | 4 | Not Started |

---

# PART 4 — PAGE INVENTORY

## React Web Dashboard (Clients/)
| ID | Page | Route | Role Access | Phase | Status |
|----|------|-------|-------------|-------|--------|
| RE-01 | Login | `/login` | All | 1 | Not Started |
| RE-02 | Dashboard / Overview | `/` | All | 1 | Not Started |
| RE-03 | Live Map (full-screen) | `/map` | All | 2 | Not Started |
| RE-04 | Team Management | `/teams` | Coord, Leader | 1 | Not Started |
| RE-05 | Team Detail | `/teams/:id` | Coord, Leader | 1 | Not Started |
| RE-06 | Mission Board | `/missions` | Coord, Planning | 2 | Not Started |
| RE-07 | Mission Detail / Briefing | `/missions/:id` | Coord, Planning | 2 | Not Started |
| RE-08 | Route Builder | `/routes/build` | Coord, Planning | 2 | Not Started |
| RE-09 | Route List | `/routes` | All | 2 | Not Started |
| RE-10 | Route Assignment | `/routes/:id/assign` | Coord, Planning, Leader | 2 | Not Started |
| RE-11 | Operations Board | `/operations` | Coord, Planning | 2 | Not Started |
| RE-12 | Chat / Comms | `/comms` | All | 2 | Not Started |
| RE-13 | Evidence Gallery | `/evidence` | Coord, Planning | 3 | Not Started |
| RE-14 | Geofences Manager | `/geofences` | Coord | 3 | Not Started |
| RE-15 | Playback / Replay | `/playback` | Coord, Planning | 4 | Not Started |
| RE-16 | Analytics | `/analytics` | Coord | 4 | Not Started |
| RE-17 | Admin Panel | `/admin` | Coord | 1 | Not Started |
| RE-18 | Admin Users | `/admin/users` | Coord | 1 | Not Started |
| RE-19 | Admin Invites / QR | `/admin/invites` | Coord | 1 | Not Started |
| RE-20 | Audit Logs | `/admin/audit` | Coord | 2 | Not Started |
| RE-21 | Notification Center | `/notifications` | All | 2 | Not Started |
| RE-22 | Profile Settings | `/profile` | All | 1 | Not Started |
| RE-23 | Mission Packages | `/packages` | Coord, Planning | 4 | Not Started |

## Flutter Mobile App (mobile/)
| ID | Screen | Role Access | Phase | Status |
|----|--------|-------------|-------|--------|
| FL-01 | Splash / Boot | All | 1 | Not Started |
| FL-02 | Login | All | 1 | Not Started |
| FL-03 | QR Enrollment | All | 1 | Not Started |
| FL-04 | Home / Dashboard | All | 1 | Not Started |
| FL-05 | Live Map (main) | All | 2 | Not Started |
| FL-06 | Map Layer Controls | All | 2 | Not Started |
| FL-07 | Team Tracker | Leader, Field | 2 | Not Started |
| FL-08 | My Route | Field | 2 | Not Started |
| FL-09 | Route Navigator | Field | 2 | Not Started |
| FL-10 | Chat Hub | All | 2 | Not Started |
| FL-11 | Chat Thread | All | 2 | Not Started |
| FL-12 | Mission List | All | 2 | Not Started |
| FL-13 | Mission Detail | Leader, Field | 2 | Not Started |
| FL-14 | SOS Screen | All | 3 | Not Started |
| FL-15 | Evidence Capture | Field, Leader | 3 | Not Started |
| FL-16 | Evidence List | All | 3 | Not Started |
| FL-17 | Voice Call | All | 3 | Not Started |
| FL-18 | Video Call | All | 3 | Not Started |
| FL-19 | Contacts Map | All | 2 | Not Started |
| FL-20 | Contact Detail | All | 2 | Not Started |
| FL-21 | Geofence Alerts | All | 3 | Not Started |
| FL-22 | Notifications | All | 2 | Not Started |
| FL-23 | Profile / Settings | All | 1 | Not Started |
| FL-24 | Offline Status | All | 4 | Not Started |
| FL-25 | Proximity Finder | All | 3 | Not Started |

---

# PART 5 — COMPONENT INVENTORY

## React Components (Clients/src/components/)
| ID | Component | Used In | Phase | Status |
|----|-----------|---------|-------|--------|
| RC-01 | `MapContainer` | Map page | 2 | Not Started |
| RC-02 | `UserMarker` | Map | 2 | Not Started |
| RC-03 | `TeamMarker` | Map | 2 | Not Started |
| RC-04 | `RouteLayer` | Map | 2 | Not Started |
| RC-05 | `DrawingLayer` | Map | 3 | Not Started |
| RC-06 | `GeofenceLayer` | Map | 3 | Not Started |
| RC-07 | `ContactMarker` | Map | 2 | Not Started |
| RC-08 | `MapToolbar` | Map | 2 | Not Started |
| RC-09 | `DrawingToolbar` | Map | 3 | Not Started |
| RC-10 | `CoordinateDisplay` | Map, Route | 2 | Not Started |
| RC-11 | `ChatPanel` | Comms | 2 | Not Started |
| RC-12 | `MessageBubble` | Chat | 2 | Not Started |
| RC-13 | `ChannelList` | Chat | 2 | Not Started |
| RC-14 | `UserStatusBadge` | Team, Map | 1 | Not Started |
| RC-15 | `MissionCard` | Missions | 2 | Not Started |
| RC-16 | `MissionTimeline` | Mission Detail | 2 | Not Started |
| RC-17 | `RouteCard` | Routes | 2 | Not Started |
| RC-18 | `WaypointEditor` | Route Builder | 2 | Not Started |
| RC-19 | `TeamCard` | Teams | 1 | Not Started |
| RC-20 | `EvidenceCard` | Evidence | 3 | Not Started |
| RC-21 | `SOSBanner` | Global | 3 | Not Started |
| RC-22 | `NotificationBell` | Layout | 2 | Not Started |
| RC-23 | `RoleBadge` | Users, Team | 1 | Not Started |
| RC-24 | `AuditLogRow` | Admin | 2 | Not Started |
| RC-25 | `PlaybackTimeline` | Playback | 4 | Not Started |
| RC-26 | `PlaybackControls` | Playback | 4 | Not Started |
| RC-27 | `QRGenerator` | Admin/Invites | 1 | Not Started |
| RC-28 | `Sidebar` | Layout | 1 | Not Started |
| RC-29 | `TopNav` | Layout | 1 | Not Started |
| RC-30 | `ConfirmModal` | Global | 1 | Not Started |
| RC-31 | `VideoCallGrid` | Calls | 3 | Not Started |
| RC-32 | `CallControls` | Calls | 3 | Not Started |
| RC-33 | `ProximityList` | Proximity | 3 | Not Started |

## Flutter Widgets (mobile/lib/widgets/)
| ID | Widget | Used In | Phase | Status |
|----|--------|---------|-------|--------|
| FW-01 | `DRDMapWidget` | Map screen | 2 | Not Started |
| FW-02 | `UserPinMarker` | Map | 2 | Not Started |
| FW-03 | `RoutePolyline` | Map | 2 | Not Started |
| FW-04 | `DrawingOverlay` | Map | 3 | Not Started |
| FW-05 | `GeofenceOverlay` | Map | 3 | Not Started |
| FW-06 | `SOSButton` | Persistent | 3 | Not Started |
| FW-07 | `ChatBubble` | Chat | 2 | Not Started |
| FW-08 | `ChannelTile` | Chat hub | 2 | Not Started |
| FW-09 | `TeamMemberTile` | Team tracker | 2 | Not Started |
| FW-10 | `MissionTile` | Mission list | 2 | Not Started |
| FW-11 | `EvidencePickerSheet` | Evidence capture | 3 | Not Started |
| FW-12 | `CoordinateChip` | Map, Route | 2 | Not Started |
| FW-13 | `ConnectionStatusBar` | Global | 4 | Not Started |
| FW-14 | `RouteNavigationHUD` | Route nav | 2 | Not Started |
| FW-15 | `CallControlsOverlay` | Calls | 3 | Not Started |
| FW-16 | `NotificationCard` | Notifications | 2 | Not Started |
| FW-17 | `UserAvatarStack` | Team | 1 | Not Started |
| FW-18 | `StatusIndicator` | Map, Team | 2 | Not Started |

---

# PART 6 — SERVICE INVENTORY

## Backend Services (Server/app/services/)
| ID | Service | Responsibilities | Phase | Status |
|----|---------|-----------------|-------|--------|
| BS-01 | `auth_service.py` | JWT, sessions, password hashing | 1 | Not Started |
| BS-02 | `user_service.py` | User CRUD, avatar upload | 1 | Not Started |
| BS-03 | `team_service.py` | Team CRUD, membership | 1 | Not Started |
| BS-04 | `location_service.py` | GPS updates, status calc | 2 | Not Started |
| BS-05 | `mission_service.py` | Mission lifecycle | 2 | Not Started |
| BS-06 | `route_service.py` | Route CRUD, GPX/KML import/export | 2 | Not Started |
| BS-07 | `message_service.py` | Chat, channels, read receipts | 2 | Not Started |
| BS-08 | `evidence_service.py` | File upload to MinIO/local, metadata | 3 | Not Started |
| BS-09 | `sos_service.py` | SOS broadcast, acknowledgement | 3 | Not Started |
| BS-10 | `call_service.py` | WebRTC signaling coordination | 3 | Not Started |
| BS-11 | `geofence_service.py` | Zone check, entry/exit events | 3 | Not Started |
| BS-12 | `notification_service.py` | Push notification dispatch | 2 | Not Started |
| BS-13 | `drawing_service.py` | Drawing CRUD and sync | 3 | Not Started |
| BS-14 | `contact_service.py` | Tactical contact management | 2 | Not Started |
| BS-15 | `audit_service.py` | Audit logging middleware | 2 | Not Started |
| BS-16 | `playback_service.py` | Historical data queries | 4 | Not Started |
| BS-17 | `package_service.py` | Mission package build/export | 4 | Not Started |
| BS-18 | `email_service.py` | Password reset emails | 1 | Not Started |
| BS-19 | `reticulum_bridge.py` | Reticulum daemon bridge | 4 | Not Started |

## Flutter Services (mobile/lib/services/)
| ID | Service | Responsibilities | Phase | Status |
|----|---------|-----------------|-------|--------|
| FS-01 | `auth_service.dart` | Login, token storage, refresh | 1 | Not Started |
| FS-02 | `api_service.dart` | HTTP client, interceptors | 1 | Not Started |
| FS-03 | `websocket_service.dart` | WS connect, reconnect, dispatch | 2 | Not Started |
| FS-04 | `location_service.dart` | GPS, background tracking | 2 | Not Started |
| FS-05 | `storage_service.dart` | SQLite + SharedPrefs | 1 | Not Started |
| FS-06 | `chat_service.dart` | Messages, offline queue | 2 | Not Started |
| FS-07 | `evidence_service.dart` | Camera, mic, file upload | 3 | Not Started |
| FS-08 | `webrtc_service.dart` | WebRTC setup, signaling | 3 | Not Started |
| FS-09 | `sos_service.dart` | SOS trigger and listen | 3 | Not Started |
| FS-10 | `notification_service.dart` | Local push, FCM | 2 | Not Started |
| FS-11 | `offline_sync_service.dart` | Queue management, sync | 4 | Not Started |
| FS-12 | `reticulum_service.dart` | Mesh networking client | 4 | Not Started |
| FS-13 | `coordinate_service.dart` | GPS↔DMS↔MGRS conversion | 2 | Not Started |
| FS-14 | `drawing_service.dart` | Collaborative drawing | 3 | Not Started |

---

# PART 7 — EVENT INVENTORY (WebSocket + Push)

## WebSocket Events (Server → Client)
| ID | Event Name | Payload | Subscribers | Phase | Status |
|----|------------|---------|-------------|-------|--------|
| EV-01 | `location_update` | uid, lat, lng, heading, speed, status | All connected | 2 | Not Started |
| EV-02 | `user_status_change` | uid, status (active/stale/offline) | All | 2 | Not Started |
| EV-03 | `sos_triggered` | sos_id, uid, lat, lng, timestamp | All + alert | 3 | Not Started |
| EV-04 | `sos_acknowledged` | sos_id, acknowledged_by | Relevant | 3 | Not Started |
| EV-05 | `sos_resolved` | sos_id | Relevant | 3 | Not Started |
| EV-06 | `new_message` | channel, message_id, sender, preview | Channel members | 2 | Not Started |
| EV-07 | `message_read` | message_id, reader_id | Sender | 2 | Not Started |
| EV-08 | `typing_indicator` | channel, uid, is_typing | Channel members | 2 | Not Started |
| EV-09 | `call_incoming` | call_id, caller, type | Callee | 3 | Not Started |
| EV-10 | `call_accepted` | call_id | Caller | 3 | Not Started |
| EV-11 | `call_declined` | call_id | Caller | 3 | Not Started |
| EV-12 | `webrtc_offer` | call_id, sdp | Callee | 3 | Not Started |
| EV-13 | `webrtc_answer` | call_id, sdp | Caller | 3 | Not Started |
| EV-14 | `webrtc_ice` | call_id, candidate | Peer | 3 | Not Started |
| EV-15 | `geofence_entered` | zone_id, uid, timestamp | Coord + uid | 3 | Not Started |
| EV-16 | `geofence_exited` | zone_id, uid, timestamp | Coord + uid | 3 | Not Started |
| EV-17 | `mission_updated` | mission_id, status, changed_by | Assignees | 2 | Not Started |
| EV-18 | `route_assigned` | route_id, assignment, deadline | Assignee | 2 | Not Started |
| EV-19 | `drawing_update` | drawing_id, delta, author | Room members | 3 | Not Started |
| EV-20 | `contact_shared` | contact, shared_by | Team | 2 | Not Started |
| EV-21 | `evidence_uploaded` | evidence_id, by, lat, lng | Team + Coord | 3 | Not Started |
| EV-22 | `notification` | type, title, body, ref_id | uid | 2 | Not Started |

---

# PART 8 — BACKEND INFRASTRUCTURE

| ID | Item | Description | Phase | Status |
|----|------|-------------|-------|--------|
| INF-01 | Alembic migrations | Schema versioning for all 39 tables | 1 | Not Started |
| INF-02 | PostGIS extension | Spatial indexing setup | 1 | Not Started |
| INF-03 | Redis pub/sub | WS broadcast channel | 2 | Not Started |
| INF-04 | MinIO/local file store | Evidence and avatar storage | 3 | Not Started |
| INF-05 | Auth middleware | JWT validation on every protected route | 1 | Not Started |
| INF-06 | RBAC middleware | Role check decorator/dependency | 1 | Not Started |
| INF-07 | Audit middleware | Log all state-changing requests | 2 | Not Started |
| INF-08 | CORS middleware | Already exists, verify config | 1 | Not Started |
| INF-09 | WS manager | Multi-room broadcast manager | 2 | Not Started |
| INF-10 | Background task scheduler | Location status updater (30s) | 1 | Not Started |
| INF-11 | Geofence checker | Periodic PostGIS point-in-polygon | 3 | Not Started |
| INF-12 | Reticulum daemon | Python sidecar process | 4 | Not Started |
| INF-13 | Docker / docker-compose | Containerized deployment | 1 | Not Started |

---

# IMPLEMENTATION ROADMAP

## PHASE 1 — Foundation (Weeks 1–2)
**Goal:** Working auth, team management, admin panel, database schema, deployable server

### Phase 1 Tasks
| ID | Task | Dependencies | Status |
|----|------|-------------|--------|
| P1-01 | Database schema — all 39 tables + migrations | — | ✅ Done |
| P1-02 | PostGIS spatial indexes setup | P1-01 | ✅ Done |
| P1-03 | `config.py` + `database.py` + `models/` | P1-01 | ✅ Done |
| P1-04 | Auth service + JWT middleware | P1-03 | ✅ Done |
| P1-05 | RBAC dependency (4 roles) | P1-04 | ✅ Done |
| P1-06 | Auth API (register, login, refresh, logout, forgot-pw) | P1-04 | ✅ Done |
| P1-07 | QR + Voucher enrollment API | P1-04 | ✅ Done |
| P1-08 | Users API (CRUD, avatar, role change) | P1-05 | ✅ Done |
| P1-09 | Teams API (CRUD, membership) | P1-05 | ✅ Done |
| P1-10 | Admin API (users, invites, stats) | P1-05 | ✅ Done |
| P1-11 | Audit middleware | P1-05 | ✅ Done |
| P1-12 | Email service (password reset) | P1-03 | ✅ Done |
| P1-13 | WS connection manager | P1-03 | ✅ Done |
| P1-14 | React: Login page + auth flow | — | ✅ Done |
| P1-15 | React: Layout (Sidebar, TopNav) | P1-14 | ✅ Done |
| P1-16 | React: Dashboard overview | P1-15 | ✅ Done |
| P1-17 | React: Team Management pages | P1-15 | ✅ Done |
| P1-18 | React: Admin panel (users, invites, QR gen) | P1-15 | ✅ Done |
| P1-19 | React: Profile/Settings | P1-15 | ✅ Done |
| P1-20 | Flutter: Splash, Login, QR enrollment screens | — | ✅ Done |
| P1-21 | Flutter: providers (auth, storage) | P1-20 | ✅ Done |
| P1-22 | Flutter: API service + auth interceptor | P1-21 | ✅ Done |
| P1-23 | Flutter: Home/Dashboard shell | P1-22 | ✅ Done |
| P1-24 | Flutter: Profile / Settings screen | P1-22 | ✅ Done |
| P1-25 | Docker-compose (postgres+postgis, redis, server) | P1-01 | ✅ Done |

**Phase 1 Deliverable:** Login, team management, admin QR enrollment, working database, deployable docker stack

---

## PHASE 2 — Tracking, Teams & Communications (Weeks 3–5)
**Goal:** Live map, real-time tracking, chat, missions, routes

### Phase 2 Tasks
| ID | Task | Dependencies | Status |
|----|------|-------------|--------|
| P2-01 | Location API + location service | P1-03 | Not Started |
| P2-02 | WebSocket location broadcaster (Redis pub/sub) | P1-13 | Not Started |
| P2-03 | Background location task (30s status updater) | P2-01 | Not Started |
| P2-04 | Mission API + service (CRUD, state machine) | P1-05 | Not Started |
| P2-05 | Route API + service (CRUD, GPX/KML import/export) | P1-05 | Not Started |
| P2-06 | Route assignment API + follow session tracking | P2-05 | Not Started |
| P2-07 | Contact API + service | P1-05 | Not Started |
| P2-08 | Drawing API + service | P1-05 | Not Started |
| P2-09 | Zone/POI API + service | P1-05 | Not Started |
| P2-10 | Message API + service (5 channels) | P1-05 | Not Started |
| P2-11 | WS message broadcaster | P1-13 | Not Started |
| P2-12 | Notification API + service | P1-05 | Not Started |
| P2-13 | WS notification broadcaster | P1-13 | Not Started |
| P2-14 | React: Live Map (Leaflet, all layers) | P2-01 | Not Started |
| P2-15 | React: Map user/team markers with status | P2-14 | Not Started |
| P2-16 | React: Route layer + waypoint display | P2-14 | Not Started |
| P2-17 | React: Route Builder (click, drag, freehand) | P2-14 | Not Started |
| P2-18 | React: Route assignment workflow | P2-17 | Not Started |
| P2-19 | React: Mission Board + Mission Detail | P2-04 | Not Started |
| P2-20 | React: Operations Board | P2-04 | Not Started |
| P2-21 | React: Chat / Comms panel | P2-10 | Not Started |
| P2-22 | React: Notifications | P2-12 | Not Started |
| P2-23 | React: Audit logs page | P1-11 | Not Started |
| P2-24 | Flutter: Live Map screen + GPS overlay | P2-01 | Not Started |
| P2-25 | Flutter: WebSocket location service | P2-02 | Not Started |
| P2-26 | Flutter: Background GPS tracking | P2-25 | Not Started |
| P2-27 | Flutter: Team tracker screen | P2-25 | Not Started |
| P2-28 | Flutter: Route following navigator HUD | P2-06 | Not Started |
| P2-29 | Flutter: Chat hub + thread screens | P2-10 | Not Started |
| P2-30 | Flutter: Mission list + detail | P2-04 | Not Started |
| P2-31 | Flutter: Contact map + detail | P2-07 | Not Started |
| P2-32 | Flutter: Coordinate display (GPS/DMS/MGRS) | — | Not Started |
| P2-33 | Flutter: Notification screen + local push | P2-12 | Not Started |

**Phase 2 Deliverable:** Live map with all users, full chat, route builder, mission management, mobile tracking

---

## PHASE 3 — Field Operations & Communications (Weeks 6–8)
**Goal:** SOS, WebRTC calls, evidence, geofencing, drawing tools, contacts

### Phase 3 Tasks
| ID | Task | Dependencies | Status |
|----|------|-------------|--------|
| P3-01 | SOS API + service + WS broadcast | P1-05 | Not Started |
| P3-02 | Evidence API + file storage (MinIO) | P1-05 | Not Started |
| P3-03 | Call API + WebRTC signaling WS | P1-13 | Not Started |
| P3-04 | Geofence API + PostGIS checker | P2-01 | Not Started |
| P3-05 | Geofence background checker task | P3-04 | Not Started |
| P3-06 | Drawing API + collaborative WS room | P2-08 | Not Started |
| P3-07 | Terrain checkpoints API | P1-05 | Not Started |
| P3-08 | Proximity finder API (PostGIS haversine) | P2-01 | Not Started |
| P3-09 | React: SOS banner (global alert) | P3-01 | Not Started |
| P3-10 | React: Evidence gallery | P3-02 | Not Started |
| P3-11 | React: Geofence manager + map layer | P3-04 | Not Started |
| P3-12 | React: Drawing tools on map | P3-06 | Not Started |
| P3-13 | React: Video call grid + WebRTC | P3-03 | Not Started |
| P3-14 | React: Proximity finder panel | P3-08 | Not Started |
| P3-15 | Flutter: SOS screen (1-tap + confirm) | P3-01 | Not Started |
| P3-16 | Flutter: Evidence capture (camera/audio/notes) | P3-02 | Not Started |
| P3-17 | Flutter: Evidence list screen | P3-02 | Not Started |
| P3-18 | Flutter: Voice call screen (WebRTC) | P3-03 | Not Started |
| P3-19 | Flutter: Video call screen (WebRTC) | P3-03 | Not Started |
| P3-20 | Flutter: Geofence alert overlay | P3-04 | Not Started |
| P3-21 | Flutter: Drawing overlay on map | P3-06 | Not Started |
| P3-22 | Flutter: Proximity finder screen | P3-08 | Not Started |
| P3-23 | Flutter: Terrain reference points | P3-07 | Not Started |

**Phase 3 Deliverable:** Full field operations: SOS, calls, video, evidence, geofencing, drawing, proximity

---

## PHASE 4 — Advanced Capabilities (Weeks 9–12)
**Goal:** Reticulum mesh, offline ops, playback, mission packages, analytics

### Phase 4 Tasks
| ID | Task | Dependencies | Status |
|----|------|-------------|--------|
| P4-01 | Playback API (snapshots, trail, events) | P2-01 | Not Started |
| P4-02 | Playback snapshot recorder (background task) | P4-01 | Not Started |
| P4-03 | Mission Package API (build, export, import zip) | P2-04 | Not Started |
| P4-04 | Resource Management API (equipment/vehicles) | P1-05 | Not Started |
| P4-05 | Reticulum daemon sidecar (Python) | — | Not Started |
| P4-06 | Reticulum bridge service (BE) | P4-05 | Not Started |
| P4-07 | Reticulum identity + roster service | P4-06 | Not Started |
| P4-08 | Reticulum store-and-forward (offline chat) | P4-07 | Not Started |
| P4-09 | Offline queue DB + sync service (Flutter) | P2-25 | Not Started |
| P4-10 | Offline location queuing (Flutter) | P4-09 | Not Started |
| P4-11 | Offline chat queuing (Flutter) | P4-09 | Not Started |
| P4-12 | Offline evidence queuing (Flutter) | P4-09 | Not Started |
| P4-13 | React: Playback engine (timeline + controls) | P4-01 | Not Started |
| P4-14 | React: Analytics dashboard | P2-01 | Not Started |
| P4-15 | React: Mission packages manager | P4-03 | Not Started |
| P4-16 | Flutter: Offline status screen | P4-09 | Not Started |
| P4-17 | Flutter: Reticulum mesh service | P4-06 | Not Started |
| P4-18 | Flutter: Sync status indicators | P4-09 | Not Started |

**Phase 4 Deliverable:** Full offline/mesh capability, historical replay, mission packages, analytics

---

# TASK SUMMARY BY PHASE

| Phase | Task Count | Priority |
|-------|-----------|---------|
| Phase 1 | 25 tasks | CRITICAL (nothing works without this) |
| Phase 2 | 33 tasks | HIGH (core operational value) |
| Phase 3 | 23 tasks | HIGH (field safety features) |
| Phase 4 | 18 tasks | MEDIUM (advanced capabilities) |
| **Total** | **99 roadmap tasks** | |
| DB tasks | 39 | Embedded in P1 |
| API endpoints | ~124 | Distributed across phases |
| Components | 51 | Distributed across phases |
| Services | 33 | Distributed across phases |
| WS Events | 22 | Distributed across phases |
| **Grand Total** | **312 items** | |

---

# TECH STACK CONFIRMATION

| Layer | Technology | Version |
|-------|-----------|---------|
| Backend | FastAPI + Uvicorn | Latest |
| ORM | SQLAlchemy (async) | 2.x |
| Migrations | Alembic | Latest |
| DB | PostgreSQL + PostGIS | 15+ |
| Cache/PubSub | Redis | 7+ |
| File Storage | MinIO (or local `/uploads`) | Latest |
| Mobile | Flutter + Dart | 3.x |
| Web | React 19 + TypeScript + Vite | As in package.json |
| Styling | TailwindCSS 4 | As in package.json |
| Maps (Web) | Leaflet + react-leaflet | As in package.json |
| Maps (Mobile) | flutter_map | As in pubspec.yaml |
| WebRTC | flutter_webrtc + server signaling | As in pubspec.yaml |
| Mesh | Reticulum | Python sidecar |
| Containers | Docker + docker-compose | Latest |

---

## APPROVAL CHECKPOINT

**Status: AWAITING APPROVAL**

Review the above inventories and roadmap. Reply with one of:
- `APPROVED` — begin Phase 1 implementation immediately
- `MODIFY: [changes]` — adjust checklist before starting
- `QUESTIONS` — clarification needed

Upon approval, Phase 1 implementation begins with P1-01 (database schema).
