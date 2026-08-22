import 'package:flutter/material.dart';

import '../../../../models/key_value_browser_source.dart';

/// Prompts for a new value for [entry], validated against its original type.
///
/// Returns the parsed value, or null if the user cancelled. Invalid input keeps
/// the dialog open with an error rather than resolving — so a caller that gets
/// null can treat it purely as "cancelled".
Future<Object?> showKeyValueEditDialog(
  BuildContext context, {
  required KeyValueEntry entry,
}) {
  return showDialog<Object?>(
    context: context,
    builder: (context) => _KeyValueEditDialog(entry: entry),
  );
}

class _KeyValueEditDialog extends StatefulWidget {
  const _KeyValueEditDialog({required this.entry});

  final KeyValueEntry entry;

  @override
  State<_KeyValueEditDialog> createState() => _KeyValueEditDialogState();
}

class _KeyValueEditDialogState extends State<_KeyValueEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: _initialText(),
  );
  String? _error;

  String _initialText() {
    final value = widget.entry.value;
    // stringList is edited as one entry per line, matching parseKeyValueInput.
    if (value is List) return value.join('\n');
    return '${value ?? ''}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = parseKeyValueInput(_controller.text, widget.entry.type);
    if (parsed == null) {
      setState(() => _error = 'Not a valid ${widget.entry.type.name} value');
      return;
    }
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.entry.key}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.entry.type == KeyValueType.stringList ? null : 1,
        decoration: InputDecoration(
          labelText: widget.entry.type.name,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Next')),
      ],
    );
  }
}
