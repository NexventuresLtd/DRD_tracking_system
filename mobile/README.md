# DRD Tracking Mobile App

This folder contains the Flutter mobile application for the DRD Tracking System.

The mobile app supports live location tracking, mapping, event monitoring, offline data caching, push notifications, and camera/media workflows.

## Technologies

- Flutter / Dart
- Provider state management
- flutter_map and latlong2
- geolocator / geocoding
- web_socket_channel
- connectivity_plus / battery_plus
- flutter_webrtc
- shared_preferences / sqflite

## Getting Started

Install dependencies:

```bash
cd mobile
flutter pub get
```

Run on a connected device or emulator:

```bash
cd mobile
flutter run
```

Build a debug APK for local testing:

```bash
cd mobile
./build_debug_dev.sh
```

Build a production release APK:

```bash
cd mobile
./build_release_prod.sh
```

## Environment

The mobile app supports environment flavors and custom API host configuration using Dart defines.

Example:

```bash
flutter run --dart-define=FLAVOR=development
flutter run --dart-define=FLAVOR=production
```

## Folder structure

- `lib/` - main application code
- `lib/models/` - data models
- `lib/providers/` - app state providers
- `lib/screens/` - app screens
- `lib/services/` - network, connectivity, and backend integration
- `lib/widgets/` - reusable UI components
- `assets/` - fonts, images, and map assets

## Notes

See the root `README.md` for repository-level setup instructions and server integration.
