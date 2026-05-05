import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';

class FieldSquadView extends StatefulWidget {
  const FieldSquadView({super.key});

  @override
  State<FieldSquadView> createState() => _FieldSquadViewState();
}

class _FieldSquadViewState extends State<FieldSquadView> {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  List<Map<String, dynamic>> _squadMembers = [];
  WebSocketChannel? _locWs;
  Timer? _refreshTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSquadData();
      _connectWS();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadSquadData());
  }

  Future<void> _loadSquadData() async {
    if (!mounted) return;
    try {
      final user = context.read<AuthProvider>().user;
      if (user?.teamId == null) return;

      final response = await _api.get('/locations?team_id=${user!.teamId}');
      if (!mounted) return;

      final List<Map<String, dynamic>> members = (response is List)
          ? List<Map<String, dynamic>>.from(response)
          : [];

      setState(() {
        _squadMembers = members;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading squad data: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _connectWS() async {
    final token = await _storage.getToken();
    if (token == null) return;
    try {
      _locWs = WebSocketChannel.connect(Uri.parse('${AppConstants.wsUrl}/locations?token=$token'));
      _locWs!.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            final d = (data['data'] ?? data) as Map<String, dynamic>;
            final uid = d['user_id'] as String?;
            if (uid == null || !mounted) return;

            final user = context.read<AuthProvider>().user;
            final senderTeam = d['team_id'] as String?;
            if (senderTeam != user?.teamId) return;

            setState(() {
              final idx = _squadMembers.indexWhere((l) => l['user_id'] == uid);
              if (idx >= 0) {
                _squadMembers[idx] = {..._squadMembers[idx], ...d};
              } else {
                _squadMembers.add(Map<String, dynamic>.from(d));
              }
            });
          } catch (e) {
            debugPrint('WS parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('WS error: $error');
          _locWs?.sink.close();
          _locWs = null;
          Future.delayed(const Duration(seconds: 3), _connectWS);
        },
        onDone: () {
          debugPrint('WS closed');
          _locWs = null;
          if (mounted) {
            Future.delayed(const Duration(seconds: 3), _connectWS);
          }
        },
      );
    } catch (e) {
      debugPrint('WS connection error: $e');
      Future.delayed(const Duration(seconds: 3), _connectWS);
    }
  }

  Color _getStatusColor(String? status) {
    if (status == 'active') return DRDTheme.successColor;
    if (status == 'stale') return DRDTheme.warningColor;
    return DRDTheme.dangerColor;
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return 'Unknown';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'Now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  void dispose() {
    _locWs?.sink.close();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_squadMembers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No squad members found',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadSquadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DRDTheme.primaryColor,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSquadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _squadMembers.length,
        itemBuilder: (context, index) {
          final member = _squadMembers[index];
          final status = member['status'] as String? ?? 'offline';
          final statusColor = _getStatusColor(status);
          final name = member['user_name'] as String? ?? 'Unknown';
          final lastUpdate = member['recorded_at'] as String?;
          final lat = member['latitude'] as double?;
          final lng = member['longitude'] as double?;
          final speed = (member['speed'] as num?)?.toDouble() ?? 0.0;
          final heading = (member['heading'] as num?)?.toDouble() ?? 0.0;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: DRDTheme.surfaceColor,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                        child: Center(
                          child: Text(
                            name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Last seen: ${_formatTime(lastUpdate)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.2),
                          border: Border.all(color: statusColor, width: 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              speed.toStringAsFixed(1),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'km/h',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildInfoChip('LAT', lat?.toStringAsFixed(4) ?? 'N/A'),
                        _buildInfoChip('LNG', lng?.toStringAsFixed(4) ?? 'N/A'),
                        _buildInfoChip('HDG', '${heading.toStringAsFixed(0)}°'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
