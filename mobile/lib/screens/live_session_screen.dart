import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/environment.dart';
import '../providers/auth_provider.dart';
import '../providers/team_provider.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';

// ── Session model ─────────────────────────────────────────────────────────────

class _Session {
  final String id;
  final String title;
  final String hostId;
  final bool isActive;
  final List<String> inviteList;
  final String? startedAt;
  final String? roomId;
  final String? missionId;

  const _Session({
    required this.id,
    required this.title,
    required this.hostId,
    required this.isActive,
    required this.inviteList,
    this.startedAt,
    this.roomId,
    this.missionId,
  });

  factory _Session.fromJson(Map<String, dynamic> j) => _Session(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Untitled',
        hostId: j['host_id'] as String? ?? '',
        isActive: j['is_active'] as bool? ?? false,
        inviteList:
            (j['invite_list'] as List<dynamic>?)?.cast<String>() ?? [],
        startedAt: j['started_at'] as String?,
        roomId: j['room_id'] as String?,
        missionId: j['mission_id'] as String?,
      );
}

// ── Per-peer WebRTC state ─────────────────────────────────────────────────────

class _PeerState {
  final String userId;
  final String name;
  final RTCPeerConnection pc;
  final RTCVideoRenderer renderer;
  MediaStream? stream;

  _PeerState({
    required this.userId,
    required this.name,
    required this.pc,
    required this.renderer,
  });
}

// ── Main screen ───────────────────────────────────────────────────────────────

