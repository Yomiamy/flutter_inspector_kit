import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A standard card widget for displaying error messages with a retry button.
class ErrorCard extends StatelessWidget {
  const ErrorCard({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: ThemePadding.paddingAll16,
        child: Card(
          child: Padding(
            padding: ThemePadding.paddingAll16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error,
                  color: ThemeColor.colorF44336,
                  size: ThemeSize.size48,
                ),
                const SizedBox(height: ThemeSpacing.spacing16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: ThemeTextStyle.boldStyle,
                ),
                const SizedBox(height: ThemeSpacing.spacing16),
                ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
