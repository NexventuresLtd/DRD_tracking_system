import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("DOD")),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.pushNamed(context, '/second');
          },
          child: 
          Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.map, size: 48),
              SizedBox(height: 8),
              Text("Go to Map"),
            ],
          )
        ),
      ),
    );
  }
}