class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({super.key});

  static String? pendingJoinSessionId;

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  List<_Session> _sessions = [];
  bool _loading = true;
  final _titleCtrl = TextEditingController();
  bool _creating = false;
  bool _showInvite = false;
  Set<String> _selTeams = {};
  Set<String> _selUsers = {};

  // Active call
  _Session? _activeSession;

  // Pending live-session invite banner
  String? _pendingInviteId;
  String? _pendingInviteTitle;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      final pendingId = LiveSessionScreen.pendingJoinSessionId;
      if (pendingId != null) {
        LiveSessionScreen.pendingJoinSessionId = null;
        _joinSession(pendingId);
      }
    });
    PushNotificationService.instance.setLiveInviteCallback((id, title) {
      if (mounted) {
        setState(() {
          _pendingInviteId = id;
          _pendingInviteTitle = title;
        });
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    PushNotificationService.instance.clearLiveInviteCallback();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService().get('/live-sessions') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _sessions = data
            .map((e) => _Session.fromJson(e as Map<String, dynamic>))
            .where((s) => s.isActive)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createSession() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _creating = true);
    try {
      final res = await ApiService().post('/live-sessions', {
        'title': title,
        'invite_team_ids': _selTeams.toList(),
        'invite_user_ids': _selUsers.toList(),
      });
      _titleCtrl.clear();
      setState(() {
        _selTeams = {};
        _selUsers = {};
        _showInvite = false;
      });
      final session = _Session.fromJson(res);
      await _load();
      if (mounted) {
        setState(() => _activeSession = session);
      }
    } catch (e) {
      _showSnack('Failed to create session');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      await ApiService().delete('/live-sessions/$sessionId');
      await _load();
      _showSnack('Session ended', success: true);
    } catch (_) {
      _showSnack('Failed to delete session');
    }
  }

  void _joinSession(String sessionId) {
    final existing = _sessions.where((s) => s.id == sessionId).toList();
    if (existing.isNotEmpty) {
      setState(() => _activeSession = existing.first);
    } else {
      _load().then((_) {
        if (!mounted) return;
        final found = _sessions.where((s) => s.id == sessionId).toList();
        if (found.isNotEmpty) setState(() => _activeSession = found.first);
      });
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor:
          success ? const Color(0xFF16A34A) : const Color(0xFF7F1D1D),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.select<AuthProvider, String?>((a) => a.user?.id);
    final teams = context.watch<TeamProvider>().teams;

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: _activeSession == null
          ? AppBar(
              backgroundColor: const Color(0xFF0F172A),
              title: Row(children: [
                const Icon(Icons.live_tv,
                    color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 8),
                const Text('Live Feeds',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                if (_sessions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFF7F1D1D),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('${_sessions.length} LIVE',
                        style: const TextStyle(
                            color: Color(0xFFFCA5A5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                    icon: const Icon(Icons.refresh,
                        color: Color(0xFF9CA3AF)),
                    onPressed: _load),
              ],
            )
          : null,
      body: Stack(
        children: [
          if (_activeSession != null)
            _CallView(
              roomId: _activeSession!.id,
              title: _activeSession!.title,
              sessionId: _activeSession!.id,
              myId: myId ?? '',
              isHost: _activeSession!.hostId == myId,
              missionId: _activeSession!.missionId,
              onLeave: () {
                setState(() => _activeSession = null);
                _load();
              },
            )
          else
            _buildList(myId, teams),

          // Pending live-session invite banner
          if (_pendingInviteId != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1B00),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: const Color(0xFFDC2626), width: 2),
                  ),
                  child: Row(children: [
                    const Icon(Icons.live_tv,
                        color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                      'LIVE: ${_pendingInviteTitle ?? "Session"}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    )),
                    TextButton(
                      onPressed: () => setState(() {
                        _pendingInviteId = null;
                        _pendingInviteTitle = null;
                      }),
                      child: const Text('Decline',
                          style: TextStyle(
                              color: Color(0xFF6B7280), fontSize: 12)),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final id = _pendingInviteId!;
                        setState(() {
                          _pendingInviteId = null;
                          _pendingInviteTitle = null;
                        });
                        _joinSession(id);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(60, 32),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Join',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(String? myId, List<TeamData> teams) {
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF22C55E),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Create session card
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF060D06),
              border: Border.all(color: const Color(0xFF1A2E1A)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Start a Live Briefing',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Session title…',
                        hintStyle:
                            const TextStyle(color: Color(0xFF4B5563)),
                        filled: true,
                        fillColor: const Color(0xFF040804),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF1F2D1F))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF1F2D1F))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF16A34A))),
                      ),
                      onSubmitted: (_) => _createSession(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showInvite = !_showInvite),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _showInvite
                            ? const Color(0xFF14532D)
                            : const Color(0xFF0A140A),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: const Color(0xFF16A34A)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.group_add,
                            color: Color(0xFF22C55E), size: 18),
                        if (_selTeams.isNotEmpty ||
                            _selUsers.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                              '${_selTeams.length + _selUsers.length}',
                              style: const TextStyle(
                                  color: Color(0xFF22C55E),
                                  fontSize: 11)),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _creating ? null : _createSession,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _creating
                            ? const Color(0xFF374151)
                            : const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _creating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('GO LIVE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                    ),
                  ),
                ]),
                if (_showInvite) ...[
                  const SizedBox(height: 12),
                  _InviteSelector(
                    teams: teams
                        .map((t) => {'id': t.id, 'name': t.name})
                        .toList(),
                    selTeams: _selTeams,
                    selUsers: _selUsers,
                    onTeamToggle: (id) => setState(() =>
                        _selTeams.contains(id)
                            ? _selTeams.remove(id)
                            : _selTeams.add(id)),
                    onUserToggle: (id) => setState(() =>
                        _selUsers.contains(id)
                            ? _selUsers.remove(id)
                            : _selUsers.add(id)),
                  ),
                ],
              ],
            ),
          ),

          // Active sessions list
          if (_loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: CircularProgressIndicator(
                        color: Color(0xFF22C55E))))
          else if (_sessions.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Column(children: [
                  Icon(Icons.live_tv,
                      color: Color(0xFF374151), size: 48),
                  SizedBox(height: 12),
                  Text('No active sessions',
                      style: TextStyle(
                          color: Color(0xFF6B7280), fontSize: 13)),
                ]),
              ),
            )
          else
            ...(_sessions.map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF060D06),
                    border: Border.all(
                        color: s.hostId == myId
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF1A2E1A)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: const Color(0xFF7F1D1D),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.live_tv,
                          color: Color(0xFFEF4444), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF7F1D1D),
                                  borderRadius:
                                      BorderRadius.circular(4)),
                              child: const Text('LIVE',
                                  style: TextStyle(
                                      color: Color(0xFFFCA5A5),
                                      fontSize: 9,
                                      fontWeight:
                                          FontWeight.bold,
                                      letterSpacing: 1)),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(s.title,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight:
                                            FontWeight.w600),
                                    overflow:
                                        TextOverflow.ellipsis)),
                          ]),
                          const SizedBox(height: 3),
                          Text(
                            s.hostId == myId
                                ? 'Your session'
                                : 'Tap to join',
                            style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 11),
                          ),
                        ])),
                    // Join button
                    GestureDetector(
                      onTap: () =>
                          setState(() => _activeSession = s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Join',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    // Delete button (host only)
                    if (s.hostId == myId) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _confirmDelete(s),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7F1D1D)
                                .withValues(alpha: 0.4),
                            borderRadius:
                                BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFF7F1D1D)),
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: Color(0xFFEF4444), size: 16),
                        ),
                      ),
                    ],
                  ]),
                ))),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(_Session s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('End Session',
            style: TextStyle(color: Colors.white)),
        content: Text(
            'End "${s.title}" for all participants?',
            style: const TextStyle(color: Color(0xFF9CA3AF))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF6B7280)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('End Session',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteSession(s.id);
  }
}

