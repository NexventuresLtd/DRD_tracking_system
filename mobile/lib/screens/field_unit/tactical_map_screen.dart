import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http_parser/http_parser.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import 'live_feed_screen.dart';
import '../../services/notification_service.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';

// ─── Data models ────────────────────────────────────────────────────────────

class TacticalMark {
  final String id;
  final String? backendId; // POI id on server
  final String typeId;
  final String label;
  final LatLng position;
  final Color color;
  final String symbol;
  final DateTime timestamp;

  TacticalMark({
    required this.id,
    this.backendId,
    required this.typeId,
    required this.label,
    required this.position,
    required this.color,
    required this.symbol,
    required this.timestamp,
  });

  TacticalMark copyWith({String? backendId}) => TacticalMark(
    id: id,
    backendId: backendId ?? this.backendId,
    typeId: typeId,
    label: label,
    position: position,
    color: color,
    symbol: symbol,
    timestamp: timestamp,
  );
}

// ─── Configuration ───────────────────────────────────────────────────────────

enum TacMapType { tactical, standard, satellite, terrain, hybrid }

const _tileConfigs = <TacMapType, Map<String, dynamic>>{
  TacMapType.tactical: {
    'url': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    'subs': ['a', 'b', 'c', 'd'],
    'label': 'TACTICAL',
    'iconData': 0xe518, // dark_mode
  },
  TacMapType.standard: {
    'url': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'label': '2D MAP',
    'iconData': 0xe55b, // map
  },
  TacMapType.satellite: {
    'url':
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'label': 'SATELLITE',
    'iconData': 0xf0541, // satellite_alt
  },
  TacMapType.terrain: {
    'url': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'label': 'TERRAIN',
    'iconData': 0xe5d5, // terrain
  },
  TacMapType.hybrid: {
    'url':
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'overlay':
        'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
    'label': 'HYBRID',
    'iconData': 0xe4b9, // layers
  },
};

const _markTypes = [
  {
    'id': 'enemy_contact',
    'label': 'ENEMY CONTACT',
    'symbol': 'CNT',
    'color': 0xFFEF4444,
    'poi_type': 'checkpoint',
    'severity': 'high',
    'event': 'ALERT',
  },
  {
    'id': 'enemy_vehicle',
    'label': 'ENEMY VEH.',
    'symbol': 'VEH',
    'color': 0xFFDC2626,
    'poi_type': 'vehicle',
    'severity': 'high',
    'event': 'ALERT',
  },
  {
    'id': 'ied_suspected',
    'label': 'IED / MINE',
    'symbol': 'IED',
    'color': 0xFFB91C1C,
    'poi_type': 'observation',
    'severity': 'high',
    'event': 'ALERT',
  },
  {
    'id': 'safe_zone',
    'label': 'SAFE ZONE',
    'symbol': 'SAFE',
    'color': 0xFF22C55E,
    'poi_type': 'checkpoint',
    'severity': 'low',
    'event': 'UPDATE',
  },
  {
    'id': 'casualty',
    'label': 'CASUALTY',
    'symbol': 'MED',
    'color': 0xFFF43F5E,
    'poi_type': 'medical',
    'severity': 'high',
    'event': 'ALERT',
  },
  {
    'id': 'rendezvous',
    'label': 'RV POINT',
    'symbol': 'RV',
    'color': 0xFF3B82F6,
    'poi_type': 'meeting',
    'severity': 'low',
    'event': 'UPDATE',
  },
  {
    'id': 'extraction',
    'label': 'EXTRACTION',
    'symbol': 'EXT',
    'color': 0xFFEAB308,
    'poi_type': 'extraction',
    'severity': 'medium',
    'event': 'UPDATE',
  },
  {
    'id': 'supply',
    'label': 'SUPPLY',
    'symbol': 'SUP',
    'color': 0xFFF97316,
    'poi_type': 'supply',
    'severity': 'low',
    'event': 'UPDATE',
  },
  {
    'id': 'obs_post',
    'label': 'OBS POST',
    'symbol': 'OBS',
    'color': 0xFF64748B,
    'poi_type': 'observation',
    'severity': 'low',
    'event': 'UPDATE',
  },
  {
    'id': 'cmd_post',
    'label': 'CMD POST',
    'symbol': 'CMD',
    'color': 0xFF8B5CF6,
    'poi_type': 'command',
    'severity': 'low',
    'event': 'UPDATE',
  },
];

const _sosTypes = [
  {
    'id': 'medical',
    'label': 'MEDICAL EMERGENCY',
    'desc': 'Soldier requires immediate medical attention',
    'color': 0xFFF43F5E,
  },
  {
    'id': 'threat',
    'label': 'UNDER ATTACK',
    'desc': 'Unit is engaged / taking fire',
    'color': 0xFFEF4444,
  },
  {
    'id': 'extraction',
    'label': 'REQUEST EXTRACTION',
    'desc': 'Unit needs immediate extraction',
    'color': 0xFFF59E0B,
  },
  {
    'id': 'other',
    'label': 'GENERAL DISTRESS',
    'desc': 'Other emergency — send help',
    'color': 0xFF8B5CF6,
  },
];

// ─── Main Screen ─────────────────────────────────────────────────────────────

class TacticalMapScreen extends StatefulWidget {
  const TacticalMapScreen({super.key});

  @override
  State<TacticalMapScreen> createState() => _TacticalMapScreenState();
}

