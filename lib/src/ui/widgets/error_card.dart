import 'package:flutter/material.dart';

import '../theme/inspector_theme.dart';

/// A standard card widget for displaying error messages with a retry button.
class ErrorCard extends StatelessWidget {
  const ErrorCard({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: InspectorTheme.paddingLg,
        child: Card(
          child: Padding(
            padding: InspectorTheme.paddingLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error,
                  color: InspectorTheme.errorColor,
                  size: 48,
                ),
                const SizedBox(height: InspectorTheme.spacingLg),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: InspectorTheme.spacingLg),
                ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
