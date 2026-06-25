import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionInfo {
  final Permission permission;
  final String title;
  final String reason;
  final bool critical;

  const PermissionInfo({
    required this.permission,
    required this.title,
    required this.reason,
    this.critical = true,
  });
}

class PermissionService {
  static final PermissionService instance = PermissionService._();
  PermissionService._();

  List<PermissionInfo> get all => [
        // ── Core field ops ────────────────────────────────────────────────
        const PermissionInfo(
          permission: Permission.locationAlways,
          title: 'Location (Always On)',
          reason: 'Tracks your field position in real-time, even when the screen is off or the app is in the background. Required for live map and mesh networking.',
        ),
        const PermissionInfo(
          permission: Permission.camera,
          title: 'Camera',
          reason: 'Captures evidence photos, scans QR enrolment codes, and enables live video feeds.',
        ),
        const PermissionInfo(
          permission: Permission.microphone,
          title: 'Microphone',
          reason: 'Used for voice comms and live video sessions with your team.',
        ),
        PermissionInfo(
          permission: Platform.isAndroid ? Permission.notification : Permission.notification,
          title: 'Notifications',
          reason: 'Delivers SOS alerts, mission updates, and command messages in real-time.',
        ),
        PermissionInfo(
          permission: Platform.isAndroid ? Permission.photos : Permission.photos,
          title: 'Photos / Storage',
          reason: 'Saves evidence photos and reads media when attaching files to field reports.',
        ),

        // ── Bluetooth & Nearby (full access) ─────────────────────────────
        // BLUETOOTH_SCAN — find nearby DRD nodes via BLE
        const PermissionInfo(
          permission: Permission.bluetoothScan,
          title: 'Bluetooth Scan',
          reason: 'Continuously scans for nearby DRD field devices so the mesh network can form even when internet is down. Required for offline mode.',
        ),
        // BLUETOOTH_CONNECT — open GATT connections for data relay
        const PermissionInfo(
          permission: Permission.bluetoothConnect,
          title: 'Bluetooth Connect',
          reason: 'Opens direct connections to nearby DRD devices to relay location, messages, and alerts over the BLE mesh.',
        ),
        // BLUETOOTH_ADVERTISE — broadcast this device so others can find it
        const PermissionInfo(
          permission: Permission.bluetoothAdvertise,
          title: 'Bluetooth Advertise',
          reason: 'Broadcasts this device as a DRD mesh node so other field units can discover and connect to it automatically.',
        ),
        // NEARBY_WIFI_DEVICES (Android 13+) — WiFi peer discovery for mesh
        if (Platform.isAndroid)
          const PermissionInfo(
            permission: Permission.nearbyWifiDevices,
            title: 'Nearby Wi-Fi Devices',
            reason: 'Allows the app to discover nearby devices on the local network for the WiFi mesh layer — used alongside Bluetooth for multi-hop relay.',
          ),
      ];

  Future<PermissionStatus> statusOf(Permission p) => p.status;

  Future<Map<Permission, PermissionStatus>> requestAll() async {
    // iOS: must request locationWhenInUse before locationAlways
    if (Platform.isIOS) {
      await Permission.locationWhenInUse.request();
    }

    // Android: request location first — older devices need it for BLE scanning
    if (Platform.isAndroid) {
      await Permission.locationAlways.request();
    }

    // Request everything else (Bluetooth permissions are now included)
    final toRequest = all.map((i) => i.permission).toList();
    return toRequest.request();
  }

  Future<PermissionStatus> requestOne(Permission p) async {
    if (p == Permission.locationAlways) {
      if (Platform.isIOS) await Permission.locationWhenInUse.request();
      return p.request();
    }
    // For BT permissions: ensure location is granted first on older Android
    if (p == Permission.bluetoothScan && Platform.isAndroid) {
      final loc = await Permission.locationWhenInUse.status;
      if (!loc.isGranted) await Permission.locationWhenInUse.request();
    }
    return p.request();
  }

  Future<bool> allCriticalGranted() async {
    for (final info in all.where((i) => i.critical)) {
      final s = await info.permission.status;
      if (!s.isGranted && !s.isLimited) return false;
    }
    return true;
  }

  Future<void> openSettings() => openAppSettings();
}
