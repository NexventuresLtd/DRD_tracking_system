import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';
import '../../config/theme.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  final ApiService _api = ApiService();
  bool _isSending = false;
  bool _sosActive = false;
  String _selectedType = 'help';

  Future<void> _sendSOS() async {
    final auth = context.read<AuthProvider>();
    final loc = context.read<LocationProvider>();
    setState(() => _isSending = true);

    try {
      await _api.post('/events', {
        'event_type': 'FLAG',
        'user_id': auth.user?.id,
        'team_id': auth.user?.teamId,
        'description':
            'SOS alert — ${auth.user?.fullName ?? 'Field Unit'} needs assistance',
        'location_lat': loc.latitude,
        'location_lng': loc.longitude,
        'severity': 'high',
        'event_metadata': {'sos_type': _selectedType},
      });

      if (!mounted) return;
      setState(() {
        _isSending = false;
        _sosActive = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send SOS. Try again.'),
          backgroundColor: DRDTheme.dangerColor,
        ),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS signal sent! Command has been alerted.'),
          backgroundColor: DRDTheme.dangerColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('EMERGENCY SOS'),
        backgroundColor: DRDTheme.dangerColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // SOS Indicator
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _sosActive
                    ? DRDTheme.dangerColor.withValues(alpha: 0.2)
                    : DRDTheme.dangerColor.withValues(alpha: 0.1),
                border: Border.all(color: DRDTheme.dangerColor, width: 3),
              ),
              child: Center(
                child: _sosActive
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sos,
                            size: 50,
                            color: DRDTheme.dangerColor,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: DRDTheme.dangerColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : const Icon(
                        Icons.sos,
                        size: 50,
                        color: DRDTheme.dangerColor,
                      ),
              ),
            ),
            const SizedBox(height: 32),

            // SOS Type Selection
            const Text(
              'SELECT ALERT TYPE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSOSTypeCard(
                    'MEDICAL',
                    Icons.medical_services,
                    DRDTheme.dangerColor,
                    _selectedType == 'medical',
                    () => setState(() => _selectedType = 'medical'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSOSTypeCard(
                    'THREAT',
                    Icons.warning,
                    DRDTheme.warningColor,
                    _selectedType == 'threat',
                    () => setState(() => _selectedType = 'threat'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSOSTypeCard(
                    'EXTRACTION',
                    Icons.flight_takeoff,
                    DRDTheme.infoColor,
                    _selectedType == 'extraction',
                    () => setState(() => _selectedType = 'extraction'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSOSTypeCard(
                    'OTHER',
                    Icons.help,
                    DRDTheme.accentColor,
                    _selectedType == 'other',
                    () => setState(() => _selectedType = 'other'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // SOS Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _sosActive ? null : (_isSending ? null : _sendSOS),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _sosActive
                      ? Colors.grey
                      : DRDTheme.dangerColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSending
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _sosActive
                            ? 'SOS ACTIVE - HELP IS COMING'
                            : 'SEND EMERGENCY SOS',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSTypeCard(
    String label,
    IconData icon,
    Color color,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : DRDTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
