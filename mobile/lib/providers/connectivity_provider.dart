import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/ble_service.dart';

enum NetMode {
  online,  // WiFi/mobile connected — full app
  bleOnly, // No internet but BLE bridge to laptop connected — chat/location/SOS only
  offline, // Nothing — mesh scanning screen
}

class ConnectivityProvider extends ChangeNotifier {
  bool _hasNetwork = true;
  bool _manualMesh = false;

  NetMode get mode {
    if (_manualMesh)  return NetMode.offline;
    if (_hasNetwork)  return NetMode.online;
    if (BleService.instance.bridgeConnected) return NetMode.bleOnly;
    return NetMode.offline;
  }

  bool get online        => mode == NetMode.online;
  bool get isBleOnly     => mode == NetMode.bleOnly;
  bool get isOffline     => mode == NetMode.offline;
  bool get manualMesh    => _manualMesh;

  // Legacy compat used in other providers
  bool get internetReachable => online;
  bool get isIsolated        => !online;

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  ConnectivityProvider() {
    _init();
  }

  Future<void> _init() async {
    final initial = await Connectivity().checkConnectivity();
    _hasNetwork = _hasNet(initial);

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final was = _hasNetwork;
      _hasNetwork = _hasNet(results);
      if (_hasNetwork != was) notifyListeners();
    });

    // Refresh when BLE state changes (bridge connect/disconnect)
    BleService.instance.addStateListener(_onBleState);
  }

  bool _hasNet(List<ConnectivityResult> r) => r.any((v) =>
      v == ConnectivityResult.wifi ||
      v == ConnectivityResult.mobile ||
      v == ConnectivityResult.ethernet);

  void _onBleState() => notifyListeners();

  void toggleManualMesh() {
    _manualMesh = !_manualMesh;
    notifyListeners();
  }

  Future<void> forceCheck() async {
    final results = await Connectivity().checkConnectivity();
    final was = _hasNetwork;
    _hasNetwork = _hasNet(results);
    if (_hasNetwork != was) notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    BleService.instance.removeStateListener(_onBleState);
    super.dispose();
  }
}
