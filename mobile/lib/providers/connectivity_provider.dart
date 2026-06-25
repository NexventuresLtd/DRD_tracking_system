import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityProvider extends ChangeNotifier {
  bool _online = true;
  bool get online => _online;

  StreamSubscription<List<ConnectivityResult>>? _sub;

  ConnectivityProvider() {
    _init();
  }

  Future<void> _init() async {
    final initial = await Connectivity().checkConnectivity();
    _online = _isOnline(initial);

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _online;
      _online = _isOnline(results);
      if (_online != wasOnline) notifyListeners();
    });
  }

  bool _isOnline(List<ConnectivityResult> r) =>
      r.isNotEmpty && !r.every((v) => v == ConnectivityResult.none);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
