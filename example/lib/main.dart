import 'package:flutter/material.dart';
import 'package:flutter_inspector/flutter_inspector.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_inspector Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Reference the package's public API so the example exercises the import.
    const inspector = FlutterInspector();

    return Scaffold(
      appBar: AppBar(title: const Text('flutter_inspector')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('flutter_inspector example'),
            const SizedBox(height: 8),
            Text('package version: ${FlutterInspector.version}'),
            const SizedBox(height: 8),
            Text('instance: $inspector'),
          ],
        ),
      ),
    );
  }
}
