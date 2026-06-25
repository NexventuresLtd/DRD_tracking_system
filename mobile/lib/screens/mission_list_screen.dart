// Mobile mission screen — field-operations redesign
// Four questions only: Do I have a mission? What's my objective?
// Where do I go? What do I report?

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/navigation_state.dart';
import '../services/websocket_service.dart';
import 'live_map_screen.dart';
import 'live_session_screen.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class MissionObjective {
  final String id;
  final String title;
  final String? description;
  final bool isCompleted;
  final int orderIndex;
  final String? completedAt;
  final String? zoneId;
  final String? routeId;
  final String? facilityId;

  const MissionObjective({
    required this.id,
    required this.title,
    this.description,
    required this.isCompleted,
    required this.orderIndex,
    this.completedAt,
    this.zoneId,
    this.routeId,
    this.facilityId,
  });

  factory MissionObjective.fromJson(Map<String, dynamic> j) => MissionObjective(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        description: j['description'] as String?,
        isCompleted: j['is_completed'] as bool? ?? false,
        orderIndex: (j['order_index'] as num?)?.toInt() ?? 0,
        completedAt: j['completed_at'] as String?,
        zoneId: j['zone_id'] as String?,
        routeId: j['route_id'] as String?,
        facilityId: j['facility_id'] as String?,
      );

  String get objectiveType {
    if (title.startsWith('[ZONE]')) return 'ZONE';
    if (title.startsWith('[ROUTE]')) return 'ROUTE';
    if (title.startsWith('[FACILITY]')) return 'FACILITY';
    return '';
  }

  String get cleanTitle => title
      .replaceFirst(RegExp(r'^\[ZONE\]\s*(Deploy to:\s*)?'), '')
      .replaceFirst(RegExp(r'^\[ROUTE\]\s*(Return via:\s*|Follow:\s*)?'), '')
      .replaceFirst(RegExp(r'^\[FACILITY\]\s*(Report to:\s*)?'), '')
      .trim();

  String get typeAction {
    switch (objectiveType) {
      case 'ZONE':
        return 'DEPLOY TO ZONE';
      case 'ROUTE':
        return 'FOLLOW ROUTE';
      case 'FACILITY':
        return 'REPORT TO FACILITY';
      default:
        return 'CURRENT OBJECTIVE';
    }
  }

  Color get typeColor {
    switch (objectiveType) {
      case 'ZONE':
        return const Color(0xFFA78BFA);
      case 'ROUTE':
        return const Color(0xFF38BDF8);
      case 'FACILITY':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
    }
  }
}

class MissionData {
  final String id;
  final String name;
  final String? missionCode;
  final String status;
  final String priority;
  final String? areaOfOperations;
  final String? briefingNotes;
  final String? liveSessionId;
  final List<MissionObjective> objectives;
  final int assignmentCount;

  const MissionData({
    required this.id,
    required this.name,
    this.missionCode,
    required this.status,
    required this.priority,
    this.areaOfOperations,
    this.briefingNotes,
    this.liveSessionId,
    required this.objectives,
    required this.assignmentCount,
  });

  factory MissionData.fromJson(Map<String, dynamic> j) {
    final rawObjs =
        (j['objectives'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final objectives = rawObjs.map(MissionObjective.fromJson).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return MissionData(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'Unnamed Mission',
      missionCode: j['mission_code'] as String?,
      status: j['status'] as String? ?? 'draft',
      priority: j['priority'] as String? ?? 'medium',
      areaOfOperations: j['area_of_operations'] as String?,
      briefingNotes: j['briefing_notes'] as String?,
      liveSessionId: j['live_session_id'] as String?,
      objectives: objectives,
      assignmentCount: (j['assignments'] as List<dynamic>? ?? []).length,
    );
  }

  int get currentIndex => objectives.indexWhere((o) => !o.isCompleted);
  MissionObjective? get currentObjective {
    final i = currentIndex;
    return i >= 0 ? objectives[i] : null;
  }
  int get completedCount => objectives.where((o) => o.isCompleted).length;
  bool get allComplete =>
      objectives.isNotEmpty && objectives.every((o) => o.isCompleted);
}

// ── Constants ─────────────────────────────────────────────────────────────────

const _activeStatuses = {
  'approved',
  'planned',
  'assigned',
  'pending_acknowledgement',
  'briefing',
  'active',
  'deploying',
  'extraction',
  'awaiting_review',
  'debrief',
};

const _priorityColor = {
  'critical': Color(0xFFDC2626),
  'high': Color(0xFFF59E0B),
  'medium': Color(0xFF3B82F6),
  'low': Color(0xFF22C55E),
};

const _priorityBg = {
  'critical': Color(0xFF2D0A0A),
  'high': Color(0xFF2D1A00),
  'medium': Color(0xFF0C1E3D),
  'low': Color(0xFF052E16),
};

const _statusLabel = {
  'assigned': 'ASSIGNED',
  'pending_acknowledgement': 'ACK PENDING',
  'briefing': 'BRIEFING',
  'active': 'ACTIVE',
  'deploying': 'DEPLOYING',
  'extraction': 'EXTRACTION',
  'awaiting_review': 'AWAITING REVIEW',
  'debrief': 'DEBRIEF',
  'completed': 'COMPLETED',
};

const _statusColor = {
  'assigned': Color(0xFF38BDF8),
  'pending_acknowledgement': Color(0xFFA78BFA),
  'briefing': Color(0xFF6366F1),
  'active': Color(0xFF22C55E),
  'deploying': Color(0xFF10B981),
  'extraction': Color(0xFF14B8A6),
  'awaiting_review': Color(0xFFF59E0B),
  'debrief': Color(0xFF8B5CF6),
  'completed': Color(0xFF16A34A),
};

const _sheetInput = InputDecoration(
  filled: true,
  fillColor: Color(0xFF060D06),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: Color(0xFF0A1F0A)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: Color(0xFF0A1F0A)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: Color(0xFF22C55E)),
  ),
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  hintStyle: TextStyle(fontSize: 12, color: Color(0xFF374151)),
  labelStyle: TextStyle(
      fontFamily: 'JetBrains Mono', fontSize: 10, color: Color(0xFF4B5563)),
);

