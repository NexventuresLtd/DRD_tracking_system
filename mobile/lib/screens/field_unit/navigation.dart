import 'package:flutter/material.dart';
import '../../config/theme.dart';

class Navigation extends StatelessWidget {
  const Navigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(title: const Text('NAVIGATION')),
      body: const Center(
        child: Text('Navigation Screen - Map View Coming Soon', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}