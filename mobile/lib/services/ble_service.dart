import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// DRD custom GATT service UUIDs (128-bit, "mrd\0" marker)
const _kServiceUuid = '6d726400-0000-1000-8000-000000000001';
const _kRxCharUuid  = '6d726401-0000-1000-8000-000000000001'; // central→peripheral
const _kTxCharUuid  = '6d726402-0000-1000-8000-000000000001'; // peripheral→central notify
const _kNamePrefix  = 'DRD-';

// Platform channel for BLE advertising (Android only; FlutterBluePlus is central-only)
const _kBleChannel = MethodChannel('drd.ops/ble_advertiser');

const _kScanOn    = Duration(seconds: 12);
const _kScanPause = Duration(seconds: 4);
const _kConnTimeout = Duration(seconds: 8);

// ── Peer ─────────────────────────────────────────────────────────────────────

class BlePeer {
  final String deviceId;
  String name;
  int rssi;
  bool connected;
  bool isDrd;
  DateTime lastSeen;

  BlePeer({
    required this.deviceId,
    required this.name,
    required this.rssi,
    this.connected = false,
    this.isDrd = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();
}

// ── Callbacks ─────────────────────────────────────────────────────────────────

typedef BleMsgCallback  = void Function(String deviceId, Map<String, dynamic> json);
typedef BlePeerCallback = void Function(BlePeer peer);

// ── BleService ────────────────────────────────────────────────────────────────

class BleService {
  BleService._();
  static final BleService instance = BleService._();

  bool _running = false;
  bool get running => _running;
  bool _adapterOn = false;
  bool get adapterOn => _adapterOn;

  final Map<String, BlePeer> _seen       = {};
  final Map<String, BluetoothDevice> _gatt = {};
  final Set<String> _connecting           = {};
  final Map<String, StringBuffer> _rxBuf  = {};

  Timer? _scanCycle;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  final List<BleMsgCallback>  _msgListeners   = [];
  final List<BlePeerCallback> _peerListeners  = [];
  final List<VoidCallback>    _stateListeners = [];

  List<BlePeer> get allPeers  => _seen.values.toList();
  List<BlePeer> get drdPeers  => _seen.values.where((p) => p.isDrd).toList();
  int get nearbyCount         => _seen.length;
  int get drdCount            => _seen.values.where((p) => p.isDrd).length;
  int get connectedCount      => _gatt.length;

  void addMessageListener(BleMsgCallback cb)    => _msgListeners.add(cb);
  void removeMessageListener(BleMsgCallback cb) => _msgListeners.remove(cb);
  void addPeerListener(BlePeerCallback cb)      => _peerListeners.add(cb);
  void removePeerListener(BlePeerCallback cb)   => _peerListeners.remove(cb);
  void addStateListener(VoidCallback cb)        => _stateListeners.add(cb);
  void removeStateListener(VoidCallback cb)     => _stateListeners.remove(cb);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start({String? nodeName}) async {
    if (_running) return;

    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      _adapterOn = (s == BluetoothAdapterState.on);
      if (_adapterOn && _running) {
        _startScanCycle();
        _startAdvertising(nodeName: nodeName);
      }
      _notifyState();
    });

    final state = FlutterBluePlus.adapterStateNow;
    _adapterOn = (state == BluetoothAdapterState.on);
    _running = true;
    _notifyState();

    if (_adapterOn) {
      _startScanCycle();
      await _startAdvertising(nodeName: nodeName);
    }

    debugPrint('[BLE] Started — adapter=${_adapterOn ? "ON" : "OFF"}');
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    _adapterSub?.cancel();
    _adapterSub = null;
    _scanCycle?.cancel();
    _scanCycle = null;
    _scanSub?.cancel();
    _scanSub = null;

    try { await FlutterBluePlus.stopScan(); } catch (_) {}
    await _stopAdvertising();

    for (final dev in List<BluetoothDevice>.from(_gatt.values)) {
      try { await dev.disconnect(); } catch (_) {}
    }
    _gatt.clear();
    _seen.clear();
    _connecting.clear();
    _rxBuf.clear();
    _notifyState();
    debugPrint('[BLE] Stopped');
  }

  // ── BLE Advertising via platform channel ──────────────────────────────────
  // flutter_blue_plus 1.36.x is central-only; advertising requires a native call.
  // The Android side is handled by DrdBleAdvertiserPlugin (see MainActivity.kt).

  Future<void> _startAdvertising({String? nodeName}) async {
    try {
      final name = nodeName != null ? '$_kNamePrefix$nodeName' : '${_kNamePrefix}Node';
      await _kBleChannel.invokeMethod('startAdvertising', {
        'localName': name,
        'serviceUuid': _kServiceUuid,
      });
      debugPrint('[BLE] Advertising as "$name"');
    } catch (e) {
      // Advertising is best-effort — scan still works without it
      debugPrint('[BLE] Advertising unavailable: $e');
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await _kBleChannel.invokeMethod('stopAdvertising');
    } catch (_) {}
  }

  // ── Scanning ──────────────────────────────────────────────────────────────

  void _startScanCycle() {
    _scanCycle?.cancel();
    _runScan();
    _scanCycle = Timer.periodic(_kScanOn + _kScanPause, (_) {
      if (_running && _adapterOn) _runScan();
    });
  }

  Future<void> _runScan() async {
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    } catch (_) {}

    _scanSub?.cancel();

