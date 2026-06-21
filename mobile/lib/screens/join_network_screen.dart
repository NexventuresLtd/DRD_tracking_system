import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class JoinNetworkScreen extends StatefulWidget {
  const JoinNetworkScreen({super.key});

  @override
  State<JoinNetworkScreen> createState() => _JoinNetworkScreenState();
}

class _JoinNetworkScreenState extends State<JoinNetworkScreen> {
  bool _scanning = false;
  bool _joining = false;
  String? _error;
  Map<String, dynamic>? _joinResult;
  final ApiService _api = ApiService();

  Future<void> _handleQr(String token) async {
    setState(() { _joining = true; _error = null; _scanning = false; _joinResult = null; });
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final res = await _api.post('/invites/$token/join', {});
      if (res != null) {
        await authProvider.checkAuthStatus();
        if (!mounted) return;
        setState(() { _joining = false; _joinResult = Map<String, dynamic>.from(res); });
      } else {
        setState(() { _error = 'Could not join network. Try again or contact your commander.'; _joining = false; });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _joining = false;
      });
    }
  }

  void _proceed() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    Navigator.pushReplacementNamed(context, authProvider.getHomeRoute());
  }

  Future<void> _logout() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C1A),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('NOT ASSIGNED',
                      style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 2, fontFamily: 'Poppins')),
                  ]),
                  TextButton(
                    onPressed: _logout,
                    child: const Text('SIGN OUT',
                      style: TextStyle(color: Colors.white38, fontSize: 10,
                        letterSpacing: 1.5, fontFamily: 'Poppins')),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _joinResult != null
                ? _buildSuccess()
                : _scanning
                  ? _buildScanner()
                  : _buildWaitingView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lock icon
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A1628),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Icon(Icons.lock_outline_rounded, size: 44, color: Color(0xFFF59E0B)),
          ),
          const SizedBox(height: 28),

          const Text(
            'ACCESS RESTRICTED',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
              letterSpacing: 2, fontFamily: 'Poppins'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Your account is not part of any network.\nYou need to join a network before you can access the system.',
            style: TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Poppins', height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1628),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, color: Color(0xFF3B82F6), size: 14),
                  SizedBox(width: 8),
                  Text('HOW TO JOIN', style: TextStyle(color: Color(0xFF3B82F6),
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, fontFamily: 'Poppins')),
                ]),
                SizedBox(height: 12),
                _StepRow(n: '1', text: 'Contact your commander or system administrator'),
                SizedBox(height: 8),
                _StepRow(n: '2', text: 'Ask them to generate a QR invite from the web dashboard'),
                SizedBox(height: 8),
                _StepRow(n: '3', text: 'Tap SCAN QR below and point your camera at the code'),
              ],
            ),
          ),
          const SizedBox(height: 32),

          if (_error != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: DRDTheme.dangerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DRDTheme.dangerColor.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: DRDTheme.dangerColor, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!,
                  style: const TextStyle(color: DRDTheme.dangerColor, fontSize: 11, fontFamily: 'Poppins'))),
              ]),
            ),
          ],

          if (_joining)
            const Column(children: [
              CircularProgressIndicator(color: DRDTheme.primaryColor),
              SizedBox(height: 12),
              Text('Joining network…',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Poppins')),
            ])
          else
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => setState(() { _scanning = true; _error = null; }),
                icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                label: const Text('SCAN QR TO JOIN',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    letterSpacing: 2, fontFamily: 'Poppins')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DRDTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  shadowColor: DRDTheme.primaryColor.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    final teamName = _joinResult?['team_name'] as String?;
    final role = (_joinResult?['role'] as String? ?? 'field_unit').replaceAll('_', ' ').toUpperCase();
    final tmr = (_joinResult?['team_member_role'] as String? ?? 'member').toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A1628),
              border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.check_circle_outline_rounded, size: 48, color: Color(0xFF22C55E)),
          ),
          const SizedBox(height: 24),
          const Text('NETWORK JOINED',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
              letterSpacing: 2, fontFamily: 'Poppins')),
          const SizedBox(height: 8),
          Text(teamName != null ? 'You have been assigned to $teamName' : 'Your account has been activated.',
            style: const TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Poppins', height: 1.5),
            textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1628),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(children: [
              _infoRow(Icons.shield_outlined, 'SYSTEM ROLE', role, const Color(0xFF3B82F6)),
              if (teamName != null) ...[
                const SizedBox(height: 10),
                _infoRow(Icons.group_outlined, 'TEAM', teamName, const Color(0xFF22C55E)),
                const SizedBox(height: 10),
                _infoRow(Icons.military_tech_outlined, 'TEAM ROLE', tmr, const Color(0xFFF59E0B)),
              ],
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _proceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('ENTER SYSTEM',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  letterSpacing: 2, fontFamily: 'Poppins')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 1.5, fontFamily: 'Poppins')),
        Text(value, style: TextStyle(color: color, fontSize: 12,
          fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
      ]),
    ]);
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white54),
              onPressed: () => setState(() => _scanning = false),
            ),
            const Expanded(
              child: Text('SCAN NETWORK QR',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
                  fontSize: 13, letterSpacing: 2, fontFamily: 'Poppins'),
                textAlign: TextAlign.center),
            ),
            const SizedBox(width: 40),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MobileScanner(
                onDetect: (capture) {
                  final raw = capture.barcodes.firstOrNull?.rawValue;
                  if (raw == null) return;
                  final uri = Uri.tryParse(raw);
                  if (uri == null) return;
                  final token = uri.queryParameters['token'];
                  if (token != null && token.isNotEmpty) {
                    _handleQr(token);
                  }
                },
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Point camera at the QR code shown on the commander\'s web dashboard',
            style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Poppins'),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String n;
  final String text;
  const _StepRow({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: DRDTheme.primaryColor.withValues(alpha: 0.15),
          border: Border.all(color: DRDTheme.primaryColor.withValues(alpha: 0.4)),
        ),
        child: Center(child: Text(n,
          style: const TextStyle(color: DRDTheme.primaryColor, fontSize: 10,
            fontWeight: FontWeight.w700, fontFamily: 'Poppins'))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text,
        style: const TextStyle(color: Colors.white70, fontSize: 12,
          fontFamily: 'Poppins', height: 1.4))),
    ]);
  }
}