// ── Main Screen ───────────────────────────────────────────────────────────────

class MissionListScreen extends StatefulWidget {
  const MissionListScreen({super.key});
  @override
  State<MissionListScreen> createState() => _MissionListScreenState();
}

class _MissionListScreenState extends State<MissionListScreen>
    with WidgetsBindingObserver {
  MissionData? _mission;
  bool _loading = true;
  String? _error;
  bool _acknowledging = false;
  bool _completingMission = false;
  final Map<String, bool> _completing = {};
  Timer? _pollTimer;

  // All event types the server actually broadcasts for mission changes.
  static const _wsEvents = [
    'mission_assigned', 'mission_active', 'mission_updated',
    'mission_approved', 'mission_suspended', 'mission_resumed',
    'mission_completed', 'mission_briefing_started', 'mission_debrief_started',
    'mission_awaiting_review', 'objective_completed',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    for (final evt in _wsEvents) {
      WebSocketService().on(evt, _onWsEvent);
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final evt in _wsEvents) {
      WebSocketService().off(evt, _onWsEvent);
    }
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  void _onWsEvent(dynamic _) => _load();

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final raw = await ApiService().get(
        '/missions',
        params: {'my_missions': 'true'},
      );
      final list =
          (raw is List ? raw : (raw as Map)['data'] as List? ?? [])
              .cast<Map<String, dynamic>>()
              .map(MissionData.fromJson)
              .toList();

      MissionData? active;
      for (final m in list) {
        if (_activeStatuses.contains(m.status)) {
          active = m;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _mission = active;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _acknowledge() async {
    if (_mission == null || _acknowledging) return;
    setState(() => _acknowledging = true);
    try {
      await ApiService().post('/missions/${_mission!.id}/acknowledge', {});
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _acknowledging = false);
    }
  }

  Future<void> _completeObjective(String objectiveId) async {
    if (_mission == null || _completing[objectiveId] == true) return;
    setState(() => _completing[objectiveId] = true);

    double? lat, lng;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {}

    try {
      await ApiService().post(
        '/missions/${_mission!.id}/objectives/$objectiveId/complete',
        {'lat': lat, 'lng': lng},
      );
      await _load();
      if (mounted) {
        HapticFeedback.mediumImpact();
        _snack('Objective complete', color: const Color(0xFF16A34A));
      }
    } catch (_) {
      if (mounted) {
        _snack('Failed to complete objective', color: const Color(0xFFDC2626));
      }
    } finally {
      if (mounted) setState(() => _completing.remove(objectiveId));
    }
  }

  Future<void> _completeMission() async {
    if (_mission == null || _completingMission) return;
    setState(() => _completingMission = true);
    try {
      await ApiService().post('/missions/${_mission!.id}/complete', {});
      await _load();
      if (mounted) {
        HapticFeedback.heavyImpact();
        _snack('Mission marked complete', color: const Color(0xFF16A34A));
      }
    } catch (e) {
      if (mounted) {
        _snack('Failed: ${e.toString()}', color: const Color(0xFFDC2626));
      }
    } finally {
      if (mounted) setState(() => _completingMission = false);
    }
  }

  void _openMap() {
    if (_mission != null) LiveMapScreen.pendingMissionId = _mission!.id;
    appTabNotifier.value = 1;
  }

  void _joinBriefing() {
    if (_mission?.liveSessionId == null) return;
    LiveSessionScreen.pendingJoinSessionId = _mission!.liveSessionId;
    Navigator.pushNamed(context, '/live');
  }

  void _joinDebrief() {
    if (_mission?.liveSessionId == null) return;
    LiveSessionScreen.pendingJoinSessionId = _mission!.liveSessionId;
    Navigator.pushNamed(context, '/live');
  }

  void _snack(String msg, {Color color = const Color(0xFF22C55E)}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12)),
      backgroundColor: color,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  bool get _isLeader {
    final role = context.read<AuthProvider>().user?.role ?? '';
    return role == 'team_leader' ||
        role == 'operations_coordinator' ||
        role == 'planning_officer';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF030712),
        body: Center(
          child: CircularProgressIndicator(
              color: Color(0xFF22C55E), strokeWidth: 1.5),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: const Color(0xFF22C55E),
          backgroundColor: const Color(0xFF0A1F0A),
          child: _mission == null
              ? _NoMissionView(onRefresh: _load, error: _error)
              : _MissionView(
                  mission: _mission!,
                  isLeader: _isLeader,
                  completing: _completing,
                  acknowledging: _acknowledging,
                  completingMission: _completingMission,
                  onAcknowledge: _acknowledge,
                  onCompleteObjective: _completeObjective,
                  onCompleteMission: _completeMission,
                  onOpenMap: _openMap,
                  onIncident: () =>
                      _showSheet(context, _IncidentSheet(missionId: _mission!.id)),
                  onEvidence: () =>
                      _showSheet(context, _EvidenceSheet(missionId: _mission!.id)),
                  onCasualty: () =>
                      _showSheet(context, _CasualtySheet(missionId: _mission!.id)),
                  onJoinBriefing: (_mission!.status == 'briefing' && _mission!.liveSessionId != null) ? _joinBriefing : null,
                  onJoinDebrief: (_mission!.status == 'debrief' && _mission!.liveSessionId != null) ? _joinDebrief : null,
                ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext ctx, Widget sheet) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }
}

// ── No Mission View ───────────────────────────────────────────────────────────

class _NoMissionView extends StatelessWidget {
  final VoidCallback onRefresh;
  final String? error;
  const _NoMissionView({required this.onRefresh, this.error});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      children: [
        const SizedBox(height: 12),
        const _MonoHeader('~/ MISSIONS'),
        const SizedBox(height: 40),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: const Color(0xFF060D06),
            border: Border.all(color: const Color(0xFF0A1F0A)),
          ),
          child: const Column(children: [
            Icon(Icons.assignment_outlined, size: 52, color: Color(0xFF1F3D1F)),
            SizedBox(height: 20),
            Text('NO ACTIVE MISSION',
                style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                    color: Color(0xFF374151),
                    letterSpacing: 3)),
            SizedBox(height: 6),
            Text('Standing by for orders',
                style: TextStyle(fontSize: 12, color: Color(0xFF1F3D1F))),
          ]),
        ),
        if (error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0A0A),
              border: Border.all(color: const Color(0xFF7F1D1D)),
            ),
            child: Text('ERROR: $error',
                style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 10,
                    color: Color(0xFFFCA5A5))),
          ),
        ],
        const SizedBox(height: 20),
        GestureDetector(
          onTap: onRefresh,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF0A1F0A))),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh, size: 14, color: Color(0xFF374151)),
                SizedBox(width: 8),
                Text('REFRESH',
                    style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        color: Color(0xFF374151),
                        letterSpacing: 2)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Active Mission View ───────────────────────────────────────────────────────