    try {
      await FlutterBluePlus.startScan(timeout: _kScanOn);
      _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
      debugPrint('[BLE] Scan started');
    } catch (e) {
      debugPrint('[BLE] Scan error: $e');
    }
  }

  void _onScanResults(List<ScanResult> results) {
    bool changed = false;

    for (final r in results) {
      final id = r.device.remoteId.str;

      // Prefer advertisementData advName, fall back to platformName
      final name = r.advertisementData.advName.isNotEmpty
          ? r.advertisementData.advName
          : (r.device.platformName.isNotEmpty ? r.device.platformName : id.substring(0, 8));

      final isDrd = name.startsWith(_kNamePrefix) ||
          r.advertisementData.serviceUuids.any(
            (g) => g.str128.toLowerCase() == _kServiceUuid,
          );

      final existing = _seen[id];
      if (existing == null) {
        _seen[id] = BlePeer(
          deviceId: id, name: name, rssi: r.rssi, isDrd: isDrd,
        );
        changed = true;
        debugPrint('[BLE] ${isDrd ? "DRD" : "BLE"} device: $name ($id) rssi=${r.rssi}');
      } else {
        existing
          ..name    = name
          ..rssi    = r.rssi
          ..isDrd   = isDrd
          ..lastSeen = DateTime.now();
      }

      final peer = _seen[id]!;
      for (final cb in _peerListeners) { cb(peer); }

      if (isDrd) _connectGatt(r.device);
    }

    // Prune peers silent for > 60 s
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    final stale = _seen.entries
        .where((e) => e.value.lastSeen.isBefore(cutoff))
        .map((e) => e.key)
        .toList();
    for (final k in stale) {
      _seen.remove(k);
      changed = true;
    }

    if (changed) _notifyState();
  }

  // ── GATT ─────────────────────────────────────────────────────────────────

  Future<void> _connectGatt(BluetoothDevice device) async {
    final id = device.remoteId.str;
    if (_gatt.containsKey(id) || _connecting.contains(id)) return;
    _connecting.add(id);

    try {
      await device.connect(timeout: _kConnTimeout, autoConnect: false);
      await device.requestMtu(512);

      _gatt[id] = device;
      final peer = _seen[id];
      if (peer != null) peer.connected = true;
      _notifyState();
      debugPrint('[BLE] GATT connected: $id');

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _gatt.remove(id);
          _rxBuf.remove(id);
          final p = _seen[id];
          if (p != null) p.connected = false;
          _notifyState();
          debugPrint('[BLE] GATT disconnected: $id');
        }
      });

      await _subscribeNotify(device);
    } catch (e) {
      debugPrint('[BLE] GATT connect failed $id: $e');
    } finally {
      _connecting.remove(id);
    }
  }

  Future<void> _subscribeNotify(BluetoothDevice device) async {
    final id = device.remoteId.str;
    try {
      final services = await device.discoverServices();
      final svc = services.where(
        (s) => s.serviceUuid.str128.toLowerCase() == _kServiceUuid,
      ).firstOrNull;

      if (svc == null) {
        debugPrint('[BLE] No DRD GATT service on $id');
        return;
      }

      final txChar = svc.characteristics.where(
        (c) => c.characteristicUuid.str128.toLowerCase() == _kTxCharUuid &&
               c.properties.notify,
      ).firstOrNull;

      if (txChar != null) {
        await txChar.setNotifyValue(true);
        txChar.lastValueStream.listen((data) => _onRxBytes(id, data));
        debugPrint('[BLE] Subscribed to DRD TX notifications on $id');
      }
    } catch (e) {
      debugPrint('[BLE] GATT discovery error $id: $e');
    }
  }

  void _onRxBytes(String deviceId, List<int> data) {
    if (data.isEmpty) return;
    _rxBuf.putIfAbsent(deviceId, StringBuffer.new);
    _rxBuf[deviceId]!.write(utf8.decode(data, allowMalformed: true));

    final raw   = _rxBuf[deviceId]!.toString();
    final parts = raw.split('\n');
    _rxBuf[deviceId]!
      ..clear()
      ..write(parts.last); // incomplete tail

    for (final line in parts.sublist(0, parts.length - 1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        for (final cb in _msgListeners) { cb(deviceId, json); }
      } catch (_) {}
    }
  }

  // ── Send ─────────────────────────────────────────────────────────────────

  Future<void> sendTo(String deviceId, Map<String, dynamic> json) async {
    final device = _gatt[deviceId];
    if (device == null) return;
    try {
      final services = await device.discoverServices();
      final svc = services.where(
        (s) => s.serviceUuid.str128.toLowerCase() == _kServiceUuid,
      ).firstOrNull;
      if (svc == null) return;

      final rxChar = svc.characteristics.where(
        (c) => c.characteristicUuid.str128.toLowerCase() == _kRxCharUuid,
      ).firstOrNull;
      if (rxChar == null) return;

      final bytes = utf8.encode('${jsonEncode(json)}\n');
      const chunk = 512;
      for (int i = 0; i < bytes.length; i += chunk) {
        final end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
        await rxChar.write(
          bytes.sublist(i, end),
          withoutResponse: rxChar.properties.writeWithoutResponse,
        );
      }
    } catch (e) {
      debugPrint('[BLE] Send error $deviceId: $e');
    }
  }

  Future<void> broadcast(Map<String, dynamic> json) async {
    for (final id in List<String>.from(_gatt.keys)) {
      await sendTo(id, json);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _notifyState() {
    for (final cb in _stateListeners) { cb(); }
  }
}
