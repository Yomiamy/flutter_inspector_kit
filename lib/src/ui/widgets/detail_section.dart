import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A standard card container for sections in detail views.
class DetailSection extends StatelessWidget {
  const DetailSection({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ThemeSpacing.spacing12),
      child: Padding(
        padding: ThemePadding.paddingAll12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: ThemeSpacing.spacing8),
            child,
          ],
        ),
      ),
    );
  }
}

/// A standard two-column key-value row for detail views.
class DetailKeyValueRow extends StatelessWidget {
  const DetailKeyValueRow({
    required this.label,
    required this.valueWidget,
    super.key,
  });

  DetailKeyValueRow.text(String label, String value, {Key? key})
    : this(label: label, valueWidget: SelectableText(value), key: key);

  final String label;
  final Widget valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ThemeSize.size120,
            child: Text(
              '$label:',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: ThemeSpacing.spacing8),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