class _MissionView extends StatelessWidget {
  final MissionData mission;
  final bool isLeader;
  final Map<String, bool> completing;
  final bool acknowledging;
  final bool completingMission;
  final VoidCallback onAcknowledge;
  final Future<void> Function(String) onCompleteObjective;
  final VoidCallback onOpenMap;
  final VoidCallback onIncident;
  final VoidCallback onEvidence;
  final VoidCallback onCasualty;
  final VoidCallback? onJoinBriefing;
  final VoidCallback? onJoinDebrief;
  final VoidCallback onCompleteMission;

  const _MissionView({
    required this.mission,
    required this.isLeader,
    required this.completing,
    required this.acknowledging,
    required this.completingMission,
    required this.onAcknowledge,
    required this.onCompleteObjective,
    required this.onOpenMap,
    required this.onIncident,
    required this.onEvidence,
    required this.onCasualty,
    required this.onCompleteMission,
    this.onJoinBriefing,
    this.onJoinDebrief,
  });

  @override
  Widget build(BuildContext context) {
    final pColor =
        _priorityColor[mission.priority] ?? const Color(0xFF3B82F6);
    final pBg = _priorityBg[mission.priority] ?? const Color(0xFF0C1E3D);
    final sLabel =
        _statusLabel[mission.status] ?? mission.status.toUpperCase();
    final sColor =
        _statusColor[mission.status] ?? const Color(0xFF6B7280);
    final current = mission.currentObjective;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        const _MonoHeader('~/ MISSIONS'),
        const SizedBox(height: 14),

        // ── Identity card ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF060D06),
            border: Border(
              left: BorderSide(color: pColor, width: 3),
              top: const BorderSide(color: Color(0xFF0A1F0A)),
              right: const BorderSide(color: Color(0xFF0A1F0A)),
              bottom: const BorderSide(color: Color(0xFF0A1F0A)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (mission.missionCode != null) ...[
                  Text(mission.missionCode!,
                      style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 9,
                          color: Color(0xFF4B5563),
                          letterSpacing: 2)),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: pBg,
                  child: Text(
                    mission.priority.toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 9,
                        color: pColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  color: sColor.withAlpha(30),
                  child: Text(sLabel,
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 9,
                          color: sColor,
                          letterSpacing: 1)),
                ),
              ]),
              const SizedBox(height: 10),
              Text(mission.name,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF0FDF4),
                      height: 1.2)),
              if (mission.areaOfOperations != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 12, color: Color(0xFF4B5563)),
                  const SizedBox(width: 4),
                  Text(mission.areaOfOperations!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF4B5563))),
                ]),
              ],
              const SizedBox(height: 12),
              Row(children: [
                _StatChip(Icons.people_outline,
                    '${mission.assignmentCount} TEAM${mission.assignmentCount != 1 ? "S" : ""}'),
                const SizedBox(width: 10),
                _StatChip(
                  Icons.flag_outlined,
                  '${mission.completedCount}/${mission.objectives.length} OBJ',
                  color: mission.completedCount > 0
                      ? const Color(0xFF22C55E)
                      : null,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onOpenMap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    color: const Color(0xFF052E16),
                    child: const Row(children: [
                      Icon(Icons.map_outlined,
                          size: 13, color: Color(0xFF22C55E)),
                      SizedBox(width: 5),
                      Text('VIEW MAP',
                          style: TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 10,
                              color: Color(0xFF22C55E),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                    ]),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Acknowledge banner ────────────────────────────────────────────────
        if (mission.status == 'pending_acknowledgement') ...[
          GestureDetector(
            onTap: acknowledging ? null : onAcknowledge,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0C1A2E),
                border: Border.all(color: const Color(0xFFA78BFA)),
              ),
              child: Row(children: [
                const Icon(Icons.notification_important_outlined,
                    size: 16, color: Color(0xFFA78BFA)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'MISSION ASSIGNED — TAP TO ACKNOWLEDGE',
                    style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        color: Color(0xFFA78BFA),
                        letterSpacing: 1),
                  ),
                ),
                if (acknowledging)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Color(0xFFA78BFA)))
                else
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFA78BFA)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Join briefing banner ──────────────────────────────────────────────
        if (mission.status == 'briefing') ...[
          GestureDetector(
            onTap: onJoinBriefing,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0A2E),
                border: Border.all(
                  color: onJoinBriefing != null
                      ? const Color(0xFF6366F1)
                      : const Color(0xFF374151),
                ),
              ),
              child: Row(children: [
                const Icon(Icons.live_tv_outlined,
                    size: 16, color: Color(0xFF6366F1)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    onJoinBriefing != null
                        ? 'LIVE BRIEFING IN PROGRESS — TAP TO JOIN'
                        : 'BRIEFING IN PROGRESS',
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        color: Color(0xFF6366F1),
                        letterSpacing: 1),
                  ),
                ),
                if (onJoinBriefing != null)
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFF6366F1)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Join debrief banner ───────────────────────────────────────────────
        if (mission.status == 'debrief') ...[
          GestureDetector(
            onTap: onJoinDebrief,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0030),
                border: Border.all(
                  color: onJoinDebrief != null
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF374151),
                ),
              ),
              child: Row(children: [
                const Icon(Icons.video_camera_front_outlined,
                    size: 16, color: Color(0xFFA78BFA)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    onJoinDebrief != null
                        ? 'DEBRIEF CALL IN PROGRESS — TAP TO JOIN'
                        : 'MISSION DEBRIEF IN PROGRESS',
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        color: Color(0xFFA78BFA),
                        letterSpacing: 1),
                  ),
                ),
                if (onJoinDebrief != null)
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFA78BFA)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Current objective card ────────────────────────────────────────────
        if (current != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF030F03),
              border: Border(
                left: BorderSide(color: current.typeColor, width: 3),
                top: BorderSide(color: current.typeColor.withAlpha(50)),
                right: BorderSide(color: current.typeColor.withAlpha(50)),
                bottom: BorderSide(color: current.typeColor.withAlpha(50)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(current.typeAction,
                    style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 9,
                        color: current.typeColor,
                        letterSpacing: 3)),
                const SizedBox(height: 8),
                Text(current.cleanTitle,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF0FDF4),
                        height: 1.2)),
                if (current.description != null) ...[
                  const SizedBox(height: 6),
                  Text(current.description!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                          height: 1.5)),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Text(
                    'Step ${mission.currentIndex + 1} of ${mission.objectives.length}  ·  ${mission.completedCount} done',
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 9,
                        color: Color(0xFF374151)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: completing[current.id] == true
                        ? null
                        : () => onCompleteObjective(current.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      color: completing[current.id] == true
                          ? const Color(0xFF0A1F0A)
                          : const Color(0xFF16A34A),
                      child: completing[current.id] == true
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: Colors.black))
                          : const Row(children: [
                              Icon(Icons.check_circle_outline,
                                  size: 13, color: Colors.black),
                              SizedBox(width: 5),
                              Text('MARK DONE',
                                  style: TextStyle(
                                      fontFamily: 'JetBrains Mono',
                                      fontSize: 10,
                                      color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1)),
                            ]),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── All complete banner ───────────────────────────────────────────────
        if (mission.allComplete && mission.status != 'completed') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF052E16),
            child: const Row(children: [
              Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ALL OBJECTIVES COMPLETE',
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      color: Color(0xFF16A34A),
                      letterSpacing: 1),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
        ],

        // ── Complete mission button (leaders) ─────────────────────────────────
        if (isLeader &&
            !const {'completed', 'archived'}.contains(mission.status)) ...[
          GestureDetector(
            onTap: completingMission ? null : onCompleteMission,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: completingMission
                  ? const Color(0xFF0A1F0A)
                  : const Color(0xFF16A34A),
              child: Center(
                child: completingMission
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.black))
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag, size: 14, color: Colors.black),
                          SizedBox(width: 8),
                          Text('MARK MISSION COMPLETE',
                              style: TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 11,
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2)),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (mission.status == 'completed') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF052E16),
            child: const Row(children: [
              Icon(Icons.verified, size: 16, color: Color(0xFF16A34A)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'MISSION COMPLETED',
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      color: Color(0xFF16A34A),
                      letterSpacing: 1),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],

        // ── Objectives timeline ───────────────────────────────────────────────
        if (mission.objectives.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF060D06),
              border: Border.all(color: const Color(0xFF0A1F0A)),
            ),
            child: const Row(children: [
              Icon(Icons.flag_outlined, size: 14, color: Color(0xFF374151)),
              SizedBox(width: 10),
              Text('No objectives have been assigned to this mission',
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      color: Color(0xFF374151))),
            ]),
          ),
        if (mission.objectives.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF060D06),
              border: Border.all(color: const Color(0xFF0A1F0A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MISSION OBJECTIVES',
                    style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 9,
                        color: Color(0xFF374151),
                        letterSpacing: 2)),
                const SizedBox(height: 14),
                ...mission.objectives.asMap().entries.map((e) {
                  final i = e.key;
                  final obj = e.value;
                  final isCurrent = i == mission.currentIndex;
                  final isDone = obj.isCompleted;
                  final dotColor = isDone
                      ? const Color(0xFF16A34A)
                      : isCurrent
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF1F3D1F);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(children: [
                            if (i > 0)
                              Container(
                                  width: 1.5,
                                  height: 12,
                                  color: const Color(0xFF0A1F0A)),
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: dotColor, width: 1.5),
                                color: isDone
                                    ? const Color(0xFF052E16)
                                    : isCurrent
                                        ? const Color(0xFF0A1F0A)
                                        : Colors.transparent,
                              ),
                              child: Center(
                                child: isDone
                                    ? const Icon(Icons.check,
                                        size: 12,
                                        color: Color(0xFF16A34A))
                                    : isCurrent
                                        ? const Text('➜',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF22C55E)))
                                        : Text('${i + 1}',
                                            style: const TextStyle(
                                                fontFamily: 'JetBrains Mono',
                                                fontSize: 9,
                                                color: Color(0xFF1F3D1F))),
                              ),
                            ),
                          ]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                    obj.cleanTitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: isDone
                                          ? const Color(0xFF374151)
                                          : isCurrent
                                              ? const Color(0xFFF0FDF4)
                                              : const Color(0xFF4B5563),
                                      fontWeight: isCurrent
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      decoration: isDone
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor:
                                          const Color(0xFF374151),
                                    ),
                                  ),
                                ),
                                if (obj.objectiveType.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    color: obj.typeColor.withAlpha(30),
                                    child: Text(obj.objectiveType,
                                        style: TextStyle(
                                            fontFamily: 'JetBrains Mono',
                                            fontSize: 8,
                                            color: obj.typeColor)),
                                  ),
                                ],
                              ]),
                            ),
                          ),
                        ],
                      ),
                      if (isCurrent)
                        Padding(
                          padding:
                              const EdgeInsets.only(left: 36, bottom: 4),
                          child: const Text('▶ ACTIVE',
                              style: TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 9,
                                  color: Color(0xFF22C55E))),
                        ),
                      if (isDone && obj.completedAt != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(left: 36, bottom: 4),
                          child: Text(
                            '✓ ${_fmtTime(obj.completedAt!)}',
                            style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 9,
                                color: Color(0xFF16A34A)),
                          ),
                        ),
                    ],
                  );
                }),
              ],
            ),
          ),
        const SizedBox(height: 10),

        // ── Quick field actions ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF060D06),
            border: Border.all(color: const Color(0xFF0A1F0A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('FIELD ACTIONS',
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 9,
                      color: Color(0xFF374151),
                      letterSpacing: 2)),
              const SizedBox(height: 12),
              Row(children: [
                _QuickAction(Icons.warning_amber_outlined, 'INCIDENT',
                    const Color(0xFFDC2626), onIncident),
                const SizedBox(width: 8),
                _QuickAction(Icons.photo_camera_outlined, 'EVIDENCE',
                    const Color(0xFF3B82F6), onEvidence),
                const SizedBox(width: 8),
                _QuickAction(Icons.personal_injury_outlined, 'CASUALTY',
                    const Color(0xFFEC4899), onCasualty),
                const SizedBox(width: 8),
                _QuickAction(
                  Icons.sos_outlined,
                  'ASSIST',
                  const Color(0xFFF59E0B),
                  () => Navigator.pushNamed(context, '/sos'),
                ),
              ]),
            ],
          ),
        ),

        // ── Briefing notes ────────────────────────────────────────────────────
        if (mission.briefingNotes?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFF030903),
              border: Border(
                left: BorderSide(color: Color(0xFF16A34A), width: 2),
                top: BorderSide(color: Color(0xFF0A1F0A)),
                right: BorderSide(color: Color(0xFF0A1F0A)),
                bottom: BorderSide(color: Color(0xFF0A1F0A)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BRIEFING NOTES',
                    style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 9,
                        color: Color(0xFF16A34A),
                        letterSpacing: 2)),
                const SizedBox(height: 8),
                Text(mission.briefingNotes!,
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                        color: Color(0xFFD1FAE5),
                        height: 1.7)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _MonoHeader extends StatelessWidget {
  final String text;
  const _MonoHeader(this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 4,
            height: 16,
            color: const Color(0xFF22C55E),
            margin: const EdgeInsets.only(right: 10)),
        Text(text,
            style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                color: Color(0xFF22C55E),
                letterSpacing: 3)),
      ]);
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _StatChip(this.icon, this.label, {this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 11, color: color ?? const Color(0xFF4B5563)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 9,
                color: color ?? const Color(0xFF4B5563),
                letterSpacing: 1)),
      ]);
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: color.withAlpha(15),
              border: Border.all(color: color.withAlpha(50)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 8,
                        color: color,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtTime(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}

// ── Sheet reusable pieces ─────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 32,
          height: 2,
          color: const Color(0xFF1F3D1F),
          margin: const EdgeInsets.only(bottom: 16),
        ),
      );
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('ERROR: $text',
            style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 10,
                color: Color(0xFFFCA5A5))),
      );
}

