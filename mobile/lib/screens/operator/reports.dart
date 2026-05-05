import 'package:flutter/material.dart';
import '../../config/theme.dart';

class Reports extends StatelessWidget {
  const Reports({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(title: const Text('REPORTS')),
      body: const Center(
        child: Text('Reports Screen', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}