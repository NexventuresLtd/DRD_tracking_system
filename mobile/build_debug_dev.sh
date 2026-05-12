#!/bin/bash
# Build debug development APK (connects to local development server)
# Usage: ./build_debug_dev.sh

echo "Building Flutter debug APK (Development - Local Server)..."
echo "Environment: development"
echo "API URL: http://192.168.1.69:8000/api/v1"
echo ""

flutter build apk \
  --debug \
  --dart-define="FLAVOR=development" \
  -t lib/main.dart

echo ""
echo "APK built successfully!"
echo ""
echo "APK location: build/app/outputs/flutter-apk/app-debug.apk"
echo ""
echo "To install on USB-connected device:"
echo "  flutter install -d <device_id>"
echo ""
echo "To install locally (without USB):"
echo "  adb install build/app/outputs/flutter-apk/app-debug.apk"