class _SheetDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final ValueChanged<T?> onChanged;
  final List<DropdownMenuItem<T>> items;
  const _SheetDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.items,
  });
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        initialValue: value,
        onChanged: onChanged,
        decoration: _sheetInput.copyWith(labelText: label),
        dropdownColor: const Color(0xFF0A0F0A),
        style: const TextStyle(fontSize: 12, color: Color(0xFFD1FAE5)),
        items: items,
      );
}

class _SubmitButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;
  const _SubmitButton({
    required this.label,
    required this.color,
    required this.loading,
    required this.onTap,
    this.disabled = false,
  });
  @override
  Widget build(BuildContext context) {
    final active = !loading && !disabled;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        color: disabled
            ? const Color(0xFF0A1F0A)
            : loading
                ? const Color(0xFF1F3D1F)
                : color,
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Colors.white))
              : Text(label,
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                      color: disabled
                          ? const Color(0xFF374151)
                          : Colors.white,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ── Incident Sheet ────────────────────────────────────────────────────────────

class _IncidentSheet extends StatefulWidget {
  final String missionId;
  const _IncidentSheet({required this.missionId});
  @override
  State<_IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<_IncidentSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _severity = 'medium';
  String _category = 'incident';
  bool _submitting = false;
  String? _err;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() { _submitting = true; _err = null; });
    try {
      await ApiService().post('/missions/${widget.missionId}/incidents', {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'severity': _severity,
        'report_category': _category,
        'incident_type': 'field_report',
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _err = e.toString(); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0F0A),
          border: Border(top: BorderSide(color: Color(0xFF0A1F0A))),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: ListView(controller: ctrl, children: [
          _SheetHandle(),
          const Text('REPORT INCIDENT',
              style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11,
                  color: Color(0xFFDC2626),
                  letterSpacing: 2)),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(fontSize: 13, color: Color(0xFFD1FAE5)),
            decoration:
                _sheetInput.copyWith(hintText: 'Incident title', labelText: 'TITLE'),
          ),
          const SizedBox(height: 10),
          _SheetDropdown<String>(
            label: 'SEVERITY',
            value: _severity,
            onChanged: (v) => setState(() => _severity = v!),
            items: const [
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'critical', child: Text('Critical')),
            ],
          ),
          const SizedBox(height: 10),
          _SheetDropdown<String>(
            label: 'CATEGORY',
            value: _category,
            onChanged: (v) => setState(() => _category = v!),
            items: const [
              DropdownMenuItem(value: 'incident', child: Text('Incident')),
              DropdownMenuItem(value: 'contact', child: Text('Contact Report')),
              DropdownMenuItem(value: 'intelligence', child: Text('Intelligence')),
              DropdownMenuItem(value: 'casualty', child: Text('Casualty')),
              DropdownMenuItem(value: 'evidence', child: Text('Evidence')),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            style: const TextStyle(fontSize: 13, color: Color(0xFFD1FAE5)),
            decoration: _sheetInput.copyWith(
                hintText: 'Describe the incident...', labelText: 'DESCRIPTION'),
          ),
          if (_err != null) _ErrorText(_err!),
          const SizedBox(height: 16),
          _SubmitButton(
            label: 'SUBMIT REPORT',
            color: const Color(0xFFDC2626),
            loading: _submitting,
            onTap: _submit,
          ),
        ]),
      ),
    );
  }
}