// ── WebRTC call view ──────────────────────────────────────────────────────────

class _CallView extends StatefulWidget {
  final String roomId;
  final String title;
  final String sessionId;
  final String myId;
  final bool isHost;
  final String? missionId;
  final VoidCallback onLeave;

  const _CallView({
    required this.roomId,
    required this.title,
    required this.sessionId,
    required this.myId,
    required this.isHost,
    required this.onLeave,
    this.missionId,
  });

  @override
  State<_CallView> createState() => _CallViewState();
}

class _CallViewState extends State<_CallView> {
  // WebSocket
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;

  // Local media
  MediaStream? _localStream;
  final _localRenderer = RTCVideoRenderer();
  bool _localRendererInit = false;

  // Peers
  final Map<String, _PeerState> _peers = {};

  // Controls state
  bool _muted = false;
  bool _cameraOff = false;
  bool _ending = false;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  // ── Startup ────────────────────────────────────────────────────────────────

  Future<void> _start() async {
    await _initLocalRenderer();
    await _openLocalMedia();
    _connectWs();
  }

  Future<void> _initLocalRenderer() async {
    await _localRenderer.initialize();
    if (mounted) setState(() => _localRendererInit = true);
  }

  Future<void> _openLocalMedia() async {
    try {
      final stream = await navigator.mediaDevices
          .getUserMedia({'video': true, 'audio': true});
      _localStream = stream;
      _localRenderer.srcObject = stream;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[WebRTC] getUserMedia error: $e');
    }
  }

