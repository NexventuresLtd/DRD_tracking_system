import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/storage_service.dart';
import '../config/environment.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Video Call Screen
// ─────────────────────────────────────────────────────────────────────────────

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String roomTitle;

  const VideoCallScreen({
    super.key,
    required this.roomId,
    required this.roomTitle,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  // WebSocket
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;

  // Local media
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  // Peer connections: peerId → RTCPeerConnection
  final Map<String, RTCPeerConnection> _peers = {};
  // Remote renderers: peerId → RTCVideoRenderer
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  bool _micMuted = false;
  bool _cameraOff = false;
  bool _connected = false;
  int _peerCount = 0;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _getUserMedia();
    _connectWS();
  }

  Future<void> _getUserMedia() async {
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': true,
      });
      _localStream = stream;
      _localRenderer.srcObject = stream;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera/mic error: $e')),
        );
      }
    }
  }

  void _connectWS() {
    final token = StorageService().accessToken;
    if (token == null) return;
    final wsBase = EnvironmentConfig.wsBaseUrl;
    final uri = Uri.parse('$wsBase/ws/video/${widget.roomId}?token=${Uri.encodeComponent(token)}');
    _wsChannel = WebSocketChannel.connect(uri);
    _wsSub = _wsChannel!.stream.listen(
      _onWsMessage,
      onDone: () => setState(() => _connected = false),
      onError: (_) => setState(() => _connected = false),
    );
    setState(() => _connected = true);
  }

  void _onWsMessage(dynamic data) async {
    if (!mounted) return;
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    final type = msg['type'] as String?;

    switch (type) {
      case 'room_state':
        final peers = (msg['peers'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map((p) => p['user_id'] as String)
            .toList();
        for (final peerId in peers) {
          await _initiateOffer(peerId);
        }
        setState(() { _connected = true; _peerCount = peers.length; });

      case 'peer_joined':
        final peerId = msg['user_id'] as String?;
        if (peerId != null) {
          // New joiner sends offers to us via room_state; we wait for their offer
          setState(() => _peerCount = (msg['participant_count'] as int? ?? _peerCount + 1) - 1);
        }

      case 'peer_left':
        final peerId = msg['user_id'] as String?;
        if (peerId != null) {
          await _removePeer(peerId);
          setState(() => _peerCount = _peers.length);
        }

      case 'offer':
        final fromId = msg['from'] as String?;
        final sdpMap = msg['sdp'] as Map<String, dynamic>?;
        if (fromId != null && sdpMap != null) {
          await _handleOffer(fromId, sdpMap);
        }

      case 'answer':
        final fromId = msg['from'] as String?;
        final sdpMap = msg['sdp'] as Map<String, dynamic>?;
        if (fromId != null && sdpMap != null) {
          final pc = _peers[fromId];
          if (pc != null) {
            await pc.setRemoteDescription(
              RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String),
            );
          }
        }

      case 'ice_candidate':
        final fromId = msg['from'] as String?;
        final candidateMap = msg['candidate'] as Map<String, dynamic>?;
        if (fromId != null && candidateMap != null) {
          final pc = _peers[fromId];
          if (pc != null) {
            await pc.addCandidate(RTCIceCandidate(
              candidateMap['candidate'] as String?,
              candidateMap['sdpMid'] as String?,
              candidateMap['sdpMLineIndex'] as int?,
            ));
          }
        }
    }
  }

  Future<RTCPeerConnection> _createPeer(String peerId) async {
    if (_peers.containsKey(peerId)) return _peers[peerId]!;

    final pc = await createPeerConnection(_iceConfig);

    // Add local tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    // Remote track → renderer
    pc.onTrack = (event) async {
      if (event.streams.isNotEmpty && mounted) {
        if (!_remoteRenderers.containsKey(peerId)) {
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          _remoteRenderers[peerId] = renderer;
        }
        _remoteRenderers[peerId]!.srcObject = event.streams[0];
        if (mounted) setState(() {});
      }
    };

    // ICE candidate → send to peer
    pc.onIceCandidate = (candidate) {
      _wsSend({
        'type': 'ice_candidate',
        'target': peerId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onConnectionState = (state) {
      if (mounted) setState(() {});
    };

    _peers[peerId] = pc;
    return pc;
  }

  Future<void> _initiateOffer(String peerId) async {
    final pc = await _createPeer(peerId);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _wsSend({
      'type': 'offer',
      'target': peerId,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  Future<void> _handleOffer(String fromId, Map<String, dynamic> sdpMap) async {
    final pc = await _createPeer(fromId);
    await pc.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String),
    );
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _wsSend({
      'type': 'answer',
      'target': fromId,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
    if (mounted) setState(() => _peerCount = _peers.length);
  }

  Future<void> _removePeer(String peerId) async {
    await _peers[peerId]?.close();
    _peers.remove(peerId);
    await _remoteRenderers[peerId]?.dispose();
    _remoteRenderers.remove(peerId);
    if (mounted) setState(() {});
  }

  void _wsSend(Map<String, dynamic> msg) {
    _wsChannel?.sink.add(jsonEncode(msg));
  }

  void _toggleMic() {
    if (_localStream == null) return;
    final audioTracks = _localStream!.getAudioTracks();
    for (final track in audioTracks) {
      track.enabled = _micMuted; // toggle: if muted, enable; if enabled, mute
    }
    setState(() => _micMuted = !_micMuted);
  }

  void _toggleCamera() {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    for (final track in videoTracks) {
      track.enabled = _cameraOff; // toggle
    }
    setState(() => _cameraOff = !_cameraOff);
  }

  Future<void> _endCall() async {
    for (final peerId in List<String>.from(_peers.keys)) {
      await _removePeer(peerId);
    }
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
    await _wsSub?.cancel();
    await _wsChannel?.sink.close();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    for (final pc in _peers.values) {
      pc.close();
    }
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remoteEntries = _remoteRenderers.entries.toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Remote video(s) ─────────────────────────────────────────────────
          if (remoteEntries.isEmpty)
            // Waiting state
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off, color: Color(0xFF374151), size: 64),
                  const SizedBox(height: 16),
                  Text(
                    _connected ? 'Waiting for peers...' : 'Connecting...',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
                  ),
                ],
              ),
            )
          else if (remoteEntries.length == 1)
            // Single remote — full screen
            SizedBox.expand(
              child: RTCVideoView(remoteEntries.first.value, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            )
          else
            // Multiple remotes — grid
            GridView.count(
              crossAxisCount: 2,
              children: remoteEntries.map((e) => RTCVideoView(
                e.value,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )).toList(),
            ),

          // ── Local video (top-right PIP) ─────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 100,
                height: 140,
                child: _cameraOff
                    ? Container(
                        color: const Color(0xFF111827),
                        child: const Icon(Icons.videocam_off, color: Color(0xFF6B7280), size: 32),
                      )
                    : RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
              ),
            ),
          ),

          // ── Header ──────────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 120, // leave room for local PIP
                bottom: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.roomTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _peerCount == 0
                        ? 'Waiting for peers...'
                        : 'Connected with $_peerCount peer${_peerCount == 1 ? '' : 's'}',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // ── Controls bar ────────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: 20,
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 24,
                right: 24,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute mic
                  _CallButton(
                    icon: _micMuted ? Icons.mic_off : Icons.mic,
                    label: _micMuted ? 'Unmute' : 'Mute',
                    active: !_micMuted,
                    onTap: _toggleMic,
                  ),
                  // End call (red, center)
                  _CallButton(
                    icon: Icons.call_end,
                    label: 'End',
                    active: false,
                    isEnd: true,
                    onTap: _endCall,
                  ),
                  // Toggle camera
                  _CallButton(
                    icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                    label: _cameraOff ? 'Cam Off' : 'Camera',
                    active: !_cameraOff,
                    onTap: _toggleCamera,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Call control button
// ─────────────────────────────────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool isEnd;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.isEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (isEnd) {
      bg = const Color(0xFFDC2626);
    } else if (active) {
      bg = const Color(0xFF374151);
    } else {
      bg = const Color(0xFF1F2937);
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isEnd ? 64 : 54,
            height: isEnd ? 64 : 54,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: active || isEnd ? Colors.white : const Color(0xFF9CA3AF),
              size: isEnd ? 28 : 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
