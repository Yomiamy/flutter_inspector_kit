import 'package:flutter/material.dart';

/// Renders a map as a compact two-column key-value table. Shows a muted
/// placeholder when [data] is null or empty.
class KeyValueTable extends StatelessWidget {
  const KeyValueTable({
    required this.data,
    this.emptyLabel = '(none)',
    super.key,
  });

  /// The key-value pairs to display. Values are rendered via `toString()`.
  final Map<String, dynamic>? data;

  /// Text shown when there is nothing to display.
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final entries = data?.entries.toList() ?? const [];
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          emptyLabel,
          style: TextStyle(
            color: Theme.of(context).disabledColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final keyStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: SizedBox(
                    width: 140,
                    child: SelectableText('${e.key}:', style: keyStyle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: SelectableText('${e.value}')),
              ],
            ),
          ),
      ],
    );
  }
}
