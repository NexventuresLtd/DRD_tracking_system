import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/mesh_service.dart';
import '../services/ble_service.dart';

class MeshProvider extends ChangeNotifier {
  bool _active = false;
  int _peerCount = 0;
  int _msgRelayed = 0;
  int _bleNearby = 0;
  int _bleDrd = 0;
  int _bleConnected = 0;
  bool _bleAdapterOn = false;
  final List<String> _log = [];

  bool get active         => _active;
  int  get peerCount      => _peerCount;
  int  get msgRelayed     => _msgRelayed;
  int  get bleNearby      => _bleNearby;
  int  get bleDrd         => _bleDrd;
  int  get bleConnected   => _bleConnected;
  bool get bleAdapterOn   => _bleAdapterOn;
  bool get anyPeer        => _peerCount > 0 || _bleDrd > 0;

  List<String>   get log      => List.unmodifiable(_log);
  List<MeshPeer> get peers    => MeshService.instance.peers;
  List<BlePeer>  get blePeers => BleService.instance.allPeers;

  Future<void> flushToServer() => MeshService.instance.flushToServer();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _refreshTimer;

  MeshProvider() {
    MeshService.instance.addListener(_onMeshMessage);
    BleService.instance.addStateListener(_onBleState);
    BleService.instance.addPeerListener(_onBlePeer);
  }

  Future<void> start({String? userName}) async {
    await MeshService.instance.start(userName: userName);
    _active = true;
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _connSub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    _addLog('Mesh + BLE started');
    notifyListeners();
  }

  Future<void> stop() async {
    _refreshTimer?.cancel();
    _connSub?.cancel();
    await MeshService.instance.stop();
    _active = false;
    _peerCount = 0;
    _bleNearby = 0;
    _bleDrd = 0;
    _bleConnected = 0;
    _addLog('Mesh stopped');
    notifyListeners();
  }

  Future<void> sendLocation(Map<String, dynamic> locationData) async {
    await MeshService.instance.broadcast('location', locationData);
    // Also send over BLE to connected DRD peers
    await BleService.instance.broadcast({'type': 'location', 'payload': locationData});
    _msgRelayed++;
    _addLog('Location broadcast — ${_peerCount}W ${_bleConnected}B peer(s)');
    notifyListeners();
  }

  Future<void> sendMessage(String content, String channel, {String? toNodeId}) async {
    final payload = {'content': content, 'channel': channel};
    if (toNodeId != null) {
      await MeshService.instance.sendTo(toNodeId, 'message', payload);
    } else {
      await MeshService.instance.broadcast('message', payload);
      await BleService.instance.broadcast({'type': 'message', 'payload': payload});
    }
    _msgRelayed++;
    _addLog('Message sent via mesh');
    notifyListeners();
  }

  Future<void> sendPoi(Map<String, dynamic> poiData) async {
    await MeshService.instance.broadcast('poi', poiData);
    await BleService.instance.broadcast({'type': 'poi', 'payload': poiData});
    _msgRelayed++;
    _addLog('POI broadcast to mesh');
    notifyListeners();
  }

  void _onMeshMessage(MeshMessage msg) {
    if (msg.type == 'announce') {
      _addLog('WiFi peer: ${msg.payload['name'] ?? msg.from.substring(0, 8)}');
    } else {
      _msgRelayed++;
      _addLog('RX(WiFi) ${msg.type} from ${msg.from.substring(0, 6)}…');
    }
    notifyListeners();
  }

  void _onBleState() {
    _bleAdapterOn = BleService.instance.adapterOn;
    _bleNearby    = BleService.instance.nearbyCount;
    _bleDrd       = BleService.instance.drdCount;
    _bleConnected = BleService.instance.connectedCount;
    notifyListeners();
  }

  void _onBlePeer(BlePeer peer) {
    if (peer.isDrd) {
      _addLog('BLE ${peer.connected ? "linked" : "found"}: ${peer.name}');
    }
    notifyListeners();
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
    if (online) MeshService.instance.flushToServer();
  }

  void _refresh() {
    final newCount = MeshService.instance.connectedCount;
    if (newCount != _peerCount) {
      _peerCount = newCount;
      if (newCount > 0) _addLog('$_peerCount WiFi peer(s) linked');
      notifyListeners();
    }
  }

  void _addLog(String entry) {
    final ts = DateTime.now();
    final hms = '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    _log.insert(0, '[$hms] $entry');
    if (_log.length > 100) _log.removeLast();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _connSub?.cancel();
    MeshService.instance.removeListener(_onMeshMessage);
    BleService.instance.removeStateListener(_onBleState);
    BleService.instance.removePeerListener(_onBlePeer);
    super.dispose();
  }
}
