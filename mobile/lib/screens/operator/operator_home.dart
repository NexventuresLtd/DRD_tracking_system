import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';

class OperatorHome extends StatelessWidget {
  const OperatorHome({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        title: const Text(
          'PLANNING OFFICER',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'Settings & Permissions',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined, size: 20),
            tooltip: 'Sign out',
            onPressed: () async {
              final nav = Navigator.of(context);
              await authProvider.logout();
              if (context.mounted) nav.pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon badge
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DRDTheme.primaryColor.withValues(alpha: 0.1),
                  border: Border.all(
                    color: DRDTheme.primaryColor.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.desktop_windows_outlined,
                  color: DRDTheme.primaryColor,
                  size: 38,
                ),
              ),
              const SizedBox(height: 28),

              const Text(
                'WEB DASHBOARD REQUIRED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'The Planning Officer role is designed for the DRD web operations portal.\n\n'
                'Open the portal on a desktop or laptop browser to access mission planning, '
                'evidence review, and briefing tools.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  height: 1.65,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 32),

              // Server URL hint
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                decoration: BoxDecoration(
                  color: DRDTheme.primaryColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: DRDTheme.primaryColor.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.link_outlined,
                        color: DRDTheme.primaryColor, size: 15),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        AppConstants.baseUrl,
                        style: TextStyle(
                          color: DRDTheme.primaryColor.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Sign out button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await authProvider.logout();
                    if (context.mounted) nav.pushReplacementNamed('/login');
                  },
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text(
                    'SIGN OUT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
}
