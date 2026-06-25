import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';

// Ports — must be open in any firewall on local LAN
const int _tcpPort = 5666;
const int _udpPort = 5667;
const Duration _discoveryInterval = Duration(seconds: 5);

// ── Message envelope (Reticulum-compatible routing) ──────────────────────────

class MeshMessage {
  final String msgId;
  final String from;
  final String? to;
  final String type;
  final Map<String, dynamic> payload;
  int ttl;
  final List<String> hops;
  final int timestamp;

  MeshMessage({
    required this.msgId,
    required this.from,
    this.to,
    required this.type,
    required this.payload,
    this.ttl = 7,
    List<String>? hops,
    int? timestamp,
  })  : hops = hops ?? [],
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory MeshMessage.fromJson(Map<String, dynamic> j) => MeshMessage(
        msgId: j['msg_id'] as String,
        from: j['from'] as String,
        to: j['to'] as String?,
        type: j['type'] as String,
        payload: (j['payload'] as Map<String, dynamic>?) ?? {},
        ttl: (j['ttl'] as int?) ?? 0,
        hops: List<String>.from(j['hops'] as List? ?? []),
        timestamp: (j['timestamp'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'msg_id': msgId,
        'from': from,
        'to': to,
        'type': type,
        'payload': payload,
        'ttl': ttl,
        'hops': hops,
        'timestamp': timestamp,
      };

  String encode() => jsonEncode(toJson());
}

// ── Peer entry ────────────────────────────────────────────────────────────────

class MeshPeer {
  final String endpointId; // "address:port"
  String endpointName;
  String nodeId;
  DateTime lastSeen;
  bool connected;
  Socket? socket;

  MeshPeer({
    required this.endpointId,
    required this.endpointName,
    required this.nodeId,
    DateTime? lastSeen,
    this.connected = false,
    this.socket,
  }) : lastSeen = lastSeen ?? DateTime.now();
}

// ── MeshService singleton ─────────────────────────────────────────────────────

typedef MeshMessageCallback = void Function(MeshMessage msg);

class MeshService {
  MeshService._();
  static final MeshService instance = MeshService._();

  String _nodeId = '';
  String _deviceName = 'DRD-Unknown';
  bool _running = false;

  ServerSocket? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;

  final Map<String, MeshPeer> _peers = {};
  final Set<String> _connecting = {}; // keys currently being connected
  final Set<String> _seenMsgIds = {};
  final List<String> _seenOrder = [];
  static const int _maxSeenIds = 1000;

  final List<MeshMessage> _offlineQueue = [];
  final List<MeshMessageCallback> _callbacks = [];

  bool get running => _running;
  List<MeshPeer> get peers => _peers.values.toList();
  int get connectedCount => _peers.values.where((p) => p.connected).length;
  List<MeshMessage> get offlineQueue => List.unmodifiable(_offlineQueue);

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> start({String? userName}) async {
    if (_running) return;
    await _deriveNodeId();
    _deviceName = userName != null ? 'DRD-$userName' : 'DRD-${_nodeId.substring(0, 6)}';
    _running = true;

    // TCP server — accept incoming connections from peers
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _tcpPort, shared: true);
      _server!.listen(_onNewConnection, onError: (e) => debugPrint('[Mesh] Server error: $e'));
      debugPrint('[Mesh] TCP server on port $_tcpPort');
    } catch (e) {
      debugPrint('[Mesh] Failed to bind TCP: $e');
    }

    // UDP socket — broadcast presence and receive peer announcements
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpPort);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen(_onUdpEvent);
      debugPrint('[Mesh] UDP listening on port $_udpPort');
    } catch (e) {
      debugPrint('[Mesh] Failed to bind UDP: $e');
    }

    // Broadcast our presence periodically
    _broadcastTimer = Timer.periodic(_discoveryInterval, (_) => _broadcastPresence());
    _broadcastPresence();

    // BLE transport — scan + advertise for offline peer discovery
    final shortName = _deviceName.replaceFirst('DRD-', '');
    BleService.instance.addMessageListener(_onBleMessage);
    BleService.instance.addStateListener(_onBleState);
    await BleService.instance.start(nodeName: shortName);

    debugPrint('[Mesh] Started — node=${_nodeId.substring(0, 8)} name=$_deviceName');
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    for (final peer in _peers.values) {
      try { peer.socket?.destroy(); } catch (_) {}
    }
    _peers.clear();
    _connecting.clear();
    try { await _server?.close(); } catch (_) {}
    _server = null;
    _udpSocket?.close();
    _udpSocket = null;

    BleService.instance.removeMessageListener(_onBleMessage);
    BleService.instance.removeStateListener(_onBleState);
    await BleService.instance.stop();

    debugPrint('[Mesh] Stopped');
  }

  void addListener(MeshMessageCallback cb) => _callbacks.add(cb);
  void removeListener(MeshMessageCallback cb) => _callbacks.remove(cb);

  // ── BLE transport callbacks ───────────────────────────────────────────────

  void _onBleMessage(String deviceId, Map<String, dynamic> json) {
    try {
      final msg = MeshMessage.fromJson(json);
      _handleIncoming(msg, fromKey: 'ble:$deviceId');
    } catch (_) {}
  }

  void _onBleState() {
    // Triggers a peer-count refresh in MeshProvider via its own BLE listener.
    // Nothing to do here — BleService.instance exposes counts directly.
  }

  // ── UDP peer discovery ────────────────────────────────────────────────────

  void _broadcastPresence() {
    if (_udpSocket == null) return;
    final packet = utf8.encode(jsonEncode({
      'type': 'drd_announce',
      'node_id': _nodeId,
      'name': _deviceName,
      'tcp_port': _tcpPort,
    }));
    try {
      _udpSocket!.send(packet, InternetAddress('255.255.255.255'), _udpPort);
    } catch (_) {}
  }

  void _onUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _udpSocket?.receive();
    if (dg == null) return;
    try {
      final data = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (data['type'] != 'drd_announce') return;
      final nodeId = data['node_id'] as String? ?? '';
      if (nodeId == _nodeId) return; // ignore self
      final address = dg.address.address;
      final port = (data['tcp_port'] as int?) ?? _tcpPort;
      final name = data['name'] as String? ?? nodeId;
      _connectToPeerIfNeeded(address, port, nodeId, name);
    } catch (_) {}
  }

  // ── TCP connection management ─────────────────────────────────────────────

  Future<void> _connectToPeerIfNeeded(String address, int port, String nodeId, String name) async {
    final key = '$address:$port';
    if (_peers.containsKey(key)) {
      _peers[key]!.lastSeen = DateTime.now();
      return;
    }
    if (_connecting.contains(key)) return;
    _connecting.add(key);
    try {
      final socket = await Socket.connect(address, port, timeout: const Duration(seconds: 3));
      final peer = MeshPeer(
        endpointId: key,
        endpointName: name,
        nodeId: nodeId,
        connected: true,
        socket: socket,
      );
      _peers[key] = peer;
      _attachSocketListeners(socket, key);
      _sendAnnounce(key);
      debugPrint('[Mesh] Connected to $key ($name)');
    } catch (e) {
      debugPrint('[Mesh] Cannot connect to $key: $e');
    } finally {
      _connecting.remove(key);
    }
  }

  void _onNewConnection(Socket socket) {
    final key = '${socket.remoteAddress.address}:${socket.remotePort}';
    debugPrint('[Mesh] Incoming from $key');
    _peers[key] = MeshPeer(
      endpointId: key,
      endpointName: key,
      nodeId: _endpointToNodeId(key),
      connected: true,
      socket: socket,
    );
    _attachSocketListeners(socket, key);
  }

  void _attachSocketListeners(Socket socket, String key) {
    final buf = StringBuffer();
    socket.listen(
      (data) {
        final chunk = utf8.decode(data, allowMalformed: true);
        buf.write(chunk);
        final raw = buf.toString();
        final parts = raw.split('\n');
        buf.clear();
        if (parts.length > 1) {
          buf.write(parts.last); // incomplete last line stays in buffer
          for (final line in parts.sublist(0, parts.length - 1)) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            try {
              final msg = MeshMessage.fromJson(
                  jsonDecode(trimmed) as Map<String, dynamic>);
              if (msg.type == 'announce') {
                final nid = msg.payload['node_id'] as String? ?? msg.from;
                final nm = msg.payload['name'] as String? ?? nid;
                _peers.update(key,
                  (p) => p
                    ..nodeId = nid
                    ..endpointName = nm
                    ..connected = true
                    ..lastSeen = DateTime.now(),
                  ifAbsent: () => MeshPeer(
                    endpointId: key, endpointName: nm, nodeId: nid,
                    connected: true, socket: socket));
              } else {
                _handleIncoming(msg, fromKey: key);
              }
            } catch (e) {
              debugPrint('[Mesh] Parse error: $e');
            }
          }
        }
      },
      onDone: () => _peerGone(key),
      onError: (_) => _peerGone(key),
      cancelOnError: true,
    );
  }

  void _peerGone(String key) {
    debugPrint('[Mesh] Peer gone: $key');
    _peers[key]?.connected = false;
    _peers.remove(key);
  }

  // ── Reticulum flood routing ───────────────────────────────────────────────

  void _handleIncoming(MeshMessage msg, {required String fromKey}) {
    if (_seenMsgIds.contains(msg.msgId)) return;
    _markSeen(msg.msgId);
    debugPrint('[Mesh] RX type=${msg.type} from=${msg.from.substring(0, 8)} ttl=${msg.ttl}');

    if (msg.to == null || msg.to == _nodeId) {
      for (final cb in _callbacks) { cb(msg); }
      if (msg.type != 'announce') _queueForServer(msg);
    }

    if (msg.ttl > 0) {
      final fwd = MeshMessage(
        msgId: msg.msgId,
        from: msg.from,
        to: msg.to,
        type: msg.type,
        payload: msg.payload,
        ttl: msg.ttl - 1,
        hops: [...msg.hops, _nodeId],
        timestamp: msg.timestamp,
      );
      final encoded = '${fwd.encode()}\n';
      final bytes = utf8.encode(encoded);
      for (final peer in _peers.values) {
        if (!peer.connected || peer.endpointId == fromKey) continue;
        if (msg.hops.contains(peer.nodeId)) continue;
        _rawSend(peer, bytes);
      }
    }
  }

  // ── Send helpers ──────────────────────────────────────────────────────────

  Future<void> broadcast(String type, Map<String, dynamic> payload) async {
    final msg = MeshMessage(msgId: _newId(), from: _nodeId, to: null,
        type: type, payload: payload);
    _markSeen(msg.msgId);
    final bytes = utf8.encode('${msg.encode()}\n');
    for (final peer in _peers.values.where((p) => p.connected)) {
      _rawSend(peer, bytes);
    }
  }

  Future<void> sendTo(String targetNodeId, String type, Map<String, dynamic> payload) async {
    final msg = MeshMessage(msgId: _newId(), from: _nodeId, to: targetNodeId,
        type: type, payload: payload);
    _markSeen(msg.msgId);
    final bytes = utf8.encode('${msg.encode()}\n');
    final direct = _peers.values
        .where((p) => p.connected && p.nodeId == targetNodeId)
        .firstOrNull;
    if (direct != null) {
      _rawSend(direct, bytes);
    } else {
      for (final peer in _peers.values.where((p) => p.connected)) {
        _rawSend(peer, bytes);
      }
    }
  }

  void _sendAnnounce(String toKey) {
    final peer = _peers[toKey];
    if (peer == null) return;
    final msg = MeshMessage(
      msgId: _newId(), from: _nodeId, to: null, type: 'announce',
      payload: {'node_id': _nodeId, 'name': _deviceName}, ttl: 0,
    );
    _markSeen(msg.msgId);
    _rawSend(peer, utf8.encode('${msg.encode()}\n'));
  }

  void _rawSend(MeshPeer peer, List<int> bytes) {
    try {
      peer.socket?.add(bytes);
    } catch (_) {
      _peerGone(peer.endpointId);
    }
  }

  // ── Offline queue ─────────────────────────────────────────────────────────

  void _queueForServer(MeshMessage msg) {
    _offlineQueue.add(msg);
    if (_offlineQueue.length > 500) _offlineQueue.removeAt(0);
  }

  Future<void> flushToServer() async {
    if (_offlineQueue.isEmpty) return;
    final batch = List<MeshMessage>.from(_offlineQueue);
    _offlineQueue.clear();

    final bridgeUrl = await _discoverBridge();
    if (bridgeUrl != null) {
      try {
        await _postToBridge(bridgeUrl, batch);
        debugPrint('[Mesh] Flushed ${batch.length} msg(s) to bridge at $bridgeUrl');
        return;
      } catch (e) {
        debugPrint('[Mesh] Bridge flush failed, using API: $e');
      }
    }

    final api = ApiService();
    for (final msg in batch) {
      try {
        await _syncMsgToServer(api, msg);
      } catch (_) {
        _offlineQueue.add(msg);
      }
    }
  }

  // ── Bridge discovery ──────────────────────────────────────────────────────

  String? _cachedBridgeUrl;
  DateTime? _lastBridgeCheck;
  static const int _bridgePort = 4344;
  static const Duration _bridgePingTimeout = Duration(seconds: 2);
  static const Duration _bridgeCacheTtl = Duration(minutes: 5);

  Future<String?> _discoverBridge() async {
    if (_cachedBridgeUrl != null && _lastBridgeCheck != null &&
        DateTime.now().difference(_lastBridgeCheck!) < _bridgeCacheTtl) {
      return _cachedBridgeUrl;
    }
    final localIp = await _getLocalIp();
    if (localIp == null) return null;
    final parts = localIp.split('.');
    if (parts.length != 4) return null;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    final candidates = [
      ...List.generate(10, (i) => '$subnet.${i + 1}'),
      ...List.generate(11, (i) => '$subnet.${i + 100}'),
    ];
    final client = HttpClient()..connectionTimeout = _bridgePingTimeout;
    for (final host in candidates) {
      try {
        final req = await client.getUrl(Uri.parse('http://$host:$_bridgePort/mesh/ping'));
        final res = await req.close().timeout(_bridgePingTimeout);
        if (res.statusCode == 200) {
          final body = await res.transform(const Utf8Decoder()).join();
          if (body.contains('drd-reticulum-bridge')) {
            _cachedBridgeUrl = 'http://$host:$_bridgePort';
            _lastBridgeCheck = DateTime.now();
            client.close();
            return _cachedBridgeUrl;
          }
        }
      } catch (_) {}
    }
    client.close();
    _cachedBridgeUrl = null;
    return null;
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!ip.startsWith('127.') && !ip.startsWith('169.254.')) return ip;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _postToBridge(String bridgeUrl, List<MeshMessage> msgs) async {
    final token = StorageService().accessToken ?? '';
    final body = utf8.encode(jsonEncode(msgs.map((m) => m.toJson()).toList()));
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$bridgeUrl/mesh/sync'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.add(body);
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('Bridge ${res.statusCode}');
    } finally {
      client.close();
    }
  }

  Future<void> _syncMsgToServer(ApiService api, MeshMessage msg) async {
    switch (msg.type) {
      case 'location':
        await api.post('/locations', msg.payload);
        break;
      case 'message':
        await api.post('/messages', msg.payload);
        break;
      case 'poi':
        await api.post('/pois', msg.payload);
        break;
    }
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  Future<void> _deriveNodeId() async {
    final stored = StorageService().getString('mesh_node_id');
    if (stored != null && stored.isNotEmpty) {
      _nodeId = stored;
      return;
    }
    final seed = List.generate(16, (_) => Random.secure().nextInt(256));
    final hash = sha256.convert(seed);
    _nodeId = hash.toString().substring(0, 32);
    await StorageService().setString('mesh_node_id', _nodeId);
  }

  String _endpointToNodeId(String endpointId) =>
      sha256.convert(utf8.encode(endpointId)).toString().substring(0, 32);

  String _newId() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _markSeen(String msgId) {
    if (_seenMsgIds.contains(msgId)) return;
    _seenMsgIds.add(msgId);
    _seenOrder.add(msgId);
    if (_seenOrder.length > _maxSeenIds) {
      _seenMsgIds.remove(_seenOrder.removeAt(0));
    }
  }
}
