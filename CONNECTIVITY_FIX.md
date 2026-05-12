# Mobile App Server Connectivity Issues - Resolution Guide

## Problem Summary

Your mobile app was failing to connect to the server when installed without USB (release/debug builds on other devices), but worked fine via USB install.

### Root Cause

**API URL Hardcoding Issue:**
- The app was hardcoded to connect to `https://drd.nexventures.net/api/v1`
- When developing locally, your server runs on `http://192.168.1.69:8000` or similar
- USB debugging works because the dev machine and mobile device share the same local network
- Non-USB installs fail because external devices can't reach a localhost/private IP address

**Network Topology Problem:**
```
✅ Development (USB):
  Dev Machine (192.168.1.69:8000) 
              ↕
         Same Local Network
              ↕
  Mobile Device (same network) → Can reach 192.168.1.69:8000

❌ Production (Non-USB):
  Mobile Device (external network) → Tries to reach drd.nexventures.net
                                   → But server not accessible at that domain
                                   → Connection fails
```

## Solution Implemented

### 1. Environment Configuration System

Created `lib/config/environment.dart` that supports three flavors:

| Flavor | API Base URL | Use Case |
|--------|-------------|----------|
| **development** | `http://192.168.1.69:8000/api/v1` | Local dev on same network |
| **staging** | `https://staging.drd.nexventures.net/api/v1` | Testing environment |
| **production** | `https://drd.nexventures.net/api/v1` | Production deployment |

### 2. Dynamic URL Resolution

Modified `lib/config/constants.dart`:
```dart
// Before: Hardcoded static URL
static const String baseUrl = 'https://drd.nexventures.net/api/v1';

// After: Dynamic based on environment
static String get baseUrl => EnvironmentConfig.getApiBaseUrl();
```

### 3. Initialization in main.dart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize with appropriate flavor
  EnvironmentConfig.init(BuildFlavor.development);  // or production
  
  // ... rest of app initialization
}
```

## How to Use

### For Development (USB + Same Network)

```bash
# 1. Update the IP address in lib/config/environment.dart if needed
# development: 'http://192.168.1.69:8000/api/v1'

# 2. Run on connected device
flutter run

# Or build debug APK
./build_debug_dev.sh
```

### For Production Release Builds

**Option 1: Automatic (Recommended)**

```bash
# Build release for production
./build_release_prod.sh
```

**Option 2: Manual**

1. In `lib/main.dart`, change:
   ```dart
   EnvironmentConfig.init(BuildFlavor.development);
   ```
   to:
   ```dart
   EnvironmentConfig.init(BuildFlavor.production);
   ```

2. Build release APK:
   ```bash
   flutter build apk --release
   ```

### For Testing Before Production

```bash
# Install the release APK locally to test
adb install -r build/app/outputs/flutter-apk/app-production-release.apk
```

## Troubleshooting

### App Still Can't Connect?

1. **Verify Server is Running**
   ```bash
   # Check if server is accessible from the device's network
   curl -v http://[server-ip]:8000/health
   ```

2. **Check API Endpoint**
   - Open your app settings or add debug logging to see current endpoint
   - Ensure `EnvironmentConfig.init()` is called with correct flavor

3. **SSL/Certificate Issues** (if using HTTPS)
   - Self-signed certs may cause connection failures
   - Add certificate pinning or update certificates on server

4. **Firewall/Network Issues**
   - Ensure port 8000 (or 443 for HTTPS) is open
   - Check if mobile device is on same network (for local dev)
   - Verify no corporate firewalls blocking connections

5. **DNS Resolution**
   ```bash
   # Test DNS resolution
   nslookup drd.nexventures.net
   # Should resolve to your server's public IP
   ```

### Environment Variable Alternative (Advanced)

If you want to avoid code changes for different builds, use `--dart-define`:

```bash
# Development
flutter run --dart-define=FLAVOR=development

# Production
flutter run --dart-define=FLAVOR=production
```

Then update `environment.dart` to read from `const String.fromEnvironment()`.

## Files Modified

- ✅ `lib/config/environment.dart` - NEW: Environment configuration
- ✅ `lib/config/constants.dart` - UPDATED: Use dynamic URLs from environment
- ✅ `lib/main.dart` - UPDATED: Initialize environment at startup
- ✅ `build_debug_dev.sh` - NEW: Build script for development
- ✅ `build_release_prod.sh` - NEW: Build script for production

## Next Steps

1. **Update development IP** in `lib/config/environment.dart` if your server IP is different from `192.168.1.69`
2. **Test on same network**: Run debug build via USB on same network as server
3. **Test production**: Build release APK and test on external network to ensure `drd.nexventures.net` is properly configured
4. **Set up production server**: Ensure `drd.nexventures.net` points to your actual server with proper SSL certificates

## Server Setup Requirements for Production

Your server needs:
- ✅ Public IP address or domain name
- ✅ DNS record pointing to server (`drd.nexventures.net`)
- ✅ SSL certificate (from Let's Encrypt or CA)
- ✅ Port forwarding: 80/443 → 8000
- ✅ Firewall rules allowing HTTPS traffic

For development, if server is local:
- Dev machine: `192.168.1.69:8000` (or your actual local IP)
- Mobile device: Same local network
- No SSL needed (HTTP is fine)
