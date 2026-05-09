import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../config/constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/storage_service.dart';

class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key});

  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen> {
  final StorageService _storage = StorageService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  WebSocketChannel? _signalingWs;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isConnecting = true;
  String? _roomId;
  String? _myId;
  String? _myName;
  String? _teamName;
  Timer? _keepAliveTimer;

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startFeed());
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _signalingWs?.sink.close();
    _localStream?.dispose();
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) { r.dispose(); }
    for (final pc in _peerConnections.values) { pc.close(); }
    super.dispose();
  }

  Future<void> _startFeed() async {
    final auth = context.read<AuthProvider>();
    final loc = context.read<LocationProvider>();
    _myId = auth.user?.id;
    _myName = auth.user?.fullName ?? auth.user?.username ?? 'Field Unit';
    _teamName = auth.user?.teamName ?? '';
    _roomId = _myId;

    // Request permissions
    await [Permission.camera, Permission.microphone].request();

    // Get local camera stream
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': 'environment', 'width': 640, 'height': 480},
        'audio': true,
      });
      _localRenderer.srcObject = _localStream;
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Connect to signaling server
    final token = await _storage.getToken();
    if (token == null || !mounted) return;

    final wsBase = AppConstants.wsUrl.replaceAll('/ws', '');
    final wsUrl = '$wsBase/ws/video/$_roomId?token=$token';
    _signalingWs = WebSocketChannel.connect(Uri.parse(wsUrl));

    _signalingWs!.stream.listen(_onSignalingMessage, onDone: _onWsClosed);

    // Join the room
    _send({
      'type': 'join',
      'room_id': _roomId,
      'user_id': _myId,
      'user_name': _myName,
      'team_name': _teamName,
      'lat': loc.latitude,
      'lng': loc.longitude,
    });

    setState(() => _isConnecting = false);

    // Keep-alive ping
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _send({'type': 'ping'});
    });
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _signalingWs?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _onWsClosed() {
    if (mounted) setState(() => _isConnecting = true);
  }

  Future<void> _onSignalingMessage(dynamic raw) async {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = msg['type'] as String?;
    final peerId = msg['from_id'] as String? ?? msg['peer_id'] as String?;

    switch (type) {
      case 'request_ignored':
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.block_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Command declined your live feed request.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFEF4444),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.pop(context);
        }

      case 'peer_joined':
        if (peerId != null && peerId != _myId) {
          await _createOffer(peerId);
        }

      case 'offer':
        if (peerId != null && peerId != _myId) {
          await _handleOffer(peerId, msg['sdp'] as String);
        }

      case 'answer':
        if (peerId != null) {
          final pc = _peerConnections[peerId];
          if (pc != null) {
            await pc.setRemoteDescription(RTCSessionDescription(msg['sdp'] as String, 'answer'));
          }
        }

      case 'ice':
        if (peerId != null) {
          final pc = _peerConnections[peerId];
          if (pc != null) {
            final c = msg['candidate'] as Map<String, dynamic>;
            await pc.addCandidate(RTCIceCandidate(
              c['candidate'] as String?,
              c['sdpMid'] as String?,
              c['sdpMLineIndex'] as int?,
            ));
          }
        }
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String peerId) async {
    final pc = await createPeerConnection(_iceServers);

    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onIceCandidate = (candidate) {
      _send({
        'type': 'ice',
        'room_id': _roomId,
        'from_id': _myId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onTrack = (event) async {
      if (event.streams.isEmpty) return;
      if (!_remoteRenderers.containsKey(peerId)) {
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        _remoteRenderers[peerId] = renderer;
      }
      if (mounted) {
        setState(() {
          _remoteRenderers[peerId]!.srcObject = event.streams.first;
        });
      }
    };

    _peerConnections[peerId] = pc;
    return pc;
  }

  Future<void> _createOffer(String peerId) async {
    final pc = await _createPeerConnection(peerId);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _send({'type': 'offer', 'room_id': _roomId, 'from_id': _myId, 'sdp': offer.sdp});
  }

  Future<void> _handleOffer(String peerId, String sdpStr) async {
    final pc = await _createPeerConnection(peerId);
    await pc.setRemoteDescription(RTCSessionDescription(sdpStr, 'offer'));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _send({'type': 'answer', 'room_id': _roomId, 'from_id': _myId, 'sdp': answer.sdp});
  }

  void _toggleMute() {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _isMuted);
    setState(() => _isMuted = !_isMuted);
    _send({'type': 'mute', 'room_id': _roomId, 'from_id': _myId, 'muted': _isMuted});
  }

  void _toggleCamera() {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _isCameraOff);
    setState(() => _isCameraOff = !_isCameraOff);
  }

  void _endFeed() {
    _send({'type': 'leave', 'room_id': _roomId, 'from_id': _myId});
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Local video (full screen when no remote, small pip otherwise)
            if (_remoteRenderers.isEmpty)
              RTCVideoView(_localRenderer, mirror: false, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            else
              Positioned(bottom: 100, right: 12, width: 100, height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: RTCVideoView(_localRenderer, mirror: false),
                ),
              ),

            // Remote feeds
            if (_remoteRenderers.isNotEmpty)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderers.values.first,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),

            // Top bar
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                          SizedBox(width: 4),
                          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11,
                              fontWeight: FontWeight.w800, letterSpacing: 1)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$_myName · $_teamName',
                        style: const TextStyle(color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_isConnecting)
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _controlBtn(
                      icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      active: _isMuted,
                      onTap: _toggleMute,
                    ),
                    _controlBtn(
                      icon: _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                      label: _isCameraOff ? 'Camera On' : 'Camera Off',
                      active: _isCameraOff,
                      onTap: _toggleCamera,
                    ),
                    GestureDetector(
                      onTap: _endFeed,
                      child: Container(
                        width: 60, height: 60,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFEF4444),
                        ),
                        child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlBtn({required IconData icon, required String label, bool active = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10,
              fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
