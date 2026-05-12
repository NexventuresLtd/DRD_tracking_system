#!/bin/bash
# Build release APK (connects to production server)
# Usage: ./build_release_prod.sh

echo "Building Flutter release APK (Production)..."
echo "Environment: production"
echo "API URL: https://drd.nexventures.net/api/v1"
echo ""

flutter build apk \
  --release \
  --dart-define="FLAVOR=production" \
  -t lib/main.dart

echo ""
echo "APK built successfully!"
echo ""
echo "APK location: build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "To test locally before uploading:"
echo "  adb install -r build/app/outputs/flutter-apk/app-release.apk"
