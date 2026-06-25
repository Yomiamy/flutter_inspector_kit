import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/network_entry.dart';
import '../../../../utils/network_formatters.dart';
import '../../../../utils/share_text.dart';
import '../../../widgets/key_value_table.dart';

/// Actions exposed in the detail view's share menu.
enum _ShareAction { curl, text, share }

/// A full-screen, structured view of a single [NetworkEntry], showing request
/// and response sections plus sharing (cURL / plain text / system share).
class NetworkDetailView extends StatelessWidget {
  const NetworkDetailView({required this.entry, super.key});

  final NetworkEntry entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('[${entry.method}] ${_shortUrl(entry.url)}'),
        actions: [
          _ResendAction(entry: entry),
          PopupMenuButton<_ShareAction>(
            icon: const Icon(Icons.share),
            onSelected: (action) => _onShare(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ShareAction.curl,
                child: Text('Copy as cURL'),
              ),
              PopupMenuItem(
                value: _ShareAction.text,
                child: Text('Copy as text'),
              ),
              PopupMenuItem(value: _ShareAction.share, child: Text('Share…')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _generalSection(context),
          if (entry.queryParameters.isNotEmpty)
            _section(
              context,
              'Query Parameters',
              KeyValueTable(data: entry.queryParameters),
            ),
          _section(
            context,
            'Request Headers',
            KeyValueTable(data: entry.requestHeaders),
          ),
          if (_hasBody(entry.requestBody))
            _bodySection(
              context,
              'Request Body',
              entry.requestBody!,
              entry.isRequestJson,
            ),
          _section(
            context,
            'Response Headers',
            KeyValueTable(data: entry.responseHeaders),
          ),
          if (_hasBody(entry.responseBody))
            _bodySection(
              context,
              'Response Body',
              entry.responseBody!,
              entry.isResponseJson,
            ),
          if (entry.error != null) _errorSection(context),
        ],
      ),
    );
  }

  Widget _generalSection(BuildContext context) {
    final statusColor = statusColorFor(entry.statusCode, entry.error != null);
    return _section(
      context,
      'General',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(context, 'Method', entry.method),
          _kv(context, 'URL', entry.url),
          _kvWidget(
            context,
            'Status',
            SelectableText(
              entry.isComplete ? '${entry.statusCode ?? '-'}' : 'Pending',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _kv(
            context,
            'Duration',
            '${entry.duration?.inMilliseconds ?? '-'} ms',
          ),
          _kv(context, 'Request size', formatBytes(entry.requestSizeBytes)),
          _kv(context, 'Response size', formatBytes(entry.responseSizeBytes)),
          if (entry.isTruncated)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '⚠ Body truncated — size reflects the truncated value',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          _kv(context, 'Time', entry.timestamp.toIso8601String()),
        ],
      ),
    );
  }

  Widget _bodySection(
    BuildContext context,
    String title,
    String body,
    bool isJson,
  ) {
    final rendered = isJson ? prettyJson(body) : body;
    return _section(
      context,
      title,
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          rendered,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }

  Widget _errorSection(BuildContext context) {
    return _section(
      context,
      'Error',
      SelectableText(
        entry.error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kv(
    BuildContext context,
    String key,
    String value,
  ) {
    return _kvWidget(context, key, SelectableText(value));
  }

  Widget _kvWidget(
    BuildContext context,
    String key,
    Widget valueWidget,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$key:',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  bool _hasBody(String? body) => body != null && body.isNotEmpty;

  String _shortUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri?.path.isNotEmpty == true ? uri!.path : url;
  }

  Future<void> _onShare(BuildContext context, _ShareAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _ShareAction.curl:
        await Clipboard.setData(ClipboardData(text: buildCurl(entry)));
        messenger.showSnackBar(
          const SnackBar(content: Text('cURL copied to clipboard')),
        );
      case _ShareAction.text:
        await Clipboard.setData(ClipboardData(text: buildPlainText(entry)));
        messenger.showSnackBar(
          const SnackBar(content: Text('Details copied to clipboard')),
        );
      case _ShareAction.share:
        try {
          await shareText(buildPlainText(entry));
        } catch (_) {
          // Fallback to clipboard when the platform has no share sheet.
          await Clipboard.setData(ClipboardData(text: buildPlainText(entry)));
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Share unavailable — copied to clipboard'),
            ),
          );
        }
    }
  }
}

/// Returns a color representing the HTTP status semantics.
Color statusColorFor(int? statusCode, bool hasError) {
  if (hasError && statusCode == null) return Colors.red;
  if (statusCode == null) return Colors.grey;
  if (statusCode >= 500) return Colors.red;
  if (statusCode >= 400) return Colors.orange;
  if (statusCode >= 300) return Colors.blue;
  if (statusCode >= 200) return Colors.green;
  return Colors.grey;
}

// ---------------------------------------------------------------------------
// Resend action – a small StatefulWidget so only it holds loading state.
// ---------------------------------------------------------------------------
class _ResendAction extends StatefulWidget {
  const _ResendAction({required this.entry});

  final NetworkEntry entry;

  @override
  State<_ResendAction> createState() => _ResendActionState();
}

class _ResendActionState extends State<_ResendAction> {
  bool _inFlight = false;

  bool get _disabled =>
      widget.entry.sourceDio?.target == null ||
      !widget.entry.isComplete ||
      widget.entry.isRequestTruncated ||
      _inFlight;

  @override
  Widget build(BuildContext context) {
    final String tooltip;
    if (widget.entry.isRequestTruncated) {
      tooltip = 'Cannot resend: request body truncated';
    } else if (widget.entry.sourceDio?.target == null) {
      tooltip = 'Cannot resend: source Dio not available';
    } else {
      tooltip = 'Resend';
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: _disabled ? null : () => _resend(context),
      icon: _inFlight
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.replay),
    );
  }

  Future<void> _resend(BuildContext context) async {
    final dio = widget.entry.sourceDio?.target;
    if (dio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resend failed: source Dio not available')),
      );
      return;
    }
    setState(() => _inFlight = true);
    final messenger = ScaffoldMessenger.of(context);
    final req = buildReplayRequest(widget.entry);
    try {
      await dio.request<dynamic>(
        req.url,
        data: req.body,
        options: Options(
          method: req.method,
          headers: req.headers,
          extra: <String, dynamic>{'_inspector_is_replay': true},
        ),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Request resent')),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Request resent')),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Resend failed')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Resend failed')),
      );
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
  }
}
