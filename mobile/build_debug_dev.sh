#!/bin/bash
# Build debug development APK (connects to local development server)
# Usage: ./build_debug_dev.sh [--run]

echo "Building Flutter debug APK (Development - Local Server)..."
echo "Environment: development"
echo "API URL: http://192.168.1.73:8000/api/v1"
echo ""

if [[ "$1" == "--run" ]]; then
  flutter run \
    --flavor development \
    --dart-define="FLAVOR=development" \
    -t lib/main.dart
else
  flutter build apk \
    --debug \
    --flavor development \
    --dart-define="FLAVOR=development" \
    -t lib/main.dart

  echo ""
  echo "APK built successfully!"
  echo ""
  echo "APK location: build/app/outputs/flutter-apk/app-development-debug.apk"
  echo ""
  echo "To install on USB-connected device:"
  echo "  adb install -r build/app/outputs/flutter-apk/app-development-debug.apk"
  echo ""
  echo "To run directly on connected device:"
  echo "  ./build_debug_dev.sh --run"
fi