// ── Casualty Sheet ────────────────────────────────────────────────────────────

class _CasualtySheet extends StatefulWidget {
  final String missionId;
  const _CasualtySheet({required this.missionId});
  @override
  State<_CasualtySheet> createState() => _CasualtySheetState();
}

class _CasualtySheetState extends State<_CasualtySheet> {
  final _searchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type = 'WIA';
  bool _submitting = false;
  bool _loadingUsers = true;
  String? _err;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  Map<String, dynamic>? _selectedUser;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchCtrl.addListener(_onSearch);
  }

  Future<void> _loadUsers() async {
    try {
      final res = await ApiService().get('/users?page_size=200') as Map<String, dynamic>;
      final users = (res['users'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _users = users; _filtered = users; _loadingUsers = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _users
          : _users.where((u) {
              final name = ((u['full_name'] ?? u['username'] ?? '') as String).toLowerCase();
              return name.contains(q);
            }).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedUser == null) {
      setState(() => _err = 'Please select a team member');
      return;
    }
    setState(() { _submitting = true; _err = null; });
    try {
      await ApiService().post('/missions/${widget.missionId}/casualties', {
        'user_id': _selectedUser!['id'],
        'casualty_type': _type,
        'notes': _notesCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _err = e.toString(); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0F0A),
          border: Border(top: BorderSide(color: Color(0xFF0A1F0A))),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: ListView(controller: ctrl, children: [
          _SheetHandle(),
          const Text('CASUALTY REPORT',
              style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11,
                  color: Color(0xFFEC4899),
                  letterSpacing: 2)),
          const SizedBox(height: 16),
          // ── Personnel search ──
          const Text('PERSONNEL',
              style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 9,
                  color: Color(0xFF6B7280), letterSpacing: 2)),
          const SizedBox(height: 6),
          if (_selectedUser != null)
            GestureDetector(
              onTap: () => setState(() { _selectedUser = null; _searchCtrl.clear(); _filtered = _users; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF052E16),
                  border: Border.all(color: const Color(0xFF16A34A)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Icon(Icons.person, color: Color(0xFF22C55E), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    (_selectedUser!['full_name'] ?? _selectedUser!['username'] ?? '') as String,
                    style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 13),
                  )),
                  const Icon(Icons.close, color: Color(0xFF6B7280), size: 14),
                ]),
              ),
            )
          else ...[
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 13, color: Color(0xFFD1FAE5)),
              decoration: _sheetInput.copyWith(
                  hintText: 'Search team member…', labelText: 'SEARCH'),
            ),
            const SizedBox(height: 6),
            if (_loadingUsers)
              const Center(child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: Color(0xFFEC4899), strokeWidth: 1.5)))
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  color: const Color(0xFF060D06),
                  border: Border.all(color: const Color(0xFF1F2D1F)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final u = _filtered[i];
                    final name = (u['full_name'] ?? u['username'] ?? 'Unknown') as String;
                    final role = ((u['role'] ?? '') as String).replaceAll('_', ' ');
                    return InkWell(
                      onTap: () => setState(() { _selectedUser = u; _searchCtrl.clear(); }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        child: Row(children: [
                          const Icon(Icons.person_outline, color: Color(0xFF4B5563), size: 14),
                          const SizedBox(width: 8),
                          Expanded(child: Text(name,
                              style: const TextStyle(color: Colors.white, fontSize: 12))),
                          Text(role,
                              style: const TextStyle(color: Color(0xFF4B5563), fontSize: 10)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ],
          const SizedBox(height: 10),
          _SheetDropdown<String>(
            label: 'TYPE',
            value: _type,
            onChanged: (v) => setState(() => _type = v!),
            items: const [
              DropdownMenuItem(value: 'WIA', child: Text('Wounded (WIA)')),
              DropdownMenuItem(value: 'KIA', child: Text('Killed (KIA)')),
              DropdownMenuItem(value: 'MIA', child: Text('Missing (MIA)')),
              DropdownMenuItem(value: 'captured', child: Text('Captured')),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            style: const TextStyle(fontSize: 13, color: Color(0xFFD1FAE5)),
            decoration: _sheetInput.copyWith(
                hintText: 'Additional notes...', labelText: 'NOTES'),
          ),
          if (_err != null) _ErrorText(_err!),
          const SizedBox(height: 16),
          _SubmitButton(
            label: 'SUBMIT REPORT',
            color: const Color(0xFFEC4899),
            loading: _submitting,
            onTap: _submit,
          ),
        ]),
      ),
    );
  }
}