  void _connectWs() {
    final token = StorageService().accessToken;
    if (token == null) return;

    final uri = Uri.parse(
        '${EnvironmentConfig.wsBaseUrl}/ws/video/${widget.roomId}?token=${Uri.encodeComponent(token)}');

    try {
      _ws = WebSocketChannel.connect(uri);
      _wsSub = _ws!.stream.listen(
        (raw) {
          try {
            _handleSignal(
                jsonDecode(raw as String) as Map<String, dynamic>);
          } catch (_) {}
        },
        onDone: () => debugPrint('[WebRTC] WS closed'),
        onError: (e) => debugPrint('[WebRTC] WS error: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[WebRTC] WS connect error: $e');
    }
  }

  // ── Signaling ──────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  Future<void> _handleSignal(Map<String, dynamic> msg) async {
    final type = msg['type'] as String? ?? '';

    switch (type) {
      case 'room_state':
        // Server sends current peers in the room
        final peers = (msg['peers'] as List<dynamic>?) ?? [];
        for (final p in peers) {
          final peerId = p['user_id'] as String? ?? p as String;
          final peerName = p is Map
              ? (p['name'] as String? ?? peerId)
              : peerId;
          if (peerId != widget.myId && !_peers.containsKey(peerId)) {
            await _createOffer(peerId, peerName);
          }
        }

      case 'peer_joined':
        final peerId = msg['user_id'] as String? ?? '';
        // New joiner sends us offers via room_state; we just update state here
        if (peerId.isNotEmpty && peerId != widget.myId) {
          if (mounted) setState(() {});
        }

      case 'offer':
        final from = msg['from'] as String? ?? '';
        final fromName = msg['name'] as String? ?? from;
        final sdp = msg['sdp'] as Map<String, dynamic>?;
        if (from.isNotEmpty && sdp != null) {
          await _handleOffer(from, fromName, sdp);
        }

      case 'answer':
        final from = msg['from'] as String? ?? '';
        final sdp = msg['sdp'] as Map<String, dynamic>?;
        if (from.isNotEmpty && sdp != null && _peers.containsKey(from)) {
          await _peers[from]!.pc.setRemoteDescription(
            RTCSessionDescription(
                sdp['sdp'] as String, sdp['type'] as String),
          );
        }

      case 'ice_candidate':
        final from = msg['from'] as String? ?? '';
        final candidate = msg['candidate'] as Map<String, dynamic>?;
        if (from.isNotEmpty &&
            candidate != null &&
            _peers.containsKey(from)) {
          await _peers[from]!.pc.addCandidate(RTCIceCandidate(
            candidate['candidate'] as String?,
            candidate['sdpMid'] as String?,
            candidate['sdpMLineIndex'] as int?,
          ));
        }

      case 'peer_left':
        final peerId = msg['user_id'] as String? ?? '';
        if (peerId.isNotEmpty) {
          await _removePeer(peerId);
        }
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(
      String peerId, String peerName) async {
    if (_peers.containsKey(peerId)) return _peers[peerId]!.pc;

    final pc = await createPeerConnection(_iceConfig);

    // Add local tracks to the connection
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _send({
        'type': 'ice_candidate',
        'target': peerId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onTrack = (event) async {
      if (event.streams.isEmpty) return;
      final peer = _peers[peerId];
      if (peer == null) return;
      peer.stream = event.streams.first;
      peer.renderer.srcObject = event.streams.first;
      if (mounted) setState(() {});
    };

    pc.onConnectionState = (state) {
      debugPrint('[WebRTC] peer $peerId connection: $state');
    };

    final renderer = RTCVideoRenderer();
    await renderer.initialize();

    final peerState = _PeerState(
      userId: peerId,
      name: peerName,
      pc: pc,
      renderer: renderer,
    );
    _peers[peerId] = peerState;
    if (mounted) setState(() {});

    return pc;
  }

  Future<void> _createOffer(String peerId, String peerName) async {
    final pc = await _createPeerConnection(peerId, peerName);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _send({
      'type': 'offer',
      'target': peerId,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  Future<void> _handleOffer(
      String from, String fromName, Map<String, dynamic> sdp) async {
    RTCPeerConnection pc;
    if (_peers.containsKey(from)) {
      pc = _peers[from]!.pc;
    } else {
      pc = await _createPeerConnection(from, fromName);
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(
          sdp['sdp'] as String, sdp['type'] as String),
    );

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _send({
      'type': 'answer',
      'target': from,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
  }

  Future<void> _removePeer(String peerId) async {
    final peer = _peers.remove(peerId);
    if (peer == null) return;
    await peer.pc.close();
    peer.renderer.srcObject = null;
    await peer.renderer.dispose();
    if (mounted) setState(() {});
  }

  // ── Controls ───────────────────────────────────────────────────────────────

  void _toggleMute() {
    final audioTracks = _localStream?.getAudioTracks() ?? [];
    for (final t in audioTracks) {
      t.enabled = _muted; // toggle: if muted, re-enable
    }
    setState(() => _muted = !_muted);
  }

  void _toggleCamera() {
    final videoTracks = _localStream?.getVideoTracks() ?? [];
    for (final t in videoTracks) {
      t.enabled = _cameraOff; // toggle: if off, re-enable
    }
    setState(() => _cameraOff = !_cameraOff);
  }

  Future<void> _flipCamera() async {
    final videoTracks = _localStream?.getVideoTracks() ?? [];
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
  }

  Future<void> _leaveCall() async {
    if (widget.isHost) {
      setState(() => _ending = true);
      try {
        await ApiService()
            .post('/live-sessions/${widget.sessionId}/end', {});
      } catch (_) {}
    }
    // Auto-mark briefing attendance when leaving a mission briefing call
    if (widget.missionId != null) {
      try {
        await ApiService()
            .post('/missions/${widget.missionId}/briefing/attend', {});
      } catch (_) {}
    }
    await _cleanup();
    widget.onLeave();
  }

  Future<void> _cleanup() async {
    await _wsSub?.cancel();
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;

    // Stop local tracks
    if (_localStream != null) {
      for (final t in _localStream!.getTracks()) {
        await t.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    _localRenderer.srcObject = null;
    if (_localRendererInit) await _localRenderer.dispose();

    // Close peers
    final peerIds = _peers.keys.toList();
    for (final id in peerIds) {
      await _removePeer(id);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote videos area
            _buildRemoteArea(),

            // Local video PiP (top-right)
            Positioned(
              top: 56,
              right: 12,
              child: _buildLocalPiP(),
            ),

            // Status bar (top)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildStatusBar(),
            ),

            // Controls (bottom)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent
          ],
        ),
      ),
      child: Row(children: [
        // Animated red LIVE dot
        _LiveDot(),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          widget.title,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        )),
        // Participant count
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.people, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text('${_peers.length + 1}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildRemoteArea() {
    if (_peers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off,
                color: Color(0xFF374151), size: 56),
            const SizedBox(height: 16),
            const Text(
              'Waiting for others to join…',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.key, color: Color(0xFF6B7280), size: 14),
                const SizedBox(width: 6),
                Text(
                  'Room: ${widget.roomId}',
                  style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ]),
            ),
          ],
        ),
      );
    }

    final peerList = _peers.values.toList();

    if (peerList.length == 1) {
      // Single remote peer — full screen
      final peer = peerList.first;
      return SizedBox.expand(
        child: _RemoteVideo(peer: peer),
      );
    }

    // Multiple peers — grid
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(4, 52, 4, 130),
      itemCount: peerList.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 3 / 4,
      ),
      itemBuilder: (_, i) => _RemoteVideo(peer: peerList[i]),
    );
  }

  Widget _buildLocalPiP() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 120,
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Stack(
          children: [
            if (_localRendererInit && !_cameraOff)
              Transform.scale(
                scaleX: -1,
                child: RTCVideoView(
                  _localRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              const Center(
                child: Icon(Icons.videocam_off,
                    color: Color(0xFF6B7280), size: 28),
              ),
            // "You" label
            Positioned(
              bottom: 4,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('You',
                      style:
                          TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.transparent
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute
          _ControlBtn(
            icon: _muted ? Icons.mic_off : Icons.mic,
            label: _muted ? 'Unmute' : 'Mute',
            active: _muted,
            onTap: _toggleMute,
          ),
          // Camera
          _ControlBtn(
            icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
            label: _cameraOff ? 'Start Video' : 'Stop Video',
            active: _cameraOff,
            onTap: _toggleCamera,
          ),
          // Flip camera
          _ControlBtn(
            icon: Icons.flip_camera_ios,
            label: 'Flip',
            active: false,
            onTap: _flipCamera,
          ),
          // End / Leave
          _ControlBtn(
            icon: Icons.call_end,
            label: widget.isHost ? 'End for All' : 'Leave',
            active: true,
            activeColor: const Color(0xFFDC2626),
            onTap: _ending ? null : _leaveCall,
            loading: _ending,
          ),
        ],
      ),
    );
  }
}

// ── Remote video tile ─────────────────────────────────────────────────────────

class _RemoteVideo extends StatelessWidget {
  final _PeerState peer;

  const _RemoteVideo({required this.peer});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (peer.stream != null)
            RTCVideoView(
              peer.renderer,
              objectFit:
                  RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Container(
              color: const Color(0xFF1F2937),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF374151),
                      child: Text(
                        peer.name.isNotEmpty
                            ? peer.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Connecting…',
                        style: TextStyle(
                            color: Color(0xFF6B7280), fontSize: 11)),
                  ],
                ),
              ),
            ),
          // Name label
          Positioned(
            bottom: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                peer.name,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Control button ────────────────────────────────────────────────────────────

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;
  final bool loading;

  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.active,
    this.activeColor = const Color(0xFF374151),
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? activeColor : const Color(0xFF1F2937);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(
                  color: active
                      ? activeColor.withValues(alpha: 0.5)
                      : const Color(0xFF374151)),
            ),
            child: loading
                ? const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)))
                : Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 10)),
        ],
      ),
    );
  }
}