class _TacticalMapScreenState extends State<TacticalMapScreen>
    with TickerProviderStateMixin {
  // ── Core ────────────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  // ── State ───────────────────────────────────────────────────────────────────
  TacMapType _mapType = TacMapType.tactical;
  List<Map<String, dynamic>> _teamLocations = [];
  List<Map<String, dynamic>> _myRoutes = [];
  List<Map<String, dynamic>> _sharedPois = [];
  List<Map<String, dynamic>> _messages = [];
  final List<TacticalMark> _marks = [];
  bool _markMode = false;
  bool _mapReady = false;
  bool _sosActive = false;
  bool _panelOpen = false;
  bool _sending = false;
  Map<String, dynamic>? _activeNavRoute;
  LatLng? _navDestination;
  Map<String, dynamic>? _activeFollowSession;
  List<LatLng> _activeRouteRoad = [];
  List<LatLng> _previewRoad = []; // OSRM road preview before follow starts
  // OSRM roads per route id: routeId → road polyline starting from soldier's position
  final Map<String, List<LatLng>> _routeRoads = {};
  LatLng? _lastRoadFetchPos; // track position to know when to re-fetch
  // Checkpoint tracking
  int _currentWaypointIndex = 0;
  bool _routePaused = false;
  bool _checkpointReached = false;
  String? _currentCheckpointLabel;

  // ── Controllers ─────────────────────────────────────────────────────────────
  Timer? _refreshTimer;
  WebSocketChannel? _locChannel;
  WebSocketChannel? _msgChannel;
  WebSocketChannel? _evtChannel;
  late AnimationController _pulseCtrl;
  late AnimationController _sosCtrl;
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _msgScroll = ScrollController();

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _sosCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
      _initTracking();
      _loadMapData();
      _loadMessages();
      _connectWebSockets();
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadMapData();
      _loadMessages();
    });
  }

  Future<void> _initTracking() async {
    final auth = context.read<AuthProvider>();
    if (auth.user != null) {
      await context.read<LocationProvider>().initialize(auth.user!.id);
    }
  }

  // ── Permissions ──────────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.photos].request();
  }

  // ── Evidence helpers ─────────────────────────────────────────────────────────

  Future<String?> _uploadImageAsEvidence({
    required XFile image,
    String? poiId,
    String? messageId,
    String? caption,
  }) async {
    MediaType mediaTypeForImage(String path) {
      final lowerPath = path.toLowerCase();
      if (lowerPath.endsWith('.png')) {
        return MediaType('image', 'png');
      }
      if (lowerPath.endsWith('.webp')) {
        return MediaType('image', 'webp');
      }
      if (lowerPath.endsWith('.gif')) {
        return MediaType('image', 'gif');
      }
      return MediaType('image', 'jpeg');
    }

    Future<http.StreamedResponse> sendUpload(String token) async {
      final uri = Uri.parse('${AppConstants.baseUrl}/evidence/upload');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(
          await http.MultipartFile.fromPath(
            'files',            // server expects field name "files" (plural)
            image.path,
            filename: image.name,
            contentType: mediaTypeForImage(image.path),
          ),
        )
        ..fields['caption'] = caption ?? '';

      if (poiId != null) request.fields['poi_id'] = poiId;
      if (messageId != null) request.fields['message_id'] = messageId;

      return request.send().timeout(const Duration(seconds: 45));
    }

    Future<String?> parseUploadResponse(http.StreamedResponse response) async {
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Evidence upload failed: ${response.statusCode} $body');
        return null;
      }

      if (body.isEmpty) {
        return null;
      }

      try {
        final data = jsonDecode(body);
        if (data is! Map<String, dynamic>) return null;

        final rawUrl = (data['url'] ?? data['file_url'] ?? data['file_path'])
            ?.toString();
        if (rawUrl == null || rawUrl.isEmpty) return null;

        final uri = Uri.parse(rawUrl);
        if (uri.isAbsolute) {
          return rawUrl;
        }

        return Uri.parse(
          AppConstants.baseUrl,
        ).replace(path: '').resolve(rawUrl).toString();
      } catch (e) {
        debugPrint('Evidence upload parse error: $e');
        return null;
      }
    }

    try {
      final token = await _storage.getToken();
      if (token == null) return null;

      var response = await sendUpload(token);
      if (response.statusCode == 401) {
        final refreshToken = await _storage.getRefreshToken();
        if (refreshToken != null) {
          final refreshResponse = await http.post(
            Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refreshToken}),
          );
          if (refreshResponse.statusCode == 200) {
            final refreshData =
                jsonDecode(refreshResponse.body) as Map<String, dynamic>;
            final newToken = refreshData['access_token'] as String?;
            final newRefreshToken = refreshData['refresh_token'] as String?;
            if (newToken != null && newToken.isNotEmpty) {
              await _storage.saveToken(newToken);
              if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
                await _storage.saveRefreshToken(newRefreshToken);
              }
              response = await sendUpload(newToken);
            }
          }
        }
      }

      return await parseUploadResponse(response);
    } catch (e) {
      debugPrint('Evidence upload error: $e');
    }
    return null;
  }

  Future<void> _showEvidenceCaptureDialog(
    String poiId,
    String markLabel,
  ) async {
    if (!mounted) return;
    final pick = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: const Color(0xFF0F1C2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Row(
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  color: DRDTheme.primaryColor,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'Add Evidence Photo?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Attach a photo to this mark as evidence for the command center.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _evidencePickerBtn(
                    Icons.camera_alt,
                    'Take Photo',
                    DRDTheme.primaryColor,
                    () => Navigator.pop(ctx, 'camera'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _evidencePickerBtn(
                    Icons.photo_library_outlined,
                    'Gallery',
                    DRDTheme.accentColor,
                    () => Navigator.pop(ctx, 'gallery'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _evidencePickerBtn(
                    Icons.videocam_rounded,
                    'Live Feed',
                    const Color(0xFFEF4444),
                    () => Navigator.pop(ctx, 'live'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _evidencePickerBtn(
                    Icons.close,
                    'Skip',
                    Colors.white38,
                    () => Navigator.pop(ctx, null),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    // Live feed option — open camera as live stream to command
    if (pick == 'live') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveFeedScreen()));
      return;
    }

    if (pick == null) return;

    final source = pick == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final perm = source == ImageSource.camera ? Permission.camera : Permission.photos;
    if (await perm.isDenied) await perm.request();
    if (!mounted) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, imageQuality: 75, maxWidth: 1280);
    if (image == null || !mounted) return;

    _showSnack('Uploading evidence…', color: DRDTheme.primaryColor);
    final url = await _uploadImageAsEvidence(image: image, poiId: poiId, caption: markLabel);

    if (!mounted) return;
    if (url != null) {
      _showSnack('Evidence photo uploaded ✓', color: DRDTheme.successColor);
    } else {
      _showSnack('Upload failed — check connection', color: const Color(0xFFEF4444));
    }
  }

  Widget _evidencePickerBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chat image upload ─────────────────────────────────────────────────────────

  Future<void> _pickAndSendChatImage() async {
    // Show source picker first (no async gap before context use)
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: const Color(0xFF0F1C2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Send Image',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _evidencePickerBtn(
                    Icons.camera_alt,
                    'Camera',
                    DRDTheme.primaryColor,
                    () => Navigator.pop(ctx, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _evidencePickerBtn(
                    Icons.photo_library_outlined,
                    'Gallery',
                    DRDTheme.accentColor,
                    () => Navigator.pop(ctx, ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    // Request permission after user chose source
    final perm = source == ImageSource.camera
        ? Permission.camera
        : Permission.photos;
    if (await perm.isDenied) await perm.request();
    if (!mounted) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024,
    );
    if (image == null || !mounted) return;

    setState(() => _sending = true);
    final url = await _uploadImageAsEvidence(image: image);
    if (!mounted) return;
    if (url != null) {
      await _sendMessage('[evidence_image]$url');
    } else {
      _showSnack('Image upload failed', color: DRDTheme.dangerColor);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _loadMapData() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final teamId = auth.user?.teamId;
    final userId = auth.user?.id;

    final results = await Future.wait([
      _api.get(teamId != null ? '/locations?team_id=$teamId' : '/locations').catchError((_) => null),
      _api.get('/routes?is_active=true${userId != null ? '&user_id=$userId' : ''}').catchError((_) => null),
      if (teamId != null) _api.get('/routes?is_active=true&team_id=$teamId').catchError((_) => null),
      _api.get('/pois?status=active').catchError((_) => null),
      _api.get('/route-follow-sessions/me').catchError((_) => null),
    ]);

    if (!mounted) return;
    final hasTeam = teamId != null;
    final userRoutes = (results[1] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final teamRoutes = hasTeam ? ((results[2] as List?)?.cast<Map<String, dynamic>>() ?? []) : <Map<String, dynamic>>[];
    final seen = <dynamic>{for (final r in userRoutes) r['id']};
    final mergedRoutes = [...userRoutes, ...teamRoutes.where((r) => seen.add(r['id']))];
    final poisResult = results[hasTeam ? 3 : 2];
    final sessionResult = results[hasTeam ? 4 : 3];

    setState(() {
      _teamLocations = (results[0] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _myRoutes      = mergedRoutes;
      _sharedPois    = (poisResult as List?)?.cast<Map<String, dynamic>>() ?? [];
      final session  = sessionResult;
      if (session is Map<String, dynamic>) _activeFollowSession = session;
    });
  }

  Future<void> _loadMessages() async {
    if (!mounted) return;
    try {
      final res = await _api.get('/messages?size=50');
      if (!mounted) return;
      final items =
          ((res as Map<String, dynamic>?)?['items'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      setState(() => _messages = items.reversed.toList());
    } catch (_) {}
  }

  void _connectWebSockets() async {
    // Cache auth info BEFORE any await to avoid BuildContext-across-async-gap warning
    final cachedTeamName = context.read<AuthProvider>().user?.teamName ?? 'Your Team';
    final token = await _storage.getToken();
    if (token == null) return;

    // Location WebSocket – receive real-time team positions
    _locChannel = WebSocketChannel.connect(
      Uri.parse('${AppConstants.wsUrl}/locations?token=$token'),
    );
    _locChannel!.stream.listen((raw) {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final d = (data['data'] ?? data) as Map<String, dynamic>;
      final uid = d['user_id'] as String?;
      if (uid == null) return;
      setState(() {
        final idx = _teamLocations.indexWhere((l) => l['user_id'] == uid);
        if (idx >= 0) {
          _teamLocations[idx] = {..._teamLocations[idx], ...d};
        } else {
          _teamLocations.add(Map<String, dynamic>.from(d));
        }
      });
    });

    // Message WebSocket
    _msgChannel = WebSocketChannel.connect(
      Uri.parse('${AppConstants.wsUrl}/messages?token=$token'),
    );
    _msgChannel!.stream.listen((raw) {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final d = (data['data'] ?? data) as Map<String, dynamic>;
      if (d['content'] == null) return;
      setState(() {
        if (!_messages.any((m) => m['id'] == d['id'])) {
          _messages.add(d);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_msgScroll.hasClients) {
          _msgScroll.animateTo(
            _msgScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });

    // Event WebSocket - keep routes and POIs synced in real time
    try {
      // Use the team name cached before the first async gap

      _evtChannel = WebSocketChannel.connect(
        Uri.parse('${AppConstants.wsUrl}/events?token=$token'),
      );
      _evtChannel!.stream.listen((raw) {
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          final d = (data['data'] ?? data) as Map<String, dynamic>;
          final eventType = (d['event_type'] ?? '').toString().toUpperCase();
          if (eventType == 'ROUTE' || eventType == 'ZONE' || eventType == 'POI' || eventType.startsWith('ROUTE_FOLLOW')) {
            _loadMapData();
            // Push notification for new route assigned (works even when app is in background)
            if (eventType == 'ROUTE') {
              final routeName = d['description'] as String? ?? 'New mission assigned';
              NotificationService.instance.showNewRoute(routeName, cachedTeamName);
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  // ── Backend actions ──────────────────────────────────────────────────────────

  Future<void> _placeMark(Map<String, dynamic> markType, LatLng pos) async {
    final auth = context.read<AuthProvider>();
    final label = '${markType['label']} ${_marks.length + 1}';

    // Add locally immediately
    final mark = TacticalMark(
      id: 'mark_${DateTime.now().millisecondsSinceEpoch}',
      typeId: markType['id'] as String,
      label: label,
      position: pos,
      color: Color(markType['color'] as int),
      symbol: markType['symbol'] as String,
      timestamp: DateTime.now(),
    );
    setState(() {
      _marks.add(mark);
      _markMode = false;
    });

    // POST to backend: create POI — capture id for evidence upload
    String? poiId;
    try {
      final res = await _api.post('/pois', {
        'name': label,
        'poi_type': markType['poi_type'],
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'tactical_shape': 'diamond',
        'status': 'active',
        'visible_to_all': true,
      });
      poiId = (res as Map<String, dynamic>?)?['id'] as String?;
      // Save backend ID in the mark for later deletion/detail view
      if (poiId != null) {
        setState(() {
          final idx = _marks.indexWhere((m) => m.id == mark.id);
          if (idx >= 0) _marks[idx] = _marks[idx].copyWith(backendId: poiId);
        });
      }
    } catch (_) {}

    // POST to backend: create event
    try {
      await _api.post('/events', {
        'event_type': markType['event'],
        'user_id': auth.user?.id,
        'description':
            '$label spotted at ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
        'location_lat': pos.latitude,
        'location_lng': pos.longitude,
        'severity': markType['severity'],
      });
    } catch (_) {}

    _showSnack(
      '${markType['label']} marked & reported to command',
      color: Color(markType['color'] as int),
    );

    // Offer evidence photo capture after mark is placed
    if (poiId != null && mounted) {
      await _showEvidenceCaptureDialog(poiId, label);
    }
  }

  Future<void> _triggerSOS(Map<String, dynamic> sosType) async {
    final auth = context.read<AuthProvider>();
    final locP = context.read<LocationProvider>();
    setState(() => _sosActive = true);

    final lat = locP.hasRealFix ? locP.latitude : null;
    final lng = locP.hasRealFix ? locP.longitude : null;
    final teamId = auth.user?.teamId;
    final unitName = auth.user?.fullName ?? 'Field Unit';

    try {
      await _api.post('/events', {
        'event_type': 'FLAG',
        'user_id': auth.user?.id,
        'team_id': ?teamId,
        'description':
            'SOS: ${sosType['label']} — $unitName needs immediate assistance',
        'location_lat': ?lat,
        'location_lng': ?lng,
        'severity': 'high',
        'event_metadata': {'sos_type': sosType['id'], 'unit_name': unitName},
      });
    } catch (_) {}

    _showSnack(
      'SOS SENT — Command has been alerted!',
      color: DRDTheme.dangerColor,
    );
  }

  Future<void> _sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    final auth = context.read<AuthProvider>();
    setState(() => _sending = true);
    try {
      final res = await _api.post('/messages', {
        'to_all': auth.user?.teamId == null,
        if (auth.user?.teamId != null) 'to_team_id': auth.user!.teamId,
        'content': content.trim(),
        'priority': 'normal',
      });
      if (res != null) {
        _msgCtrl.clear();
        await _loadMessages();
      }
    } catch (_) {}
    setState(() => _sending = false);
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────────

  void _showMarkTypeDialog(LatLng pos) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DRDTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.push_pin,
                  color: DRDTheme.warningColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'MARK TYPE  —  ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: LayoutBuilder(
              builder: (_, constraints) {
                final width = constraints.maxWidth;
                final columns = width < 320 ? 3 : (width < 420 ? 4 : 5);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: _markTypes.length,
                  itemBuilder: (_, i) {
                    final mt = _markTypes[i];
                    final color = Color(mt['color'] as int);
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _placeMark(mt, pos);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              mt['symbol'] as String,
                              style: TextStyle(
                                color: color,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              mt['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: color.withValues(alpha: 0.85),
                                fontSize: 7.5,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSOSDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DRDTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(Icons.sos, color: Color(0xFFEF4444), size: 20),
                SizedBox(width: 8),
                Text(
                  'EMERGENCY — SELECT TYPE',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ..._sosTypes.map((sos) {
            final color = Color(sos['color'] as int);
            return ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              title: Text(
                sos['label'] as String,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                sos['desc'] as String,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                _triggerSOS(sos);
              },
            );
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _showRoutesSheet() {
    if (_myRoutes.isEmpty) {
      _showSnack(
        'No routes assigned to your team',
        color: DRDTheme.warningColor,
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: DRDTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.alt_route, color: DRDTheme.accentColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  'ASSIGNED ROUTES — TAP TO NAVIGATE',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: _myRoutes.length,
            itemBuilder: (_, i) {
              final r = _myRoutes[i];
              final name = r['name'] as String? ?? 'Route';
              final color = _colorFromHex(r['color']);
              final wps = r['waypoints'] as List?;
              final wpsCount = wps?.length ?? 0;
              final routeStatus =
                  (r['route_status'] as String? ??
                          (r['is_active'] == false ? 'completed' : 'assigned'))
                      .toUpperCase();
              final isActive =
                  _activeNavRoute != null && _activeNavRoute!['id'] == r['id'];
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _showRouteDetailsSheet(r);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF00E5FF).withValues(alpha: 0.12)
                        : color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.6)
                          : color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF00E5FF) : color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                color: isActive
                                    ? const Color(0xFF00E5FF)
                                    : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$wpsCount waypoints · $routeStatus${isActive ? '  ·  NAVIGATING' : ''}',
                              style: TextStyle(
                                color: isActive
                                    ? const Color(
                                        0xFF00E5FF,
                                      ).withValues(alpha: 0.8)
                                    : Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isActive ? Icons.navigation : Icons.chevron_right,
                        color: isActive
                            ? const Color(0xFF00E5FF)
                            : Colors.white24,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── UI Builder ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<LocationProvider>(
      builder: (context, loc, _) {
        final auth = context.read<AuthProvider>();
        // Fall back to operation area default until GPS has a real fix
        final myPos = loc.hasRealFix
            ? LatLng(loc.latitude, loc.longitude)
            : const LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
        final myId = auth.user?.id;
        final topPad = MediaQuery.of(context).padding.top;

        // Check for checkpoint arrival after every render
        if (_activeNavRoute != null && !_routePaused && !_checkpointReached) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _checkNearbyCheckpoints(myPos);
          });
        }
        final screenH = MediaQuery.of(context).size.height;
        final panelHeight = (screenH * 0.46).clamp(260.0, 360.0).toDouble();

        return Scaffold(
          backgroundColor: DRDTheme.backgroundColor,
          body: Stack(
            children: [
              // ── Full-screen map ──────────────────────────────────────────
              _buildMap(myPos, myId, loc),

              if (!_mapReady)
                Container(
                  color: DRDTheme.backgroundColor,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: DRDTheme.primaryColor),
                        SizedBox(height: 14),
                        Text(
                          'INITIALIZING TACTICAL MAP…',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_mapReady) ...[
                // ── Map type selector ──────────────────────────────────────
                Positioned(
                  top: topPad + 6,
                  left: 0,
                  right: 0,
                  child: _buildMapTypeBar(),
                ),

                // ── GPS / Status HUD ───────────────────────────────────────
                Positioned(top: topPad + 52, left: 10, child: _buildHud(loc)),

                // ── Team badge + Profile button ────────────────────────────
                Positioned(
                  top: topPad + 52,
                  right: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildTeamBadge(),
                      const SizedBox(height: 8),
                      _buildProfileButton(auth),
                    ],
                  ),
                ),

                // ── Mark mode crosshair ────────────────────────────────────
                if (_markMode) _buildCrosshair(screenH),

                // ── Active navigation info bar ─────────────────────────────
                if (_activeNavRoute != null) ...[
                  Positioned(
                    top: topPad + 52,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildNavBar(myPos)),
                  ),
                  // Checkpoint reached overlay
                  if (_checkpointReached)
                    Positioned(
                      top: topPad + 100,
                      left: 0,
                      right: 0,
                      child: Center(child: _buildCheckpointOverlay(myPos)),
                    ),
                ],

                // ── Left tactical action column ────────────────────────────
                Positioned(
                  left: 8,
                  top: max(topPad + 120, screenH / 2 - 90),
                  child: _buildActionColumn(),
                ),

                // ── SOS button ─────────────────────────────────────────────
                Positioned(
                  bottom: _panelOpen ? panelHeight + 16 : 28,
                  left: 12,
                  child: _buildSOSButton(),
                ),

                // ── Navigation FABs ────────────────────────────────────────
                Positioned(
                  bottom: _panelOpen ? panelHeight + 16 : 60,
                  right: 12,
                  child: _buildNavFabs(loc, myPos),
                ),

                // ── Comms panel — only visible when opened ─────────────────
                if (_panelOpen)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: panelHeight,
                    child: _buildBottomPanel(auth, panelHeight),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Map ──────────────────────────────────────────────────────────────────────

  Widget _buildMap(LatLng myPos, String? myId, LocationProvider loc) {
    final tile = _tileConfigs[_mapType]!;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: myPos,
        initialZoom: AppConstants.defaultZoom,
        onMapReady: () => setState(() => _mapReady = true),
        onLongPress: (_, point) {
          if (_markMode) _showMarkTypeDialog(point);
        },
      ),
      children: [
        // Base tile
        TileLayer(
          urlTemplate: tile['url'] as String,
          subdomains: (tile['subs'] as List<String>?)?.toList() ?? const [],
          userAgentPackageName: 'com.drd.fieldops',
        ),
        // Hybrid label overlay
        if (_mapType == TacMapType.hybrid && tile['overlay'] != null)
          TileLayer(
            urlTemplate: tile['overlay'] as String,
            userAgentPackageName: 'com.drd.fieldops',
          ),
        // Approach preview: only shown when no OSRM road is active yet
        if (_activeRouteRoad.isEmpty)
          PolylineLayer(polylines: _buildApproachLines(myPos)),
        // Route polylines
        PolylineLayer(polylines: _buildRouteLines()),
        // Active route: OSRM road polyline when available, otherwise straight line
        if (_navDestination != null)
          PolylineLayer(
            polylines: [
              if (_activeRouteRoad.length >= 2)
                Polyline(
                  points: _activeRouteRoad,
                  color: const Color(0xFF00E5FF),
                  strokeWidth: 3.5,
                )
              else
                Polyline(
                  points: [myPos, _navDestination!],
                  color: const Color(0xFF00E5FF),
                  strokeWidth: 2.5,
                  isDotted: true,
                ),
            ],
          ),
        // Nav destination marker
        if (_navDestination != null)
          MarkerLayer(markers: [_buildNavDestMarker(_navDestination!)]),
        // Waypoint markers
        MarkerLayer(markers: _buildWaypointMarkers()),
        // Shared POI markers from backend
        MarkerLayer(markers: _buildSharedPoiMarkers()),
        // Tactical marks
        MarkerLayer(markers: _buildMarkMarkers()),
        // Team members
        MarkerLayer(markers: _buildTeamMarkers(myId)),
        // Own position
        MarkerLayer(
          markers: [
            Marker(
              point: myPos,
              width: 80,
              height: 80,
              child: _buildOwnMarker(loc),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOwnMarker(LocationProvider loc) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, _) {
        final t = _pulseCtrl.value;
        final sosFlash = _sosActive ? _sosCtrl.value : 0.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulse ring
            Container(
              width: 80 * t,
              height: 80 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      (_sosActive
                              ? DRDTheme.dangerColor
                              : DRDTheme.primaryColor)
                          .withValues(alpha: 0.45 * (1 - t)),
                  width: 2,
                ),
              ),
            ),
            // SOS flash ring
            if (_sosActive)
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: DRDTheme.dangerColor.withValues(
                      alpha: 0.6 * sosFlash,
                    ),
                    width: 3,
                  ),
                ),
              ),
            // Core marker
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    (_sosActive ? DRDTheme.dangerColor : DRDTheme.primaryColor)
                        .withValues(alpha: 0.2),
                border: Border.all(
                  color: _sosActive
                      ? DRDTheme.dangerColor
                      : DRDTheme.primaryColor,
                  width: 2.5,
                ),
              ),
            ),
            // Heading arrow
            Transform.rotate(
              angle: loc.heading * pi / 180,
              child: Icon(
                Icons.navigation,
                color: _sosActive
                    ? DRDTheme.dangerColor
                    : DRDTheme.primaryColor,
                size: 22,
              ),
            ),
            // SOS label
            if (_sosActive)
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: DRDTheme.dangerColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Marker _buildNavDestMarker(LatLng point) {
    final routeName = _activeNavRoute?['name'] as String? ?? 'DESTINATION';
    return Marker(
      point: point,
      width: 64,
      height: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              routeName.length > 10
                  ? '${routeName.substring(0, 9)}…'
                  : routeName,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              border: Border.all(color: const Color(0xFF00E5FF), width: 2.5),
            ),
            child: const Icon(Icons.flag, color: Color(0xFF00E5FF), size: 16),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildTeamMarkers(String? myId) {
    return _teamLocations
        .where((l) => l['user_id'] != myId)
        .map((l) {
          final lat = (l['latitude'] as num?)?.toDouble();
          final lng = (l['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) return null;

          final status = l['status'] as String? ?? 'offline';
          final statusColor = DRDTheme.statusColors[status] ?? Colors.grey;
          final name = l['user_name'] as String? ?? '?';
          final initials = name
              .split(' ')
              .where((w) => w.isNotEmpty)
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();
          final shortName = name.split(' ').first;

          return Marker(
            point: LatLng(lat, lng),
            width: 56,
            height: 72,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Solid blue circle with white initials
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DRDTheme.primaryColor,
                    border: Border.all(color: statusColor, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: DRDTheme.primaryColor.withValues(alpha: 0.45),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                // Name label
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    shortName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        })
        .whereType<Marker>()
        .toList();
  }

  static const _enemyTypeIds = {'enemy_contact', 'enemy_vehicle', 'ied_suspected'};

  List<Marker> _buildMarkMarkers() {
    return _marks.map((m) {
      final isEnemy = _enemyTypeIds.contains(m.typeId);
      final markerSize = isEnemy ? 48.0 : 36.0;

      Widget markerWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: markerSize,
            height: markerSize,
            decoration: BoxDecoration(
              color: isEnemy ? const Color(0xFFEF4444).withValues(alpha: 0.25) : m.color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: isEnemy ? const Color(0xFFEF4444) : m.color,
                width: isEnemy ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isEnemy ? const Color(0xFFEF4444) : m.color).withValues(alpha: isEnemy ? 0.7 : 0.5),
                  blurRadius: isEnemy ? 14 : 6,
                  spreadRadius: isEnemy ? 3 : 1,
                ),
              ],
            ),
            child: Center(
              child: Text(
                m.symbol,
                style: TextStyle(
                  color: isEnemy ? Colors.white : m.color,
                  fontSize: isEnemy ? 14 : 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: isEnemy ? const Color(0xFFEF4444) : m.color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
              boxShadow: isEnemy ? [const BoxShadow(color: Color(0xFFEF4444), blurRadius: 4, spreadRadius: 0)] : null,
            ),
            child: Text(
              m.label.split(' ').take(2).join(' '),
              style: TextStyle(
                color: Colors.white,
                fontSize: isEnemy ? 8 : 6.5,
                fontWeight: isEnemy ? FontWeight.w900 : FontWeight.bold,
                letterSpacing: isEnemy ? 0.5 : 0,
              ),
            ),
          ),
          // ENEMY label
          if (isEnemy) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFFEF4444), width: 0.5),
              ),
              child: const Text(
                '⚠ ENEMY',
                style: TextStyle(color: Color(0xFFEF4444), fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ),
          ],
        ],
      );

      // Wrap enemy marks in AnimatedBuilder for pulsing glow effect
      if (isEnemy) {
        markerWidget = AnimatedBuilder(
          animation: _sosCtrl, // reuse SOS animation controller for pulsing
          builder: (ctx, child) {
            return Transform.scale(
              scale: 0.95 + 0.05 * _sosCtrl.value,
              child: child,
            );
          },
          child: markerWidget,
        );
      }

      return Marker(
        point: m.position,
        width: isEnemy ? 64 : 44,
        height: isEnemy ? 80 : 56,
        child: GestureDetector(
          onTap: () => _showMarkDetailsSheet(m),
          child: markerWidget,
        ),
      );
    }).toList();
  }

  void _showMarkDetailsSheet(TacticalMark m) {
    final isEnemy = _enemyTypeIds.contains(m.typeId);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1C2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Mark header
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: m.color.withValues(alpha: 0.2),
                    border: Border.all(color: m.color, width: 2),
                  ),
                  child: Center(child: Text(m.symbol, style: TextStyle(color: m.color, fontWeight: FontWeight.w900, fontSize: 13))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.label, style: TextStyle(
                        color: isEnemy ? const Color(0xFFEF4444) : Colors.white,
                        fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'Poppins',
                      )),
                      if (isEnemy)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                          ),
                          child: const Text('⚠ ENEMY MARK', style: TextStyle(
                            color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1,
                          )),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Details
            _markDetailRow(Icons.location_on_outlined, 'Location',
              '${m.position.latitude.toStringAsFixed(5)}, ${m.position.longitude.toStringAsFixed(5)}'),
            _markDetailRow(Icons.access_time, 'Marked at',
              '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')} · ${m.timestamp.day}/${m.timestamp.month}/${m.timestamp.year}'),
            if (m.backendId != null)
              _markDetailRow(Icons.fingerprint, 'Report ID', m.backendId!.substring(0, 8).toUpperCase()),
            const SizedBox(height: 20),
            // Start Live Feed button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveFeedScreen()));
                },
                icon: const Icon(Icons.videocam_rounded, size: 16),
                label: const Text('Start Live Feed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Deactivate + Delete row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _deactivateMark(m);
                    },
                    icon: const Icon(Icons.visibility_off_outlined, size: 16),
                    label: const Text('Mark Inactive'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DRDTheme.warningColor,
                      side: BorderSide(color: DRDTheme.warningColor.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _deleteMark(m);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DRDTheme.dangerColor,
                      side: BorderSide(color: DRDTheme.dangerColor.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _markDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white38),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Poppins')),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Future<void> _deactivateMark(TacticalMark m) async {
    if (m.backendId != null) {
      try {
        await _api.put('/pois/${m.backendId}', {'status': 'inactive'});
      } catch (_) {}
    }
    setState(() => _marks.removeWhere((mark) => mark.id == m.id));
    _showSnack('Mark set to inactive', color: DRDTheme.warningColor);
  }

  Future<void> _deleteMark(TacticalMark m) async {
    if (m.backendId != null) {
      try {
        await _api.delete('/pois/${m.backendId}');
      } catch (_) {}
    }
    setState(() => _marks.removeWhere((mark) => mark.id == m.id));
    _showSnack('Mark deleted', color: DRDTheme.successColor);
  }

  List<Polyline> _buildRouteLines() {
    final polylines = <Polyline>[];
    for (final route in _myRoutes) {
      final wps = route['waypoints'] as List?;
      if (wps == null || wps.length < 2) continue;
      final color = _colorFromHex(route['color']);
      polylines.add(
        Polyline(
          points: wps
              .map(
                (wp) => LatLng(
                  (wp['latitude'] as num).toDouble(),
                  (wp['longitude'] as num).toDouble(),
                ),
              )
              .toList(),
          color: color,
          strokeWidth: 3.5,
        ),
      );
    }
    return polylines;
  }

  /// Approach from current GPS position to the selected route.
  /// Uses the OSRM-fetched road preview when available, straight dashed line while loading.
  List<Polyline> _buildApproachLines(LatLng myPos) {
    // If we have the OSRM preview road, use it (actual road, not straight line)
    if (_previewRoad.length >= 2) {
      return [
        Polyline(
          points: _previewRoad,
          color: Colors.amberAccent.withValues(alpha: 0.85),
          strokeWidth: 2.5,
          isDotted: true,
        ),
      ];
    }
    // Fallback: straight dashed line while OSRM is loading
    final lines = <Polyline>[];
    for (final route in _myRoutes) {
      final wps = route['waypoints'] as List?;
      if (wps == null || wps.isEmpty) continue;
      final first = wps.first as Map<String, dynamic>;
      final lat = (first['latitude'] as num?)?.toDouble();
      final lng = (first['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final dist = _distanceKm(myPos.latitude, myPos.longitude, lat, lng);
      if (dist != null && dist < 0.02) continue;
      lines.add(Polyline(
        points: [myPos, LatLng(lat, lng)],
        color: Colors.amberAccent.withValues(alpha: 0.5),
        strokeWidth: 2,
        isDotted: true,
      ));
    }
    return lines;
  }

  List<Marker> _buildWaypointMarkers() {
    final markers = <Marker>[];
    for (final route in _myRoutes) {
      final wps = route['waypoints'] as List?;
      if (wps == null) continue;
      final color = _colorFromHex(route['color']);
      for (final wp in wps) {
        final lat = (wp['latitude'] as num?)?.toDouble();
        final lng = (wp['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 14,
            height: 14,
            child: GestureDetector(
              onTap: () => _showRouteDetailsSheet(route),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  List<Marker> _buildSharedPoiMarkers() {
    return _sharedPois
        .map((poi) {
          final lat = (poi['latitude'] as num?)?.toDouble();
          final lng = (poi['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) return null;

          final poiType = (poi['poi_type'] ?? 'checkpoint').toString();
          final status = (poi['status'] ?? 'active').toString();
          final color = _poiColor(poiType);
          final icon = _poiIcon(poiType);
          final label = (poi['name'] ?? poiType).toString();

          return Marker(
            point: LatLng(lat, lng),
            width: 36,
            height: 36,
            child: GestureDetector(
              onTap: () {
                final route = _nearestRouteToPoint(LatLng(lat, lng));
                if (route != null) {
                  _showRouteDetailsSheet(route, anchorPoint: LatLng(lat, lng));
                }
              },
              child: Tooltip(
                message: '$label (${status.toUpperCase()})',
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.2),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();
  }

  double? _routeDistanceToTarget(Map<String, dynamic> route, LatLng origin) {
    final target = _routeTarget(route);
    if (target == null) return null;
    return _distanceKm(
      origin.latitude,
      origin.longitude,
      target.latitude,
      target.longitude,
    );
  }

  Map<String, dynamic>? _nearestRouteToPoint(LatLng point) {
    Map<String, dynamic>? best;
    double? bestDistance;
    for (final route in _myRoutes) {
      final distance = _routeDistanceToTarget(route, point);
      if (distance == null) continue;
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        best = route;
      }
    }
    return best;
  }

  /// Fetches a real road-following polyline from the OSRM public API.
  /// Falls back to straight-line waypoints if the request fails.
  Future<List<LatLng>> _fetchOsrmRoute(
    List<Map<String, dynamic>> waypoints,
  ) async {
    if (waypoints.length < 2) {
      return waypoints
          .map(
            (wp) => LatLng(
              (wp['latitude'] as num).toDouble(),
              (wp['longitude'] as num).toDouble(),
            ),
          )
          .toList();
    }

    // OSRM expects coordinates as "lng,lat;lng,lat;..."
    final coords = waypoints
        .map((wp) {
          final lat = (wp['latitude'] as num).toDouble();
          final lng = (wp['longitude'] as num).toDouble();
          return '$lng,$lat';
        })
        .join(';');

    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coords'
        '?overview=full&geometries=geojson',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry = routes.first['geometry'] as Map<String, dynamic>?;
          final coordinates = geometry?['coordinates'] as List?;
          if (coordinates != null) {
            // GeoJSON coordinates are [lng, lat]
            return coordinates.map((c) {
              final lng = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              return LatLng(lat, lng);
            }).toList();
          }
        }
      }
    } catch (_) {
      // Network error or timeout — fall through to straight-line fallback
    }

    // Fallback: straight lines between waypoints
    return waypoints
        .map(
          (wp) => LatLng(
            (wp['latitude'] as num).toDouble(),
            (wp['longitude'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<void> _startFollowRoute(Map<String, dynamic> route) async {
    final waypoints =
        (route['waypoints'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (waypoints.isEmpty) {
      _showSnack('Route has no waypoints', color: DRDTheme.warningColor);
      return;
    }

    final loc = context.read<LocationProvider>();
    final session = await _api.startRouteFollow({
      'route_id': route['id'],
      'current_latitude': loc.latitude,
      'current_longitude': loc.longitude,
    });
    if (session == null) {
      _showSnack('Failed to start route follow', color: DRDTheme.dangerColor);
      return;
    }

    // Build waypoints list starting from soldier's current GPS position
    // so OSRM routes from here → first waypoint → … → destination
    final waypointsWithStart = [
      if (loc.hasRealFix)
        {'latitude': loc.latitude, 'longitude': loc.longitude},
      ...waypoints,
    ];
    final roadPoints = await _fetchOsrmRoute(waypointsWithStart);

    final target = _routeTarget(route);
    if (!mounted) return;
    setState(() {
      _activeNavRoute = route;
      _navDestination = target;
      _activeFollowSession = session as Map<String, dynamic>?;
      _activeRouteRoad = roadPoints;
      _previewRoad = []; // OSRM road takes over
      _panelOpen = false;
      // Reset checkpoint tracking
      _currentWaypointIndex = 0;
      _routePaused = false;
      _checkpointReached = false;
      _currentCheckpointLabel = null;
    });
    if (target != null && _mapReady) {
      _mapController.move(target, 14);
    }
    _showSnack('Route follow started', color: DRDTheme.successColor);
  }

  Future<void> _stopFollowSession() async {
    final session = _activeFollowSession;
    if (session == null) return;
    final result = await _api.stopRouteFollow(session['id'] as String, {
      'completion_note': 'Stopped from mobile',
    });
    if (result != null && mounted) {
      setState(() {
        _activeFollowSession = null;
        _activeNavRoute = null;
        _navDestination = null;
        _previewRoad = [];
        _activeRouteRoad = [];
        _activeRouteRoad = [];
        _currentWaypointIndex = 0;
        _routePaused = false;
        _checkpointReached = false;
        _currentCheckpointLabel = null;
      });
      _showSnack('Route follow stopped', color: DRDTheme.warningColor);
    }
  }

  void _showRouteDetailsSheet(
    Map<String, dynamic> route, {
    LatLng? anchorPoint,
  }) {
    final waypoints =
        (route['waypoints'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final target = _routeTarget(route);
    final routeName = route['name'] as String? ?? 'Route';

    // Fetch OSRM preview from current position → first waypoint → … → destination
    final loc = context.read<LocationProvider>();
    if (loc.hasRealFix && waypoints.isNotEmpty) {
      final waypointsWithStart = [
        {'latitude': loc.latitude, 'longitude': loc.longitude},
        ...waypoints,
      ];
      _fetchOsrmRoute(waypointsWithStart).then((road) {
        if (mounted) setState(() => _previewRoad = road);
      });
    }
    final routeStatus =
        (route['route_status'] as String? ??
                (route['is_active'] == false ? 'completed' : 'assigned'))
            .toUpperCase();
    final activeRouteId = _activeFollowSession?['route_id'] as String?;
    final sessionActive =
        activeRouteId == route['id'] &&
        _activeFollowSession?['status'] == 'active';

    showModalBottomSheet(
      context: context,
      backgroundColor: DRDTheme.surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colorFromHex(
                        route['color'],
                      ).withValues(alpha: 0.95),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      routeName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: sessionActive
                          ? DRDTheme.successColor.withValues(alpha: 0.18)
                          : DRDTheme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      sessionActive ? 'FOLLOWING' : routeStatus,
                      style: TextStyle(
                        color: sessionActive
                            ? DRDTheme.successColor
                            : DRDTheme.primaryColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                route['description'] as String? ??
                    'Route details are synced from the backend.',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tag('${waypoints.length} waypoints', Colors.white70),
                  if (target != null)
                    _tag(
                      'TARGET ${target.latitude.toStringAsFixed(4)}, ${target.longitude.toStringAsFixed(4)}',
                      Colors.white54,
                    ),
                  if (_activeFollowSession != null)
                    _tag(
                      'ETA ${_activeFollowSession!['eta_seconds'] ?? '--'}s',
                      Colors.white54,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: sessionActive
                          ? null
                          : () async {
                              Navigator.pop(context);
                              await _startFollowRoute(route);
                            },
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('FOLLOW ROUTE'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: sessionActive
                          ? _stopFollowSession
                          : () {
                              if (target != null && _mapReady) {
                                _mapController.move(target, 14);
                              }
                              Navigator.pop(context);
                            },
                      icon: Icon(
                        sessionActive
                            ? Icons.stop_circle_outlined
                            : Icons.center_focus_strong,
                        size: 18,
                      ),
                      label: Text(sessionActive ? 'STOP' : 'CENTER'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  LatLng? _routeTarget(Map<String, dynamic> route) {
    final wps =
        (route['waypoints'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (wps.isEmpty) return null;
    final last = wps.last;
    final lat = (last['latitude'] as num?)?.toDouble();
    final lng = (last['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  double? _distanceKm(double aLat, double aLng, double bLat, double bLng) {
    const radius = 6371.0;
    final dLat = (bLat - aLat) * pi / 180;
    final dLng = (bLng - aLng) * pi / 180;
    final lat1 = aLat * pi / 180;
    final lat2 = bLat * pi / 180;
    final sinLat = sin(dLat / 2);
    final sinLng = sin(dLng / 2);
    final a = sinLat * sinLat + cos(lat1) * cos(lat2) * sinLng * sinLng;
    return 2 * radius * asin(min(1, sqrt(a)));
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ── HUD Overlays ─────────────────────────────────────────────────────────────

  Widget _buildNavBar(LatLng myPos) {
    final routeName = _activeNavRoute?['name'] as String? ?? 'Route';
    double distKm = 0;
    if (_navDestination != null) {
      const earthR = 6371.0;
      final lat1 = myPos.latitude * pi / 180;
      final lat2 = _navDestination!.latitude * pi / 180;
      final dLat = lat2 - lat1;
      final dLng = (_navDestination!.longitude - myPos.longitude) * pi / 180;
      final a =
          sin(dLat / 2) * sin(dLat / 2) +
          cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
      distKm = earthR * 2 * atan2(sqrt(a), sqrt(1 - a));
    }
    final distLabel = distKm < 1
        ? '${(distKm * 1000).toStringAsFixed(0)} m'
        : '${distKm.toStringAsFixed(2)} km';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 60),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _routePaused ? Icons.pause_circle_rounded : Icons.navigation,
            color: _routePaused ? DRDTheme.warningColor : const Color(0xFF00E5FF),
            size: 14,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _routePaused
                  ? 'PAUSED — ${_currentCheckpointLabel ?? routeName}'
                  : routeName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _routePaused ? DRDTheme.warningColor : const Color(0xFF00E5FF),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_routePaused) ...[
            GestureDetector(
              onTap: _resumeFromCheckpoint,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DRDTheme.successColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: DRDTheme.successColor.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: DRDTheme.successColor, size: 12),
                    SizedBox(width: 3),
                    Text('RESUME', style: TextStyle(color: DRDTheme.successColor,
                        fontSize: 9, fontWeight: FontWeight.w800, fontFamily: 'Poppins')),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text(distLabel, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() {
              _activeNavRoute = null;
              _navDestination = null;
              _activeRouteRoad = [];
              _routePaused = false;
              _checkpointReached = false;
              _currentWaypointIndex = 0;
              _currentCheckpointLabel = null;
            }),
            child: const Icon(Icons.close, color: Colors.white54, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMapTypeBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: TacMapType.values.map((type) {
          final cfg = _tileConfigs[type]!;
          final active = _mapType == type;
          return GestureDetector(
            onTap: () => setState(() => _mapType = type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? DRDTheme.primaryColor
                    : DRDTheme.surfaceColor.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? DRDTheme.primaryColor
                      : Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForMapType(type),
                    size: 12,
                    color: active ? Colors.white : Colors.white60,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    cfg['label'] as String,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHud(LocationProvider loc) {
    final isDanger = !loc.isTracking || loc.batteryLevel < 20;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDanger
            ? DRDTheme.dangerColor.withValues(alpha: 0.1)
            : DRDTheme.surfaceColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDanger
              ? DRDTheme.dangerColor.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.07),
          width: isDanger ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDanger
                ? DRDTheme.dangerColor.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.35),
            blurRadius: isDanger ? 10 : 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: loc.isTracking
                      ? DRDTheme.successColor
                      : DRDTheme.dangerColor,
                  boxShadow: [
                    if (loc.isTracking)
                      BoxShadow(
                        color: DRDTheme.successColor.withValues(alpha: 0.7),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                loc.isTracking ? 'LIVE GPS' : 'GPS LOST',
                style: TextStyle(
                  color: loc.isTracking
                      ? DRDTheme.successColor
                      : DRDTheme.dangerColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _hRow(Icons.speed_outlined, '${loc.speed.toStringAsFixed(1)} km/h'),
          _hRow(
            Icons.explore_outlined,
            'HDG ${loc.heading.toStringAsFixed(0)}°',
          ),
          _hRow(
            Icons.landscape_outlined,
            'ALT ${loc.altitude.toStringAsFixed(0)} m',
          ),
          _hRow(
            Icons.battery_std_outlined,
            '${loc.batteryLevel}%',
            color: loc.batteryLevel < 20 ? DRDTheme.dangerColor : null,
          ),
          _hRow(
            Icons.gps_fixed_outlined,
            'ACC ±${loc.accuracy.toStringAsFixed(0)} m',
            color: loc.accuracy > 20 ? DRDTheme.warningColor : null,
          ),
          if (loc.pendingCount > 0)
            _hRow(
              Icons.cloud_upload_outlined,
              '${loc.pendingCount} queued',
              color: DRDTheme.warningColor,
            ),
        ],
      ),
    );
  }

  Widget _hRow(IconData icon, String text, {Color? color}) {
    final c = color ?? Colors.white60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: c, fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _buildTeamBadge() {
    final active = _teamLocations.where((l) => l['status'] == 'active').length;
    final stale = _teamLocations.where((l) => l['status'] == 'stale').length;
    final offline = _teamLocations.where((l) => l['status'] == 'offline').length;
    final hasDanger = offline > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasDanger
            ? DRDTheme.dangerColor.withValues(alpha: 0.1)
            : DRDTheme.surfaceColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDanger
              ? DRDTheme.dangerColor.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.07),
          width: hasDanger ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasDanger
                ? DRDTheme.dangerColor.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'UNIT  ${_teamLocations.length}',
            style: const TextStyle(color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 4),
          _badgeRow(DRDTheme.successColor, 'ACT', active),
          _badgeRow(DRDTheme.warningColor, 'STL', stale),
          _badgeRow(DRDTheme.dangerColor, 'OFF', offline, bold: hasDanger),
        ],
      ),
    );
  }

  Widget _badgeRow(Color color, String label, int count, {bool bold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bold && count > 0)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.warning_amber_rounded, color: color, size: 10),
          ),
        Text(
          label,
          style: TextStyle(
            color: bold && count > 0 ? color : Colors.white38,
            fontSize: bold && count > 0 ? 10 : 9,
            letterSpacing: 0.8,
            fontWeight: bold && count > 0 ? FontWeight.w800 : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: bold && count > 0 ? 12 : 10,
            fontWeight: bold && count > 0 ? FontWeight.w900 : FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileButton(AuthProvider auth) {
    final user = auth.user;
    final name = user?.fullName ?? user?.username ?? 'Operator';
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF0F1C2E),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DRDTheme.primaryColor,
                    border: Border.all(
                      color: DRDTheme.primaryColor.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: DRDTheme.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (user?.username != null && user!.username != name) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: DRDTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: DRDTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    (user?.role ?? 'FIELD UNIT').toUpperCase().replaceAll(
                      '_',
                      ' ',
                    ),
                    style: const TextStyle(
                      color: DRDTheme.primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (user?.teamName != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    user!.teamName!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _handleLogout();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('SIGN OUT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DRDTheme.dangerColor,
                      side: BorderSide(
                        color: DRDTheme.dangerColor.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: DRDTheme.primaryColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: DRDTheme.primaryColor.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'PROFILE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrosshair(double screenH) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add, color: DRDTheme.warningColor, size: 32),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: DRDTheme.warningColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'LONG PRESS TO PLACE MARK',
              style: TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live feed button
        _actionBtn(
          icon: Icons.videocam_rounded,
          label: 'LIVE',
          color: const Color(0xFFEF4444),
          solid: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LiveFeedScreen()),
          ),
        ),
        const SizedBox(height: 6),
        _actionBtn(
          icon: _markMode ? Icons.close : Icons.push_pin_outlined,
          label: _markMode ? 'CANCEL' : 'MARK',
          color: _markMode ? DRDTheme.warningColor : DRDTheme.primaryColor,
          solid: !_markMode,
          onTap: () => setState(() => _markMode = !_markMode),
        ),
        const SizedBox(height: 6),
        _actionBtn(
          icon: Icons.chat_bubble_outline,
          label: 'COMMS',
          color: DRDTheme.primaryColor,
          solid: true,
          badge: _messages.where((m) => m['is_read'] == false).length,
          onTap: () => setState(() => _panelOpen = true),
        ),
        const SizedBox(height: 6),
        _actionBtn(
          icon: Icons.alt_route,
          label: 'ROUTES',
          color: DRDTheme.primaryColor,
          solid: true,
          badge: _myRoutes.length,
          onTap: _showRoutesSheet,
        ),
        const SizedBox(height: 14),
        _actionBtn(
          icon: Icons.logout_rounded,
          label: 'EXIT',
          color: DRDTheme.dangerColor,
          solid: true,
          onTap: _handleLogout,
        ),
      ],
    );
  }

  // ── Checkpoint pause / resume ─────────────────────────────────────────────

  void _checkNearbyCheckpoints(LatLng myPos) {
    if (_activeNavRoute == null || _routePaused) return;
    final wps = (_activeNavRoute!['waypoints'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];
    if (wps.isEmpty) return;

    // Check every intermediate waypoint (skip last — that's the final destination)
    for (int i = _currentWaypointIndex; i < wps.length - 1; i++) {
      final lat = (wps[i]['latitude'] as num?)?.toDouble();
      final lng = (wps[i]['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final dist = (_distanceKm(myPos.latitude, myPos.longitude, lat, lng) ?? double.infinity) * 1000;
      if (dist <= 60) {
        setState(() {
          _currentWaypointIndex = i;
          _checkpointReached = true;
          _currentCheckpointLabel = wps[i]['label'] as String? ?? 'Waypoint ${i + 1}';
        });
        return;
      }
    }
  }

  void _pauseAtCheckpoint() {
    setState(() {
      _routePaused = true;
      _checkpointReached = false;
    });
    _showSnack('Paused at $_currentCheckpointLabel', color: DRDTheme.warningColor);
  }

  void _resumeFromCheckpoint() {
    setState(() {
      _routePaused = false;
      _checkpointReached = false;
      _currentWaypointIndex++;
    });
    _showSnack('Resuming route…', color: DRDTheme.successColor);
  }

  Widget _buildCheckpointOverlay(LatLng myPos) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DRDTheme.warningColor.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 16)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DRDTheme.warningColor.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.flag_rounded, color: DRDTheme.warningColor, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CHECKPOINT REACHED',
                        style: TextStyle(color: DRDTheme.warningColor, fontSize: 9,
                            fontWeight: FontWeight.w800, letterSpacing: 1.5, fontFamily: 'Poppins')),
                    const SizedBox(height: 2),
                    Text(_currentCheckpointLabel ?? 'Waypoint',
                        style: const TextStyle(color: Colors.white, fontSize: 13,
                            fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pauseAtCheckpoint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: DRDTheme.warningColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DRDTheme.warningColor.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pause_rounded, color: DRDTheme.warningColor, size: 16),
                        SizedBox(width: 6),
                        Text('PAUSE', style: TextStyle(color: DRDTheme.warningColor, fontSize: 11,
                            fontWeight: FontWeight.w800, fontFamily: 'Poppins')),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _resumeFromCheckpoint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: DRDTheme.successColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DRDTheme.successColor.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: DRDTheme.successColor, size: 16),
                        SizedBox(width: 6),
                        Text('CONTINUE', style: TextStyle(color: DRDTheme.successColor, fontSize: 11,
                            fontWeight: FontWeight.w800, fontFamily: 'Poppins')),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final auth = context.read<AuthProvider>();
    final loc = context.read<LocationProvider>();
    final nav = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
            SizedBox(width: 8),
            Text(
              'Sign Out',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
        content: Text(
          'End your field session and sign out?',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await loc.stopTracking();
      await auth.logout();
      if (mounted) nav.pushReplacementNamed('/login');
    }
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    int badge = 0,
    bool solid = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: solid ? color : color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: solid ? color : color.withValues(alpha: 0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: solid
                      ? color.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: solid ? 8 : 4,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: solid ? Colors.white : color, size: 18),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: solid ? Colors.white : color,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          if (badge > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: DRDTheme.dangerColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSOSButton() {
    return AnimatedBuilder(
      animation: _sosCtrl,
      builder: (_, _) {
        return GestureDetector(
          onTap: _showSOSDialog,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DRDTheme.dangerColor,
              boxShadow: [
                BoxShadow(
                  color: DRDTheme.dangerColor.withValues(
                    alpha: _sosActive ? 0.4 + 0.4 * _sosCtrl.value : 0.5,
                  ),
                  blurRadius: _sosActive ? 16 + 12 * _sosCtrl.value : 12,
                  spreadRadius: _sosActive ? 2 + 4 * _sosCtrl.value : 2,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sos,
                  color: Colors.white,
                  size: _sosActive ? 22 : 18,
                ),
                if (!_sosActive)
                  const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavFabs(LocationProvider loc, LatLng myPos) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'center',
          onPressed: () {
            if (_mapReady) _mapController.move(myPos, 16);
          },
          backgroundColor: DRDTheme.primaryColor,
          child: const Icon(Icons.my_location, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 6),
        FloatingActionButton.small(
          heroTag: 'zoomin',
          onPressed: () {
            if (_mapReady) {
              _mapController.move(
                _mapController.camera.center,
                _mapController.camera.zoom + 1,
              );
            }
          },
          backgroundColor: DRDTheme.surfaceColor,
          child: const Icon(Icons.add, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 6),
        FloatingActionButton.small(
          heroTag: 'zoomout',
          onPressed: () {
            if (_mapReady) {
              _mapController.move(
                _mapController.camera.center,
                _mapController.camera.zoom - 1,
              );
            }
          },
          backgroundColor: DRDTheme.surfaceColor,
          child: const Icon(Icons.remove, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 6),
        FloatingActionButton.small(
          heroTag: 'refresh',
          onPressed: _loadMapData,
          backgroundColor: DRDTheme.surfaceColor,
          child: const Icon(Icons.refresh, color: Colors.white, size: 18),
        ),
      ],
    );
  }

  // ── Bottom Panel ─────────────────────────────────────────────────────────────

  Widget _buildBottomPanel(AuthProvider auth, double panelHeight) {
    final unread = _messages.where((m) => m['is_read'] == false).length;
    return Container(
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle bar + header
          Container(
            width: double.infinity,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 13,
                  color: DRDTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'COMMS',
                  style: TextStyle(
                    color: DRDTheme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: DRDTheme.dangerColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${_messages.length} msgs',
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => setState(() => _panelOpen = false),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Comms content
          Expanded(child: _buildCommsTab(auth)),
        ],
      ),
    );
  }

  // ── Comms Tab ────────────────────────────────────────────────────────────────

  Widget _buildImageMessage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GestureDetector(
        onTap: () => _showFullImage(url),
        child: Image.network(
          url,
          width: 200,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 200,
              height: 120,
              decoration: BoxDecoration(
                color: DRDTheme.backgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                      : null,
                  color: DRDTheme.primaryColor,
                  strokeWidth: 2,
                ),
              ),
            );
          },
          errorBuilder: (ctx, err, stack) => Container(
            width: 200,
            height: 80,
            decoration: BoxDecoration(
              color: DRDTheme.backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38,
                  size: 28,
                ),
                SizedBox(height: 4),
                Text(
                  'Image unavailable',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.black87,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, err, stack) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 48,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 48,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommsTab(AuthProvider auth) {
    final myId = auth.user?.id ?? '';
    return Column(
      children: [
        // Messages list
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text(
                    'No messages',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _msgScroll,
                  reverse: false,
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final msg = _messages[i];
                    final fromMe = msg['from_user_id'] == myId;
                    final content = msg['content'] as String? ?? '';
                    final sender =
                        msg['from_user_name'] as String? ?? 'Unknown';
                    final priority = msg['priority'] as String? ?? 'normal';
                    final priorityColor =
                        {
                          'urgent': DRDTheme.dangerColor,
                          'high': DRDTheme.warningColor,
                          'normal': Colors.white54,
                          'low': Colors.white30,
                        }[priority] ??
                        Colors.white54;

                    final senderInitials = sender
                        .split(' ')
                        .where((w) => w.isNotEmpty)
                        .take(2)
                        .map((w) => w[0].toUpperCase())
                        .join();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: fromMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          // Avatar (left side for others)
                          if (!fromMe) ...[
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: DRDTheme.primaryColor,
                              ),
                              child: Center(
                                child: Text(
                                  senderInitials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                              decoration: BoxDecoration(
                                color: fromMe
                                    ? DRDTheme.primaryColor.withValues(
                                        alpha: 0.25,
                                      )
                                    : DRDTheme.backgroundColor.withValues(
                                        alpha: 0.7,
                                      ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: fromMe
                                      ? DRDTheme.primaryColor.withValues(
                                          alpha: 0.4,
                                        )
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: fromMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!fromMe)
                                    Text(
                                      sender,
                                      style: TextStyle(
                                        color: DRDTheme.primaryColor.withValues(
                                          alpha: 0.9,
                                        ),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  if (!fromMe) const SizedBox(height: 2),
                                  // Image message
                                  if (content.startsWith('[evidence_image]'))
                                    _buildImageMessage(
                                      content.replaceFirst(
                                        '[evidence_image]',
                                        '',
                                      ),
                                    )
                                  else
                                    Text(
                                      content,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (priority != 'normal') ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      priority.toUpperCase(),
                                      style: TextStyle(
                                        color: priorityColor,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        // Send bar – SafeArea prevents overlap with system nav bar
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Message unit / command…',
                      hintStyle: const TextStyle(
                        color: Colors.white30,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: DRDTheme.backgroundColor.withValues(
                        alpha: 0.5,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: DRDTheme.primaryColor,
                        ),
                      ),
                    ),
                    onSubmitted: (v) => _sendMessage(v),
                  ),
                ),
                const SizedBox(width: 6),
                // Camera button
                GestureDetector(
                  onTap: _sending ? null : _pickAndSendChatImage,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: DRDTheme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: DRDTheme.primaryColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: DRDTheme.primaryColor,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Send button
                GestureDetector(
                  onTap: () => _sendMessage(_msgCtrl.text),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _sending ? Colors.white10 : DRDTheme.primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ), // SafeArea
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        backgroundColor: color ?? DRDTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _colorFromHex(dynamic value) {
    if (value is String && value.startsWith('#')) {
      try {
        return Color(int.parse(value.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return DRDTheme.warningColor;
  }

  Color _poiColor(String poiType) {
    switch (poiType.toLowerCase()) {
      case 'hospital':
      case 'medical':
        return const Color(0xFFEF4444);
      case 'base':
      case 'command':
        return const Color(0xFF3B82F6);
      case 'supply':
        return const Color(0xFFF97316);
      case 'vehicle':
        return const Color(0xFF84CC16);
      case 'meeting':
        return const Color(0xFFEC4899);
      case 'extraction':
        return const Color(0xFFEAB308);
      case 'observation':
        return const Color(0xFF64748B);
      case 'police':
        return const Color(0xFF06B6D4);
      default:
        return const Color(0xFFA855F7);
    }
  }

  IconData _poiIcon(String poiType) {
    switch (poiType.toLowerCase()) {
      case 'hospital':
      case 'medical':
        return Icons.local_hospital;
      case 'base':
      case 'command':
        return Icons.shield;
      case 'supply':
        return Icons.inventory_2;
      case 'vehicle':
        return Icons.directions_car;
      case 'meeting':
        return Icons.groups;
      case 'extraction':
        return Icons.flight_takeoff;
      case 'observation':
        return Icons.visibility;
      case 'police':
        return Icons.local_police;
      default:
        return Icons.place;
    }
  }

  IconData _iconForMapType(TacMapType type) {
    return {
      TacMapType.tactical: Icons.dark_mode_outlined,
      TacMapType.standard: Icons.map_outlined,
      TacMapType.satellite: Icons.satellite_alt_outlined,
      TacMapType.terrain: Icons.terrain_outlined,
      TacMapType.hybrid: Icons.layers_outlined,
    }[type]!;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _sosCtrl.dispose();
    _refreshTimer?.cancel();
    _locChannel?.sink.close();
    _msgChannel?.sink.close();
    _evtChannel?.sink.close();
    _msgCtrl.dispose();
    _msgScroll.dispose();
    super.dispose();
  }
}