// ── Evidence Sheet ────────────────────────────────────────────────────────────

class _EvidenceSheet extends StatefulWidget {
  final String missionId;
  const _EvidenceSheet({required this.missionId});
  @override
  State<_EvidenceSheet> createState() => _EvidenceSheetState();
}

class _EvidenceSheetState extends State<_EvidenceSheet> {
  final _notesCtrl = TextEditingController();
  File? _image;
  bool _submitting = false;
  String? _err;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null && mounted) setState(() => _image = File(picked.path));
  }

  Future<void> _submit() async {
    if (_image == null) return;
    setState(() { _submitting = true; _err = null; });
    try {
      await ApiService().uploadFile(
        '/evidence',
        _image!,
        'file',
        extraFields: {
          'mission_id': widget.missionId,
          if (_notesCtrl.text.trim().isNotEmpty)
            'notes': _notesCtrl.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _err = e.toString(); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      maxChildSize: 0.88,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0F0A),
          border: Border(top: BorderSide(color: Color(0xFF0A1F0A))),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: ListView(controller: ctrl, children: [
          _SheetHandle(),
          const Text('UPLOAD EVIDENCE',
              style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11,
                  color: Color(0xFF3B82F6),
                  letterSpacing: 2)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFF060D06),
                border: Border.all(color: const Color(0xFF0A1F0A)),
              ),
              child: _image != null
                  ? Image.file(_image!, fit: BoxFit.cover)
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_camera_outlined,
                            size: 32, color: Color(0xFF374151)),
                        SizedBox(height: 8),
                        Text('TAP TO CAPTURE',
                            style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 10,
                                color: Color(0xFF374151),
                                letterSpacing: 2)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            style: const TextStyle(fontSize: 13, color: Color(0xFFD1FAE5)),
            decoration: _sheetInput.copyWith(
                hintText: 'Evidence description...', labelText: 'NOTES'),
          ),
          if (_err != null) _ErrorText(_err!),
          const SizedBox(height: 16),
          _SubmitButton(
            label: 'SUBMIT EVIDENCE',
            color: const Color(0xFF3B82F6),
            loading: _submitting,
            disabled: _image == null,
            onTap: _submit,
          ),
        ]),
      ),
    );
  }
}
