import 'package:flutter/material.dart';

import '../theme/theme_color.dart';

/// Asks the user to confirm an action, returning true only if they accept.
///
/// Cancelling, tapping the barrier, or dismissing with the back gesture all
/// resolve to false — the `bool?` from [showDialog] is collapsed here so
/// callers never have to write `?? false`.
///
/// [destructive] only recolors the confirm action; it adds no second code path.
Future<bool> showInspectorConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: ThemeColor.colorF44336)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