// ── Animated LIVE dot ─────────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Color.fromRGBO(
                  239, 68, 68, _anim.value),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF7F1D1D),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('LIVE',
                style: TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}

// ── Invite selector widget ─────────────────────────────────────────────────────

class _InviteSelector extends StatefulWidget {
  final List<Map<String, String>> teams;
  final Set<String> selTeams;
  final Set<String> selUsers;
  final void Function(String) onTeamToggle;
  final void Function(String) onUserToggle;

  const _InviteSelector({
    required this.teams,
    required this.selTeams,
    required this.selUsers,
    required this.onTeamToggle,
    required this.onUserToggle,
  });

  @override
  State<_InviteSelector> createState() => _InviteSelectorState();
}

class _InviteSelectorState extends State<_InviteSelector> {
  bool _showTeams = true;
  List<Map<String, dynamic>> _users = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final res = await ApiService().get('/users?page_size=100')
          as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _users =
          (res['users'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filteredTeams = widget.teams
        .where((t) =>
            (t['name'] ?? '').toLowerCase().contains(_q.toLowerCase()))
        .toList();
    final filteredUsers = _users.where((u) {
      final name = (u['full_name'] as String? ??
              u['username'] as String? ??
              '')
          .toLowerCase();
      return name.contains(_q.toLowerCase());
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF040804),
        border: Border.all(color: const Color(0xFF1F2D1F)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(children: [
            _tab(
                'Teams (${widget.selTeams.length})',
                _showTeams,
                () => setState(() => _showTeams = true)),
            _tab(
                'Users (${widget.selUsers.length})',
                !_showTeams,
                () => setState(() => _showTeams = false)),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style:
                  const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Search…',
                hintStyle: TextStyle(color: Color(0xFF4B5563)),
                isDense: true,
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search,
                    color: Color(0xFF4B5563), size: 16),
              ),
            ),
          ),
          SizedBox(
            height: 140,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              children: _showTeams
                  ? filteredTeams
                      .map((t) => _checkRow(
                            t['name'] ?? '',
                            null,
                            widget.selTeams.contains(t['id']),
                            () => widget.onTeamToggle(t['id']!),
                          ))
                      .toList()
                  : filteredUsers
                      .map((u) => _checkRow(
                            u['full_name'] as String? ??
                                u['username'] as String? ??
                                '',
                            u['role'] as String?,
                            widget.selUsers
                                .contains(u['id'] as String),
                            () =>
                                widget.onUserToggle(u['id'] as String),
                          ))
                      .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: active
                          ? const Color(0xFF22C55E)
                          : Colors.transparent,
                      width: 2)),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF4B5563),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ),
      );

  Widget _checkRow(
          String name, String? sub, bool checked, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(
                checked
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                color: checked
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF374151),
                size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12))),
            if (sub != null)
              Text(sub.replaceAll('_', ' '),
                  style: const TextStyle(
                      color: Color(0xFF4B5563), fontSize: 10)),
          ]),
        ),
      );
}
