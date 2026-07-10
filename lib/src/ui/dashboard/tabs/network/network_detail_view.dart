import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/network_entry.dart';
import '../../../../utils/network_formatters.dart';
import '../../../../utils/share_text.dart';
import '../../../widgets/detail_section.dart';
import '../../../widgets/key_value_table.dart';
import '../../../theme/theme.dart';

/// Actions exposed in the detail view's share menu.
enum _ShareAction { curl, text, share }

/// A full-screen, structured view of a single [NetworkEntry], showing request
/// and response sections plus sharing (cURL / plain text / system share).
class NetworkDetailView extends StatelessWidget {
  const NetworkDetailView({
    required this.entry,
    this.redactSensitiveData = true,
    super.key,
  });

  final NetworkEntry entry;

  /// Whether share/export paths mask sensitive headers. Mirrors
  /// [FlutterInspector.redactSensitiveData]. Defaults to `true` (secure by
  /// default) so a NetworkDetailView built without this value still redacts.
  final bool redactSensitiveData;

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
        padding: ThemePadding.paddingAll12,
        children: [
          _generalSection(context),
          if (entry.queryParameters.isNotEmpty)
            DetailSection(
              title: 'Query Parameters',
              child: KeyValueTable(data: entry.queryParameters),
            ),
          DetailSection(
            title: 'Request Headers',
            child: KeyValueTable(data: entry.requestHeaders),
          ),
          if (_hasBody(entry.requestBody))
            _bodySection(
              context,
              'Request Body',
              entry.requestBody!,
              entry.isRequestJson,
            ),
          DetailSection(
            title: 'Response Headers',
            child: KeyValueTable(data: entry.responseHeaders),
          ),
          if (_hasBody(entry.responseBody))
            _bodySection(
              context,
              'Response Body',
              entry.responseBody!,
              entry.isResponseJson,
            ),
          if (entry.error != null ||
              entry.errorType != null ||
              (entry.errorStackTrace != null &&
                  entry.errorStackTrace!.isNotEmpty))
            _exceptionDetailsSection(context),
        ],
      ),
    );
  }

  Widget _generalSection(BuildContext context) {
    final statusColor = ThemeColor.statusColor(
      entry.statusCode,
      hasError: entry.error != null,
    );
    return DetailSection(
      title: 'General',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailKeyValueRow.text('Method', entry.method),
          DetailKeyValueRow.text('URL', entry.url),
          DetailKeyValueRow(
            label: 'Status',
            valueWidget: SelectableText(
              entry.isComplete ? '${entry.statusCode ?? '-'}' : 'Pending',
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
            ),
          ),
          DetailKeyValueRow.text(
            'Duration',
            '${entry.duration?.inMilliseconds ?? '-'} ms',
          ),
          DetailKeyValueRow.text(
            'Request size',
            formatBytes(entry.requestSizeBytes),
          ),
          DetailKeyValueRow.text(
            'Response size',
            formatBytes(entry.responseSizeBytes),
          ),
          if (entry.isTruncated)
            Padding(
              padding: const EdgeInsets.only(top: ThemeSpacing.spacing4),
              child: Text(
                '⚠ Body truncated — size reflects the truncated value',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          DetailKeyValueRow.text('Time', entry.timestamp.toIso8601String()),
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
    return DetailSection(
      title: title,
      child: Container(
        width: double.infinity,
        padding: ThemePadding.paddingAll8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(ThemeRadius.radius4),
        ),
        child: SelectableText(rendered, style: ThemeTextStyle.monospaceStyle),
      ),
    );
  }

  Widget _exceptionDetailsSection(BuildContext context) {
    return DetailSection(
      title: 'Exception Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.errorType != null) ...[
            if (entry.statusCode == null)
              DetailKeyValueRow.text(
                'Kind',
                '傳輸層失敗 (transport failure — request did not reach server)',
              )
            else
              DetailKeyValueRow.text(
                'Kind',
                'Server 錯誤回應 (server responded with error)',
              ),
            DetailKeyValueRow.text('Error Type', entry.errorType!.name),
          ],
          if (entry.error != null)
            DetailKeyValueRow(
              label: 'Error',
              valueWidget: SelectableText(
                entry.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (entry.errorStackTrace != null &&
              entry.errorStackTrace!.isNotEmpty) ...[
            const SizedBox(height: ThemeSpacing.spacing12),
            Text(
              'Stack Trace',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: ThemeSpacing.spacing8),
            Container(
              width: double.infinity,
              padding: ThemePadding.paddingAll8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(ThemeRadius.radius4),
              ),
              child: SelectableText(
                entry.errorStackTrace!,
                style: ThemeTextStyle.monospaceStyle,
              ),
            ),
          ],
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
        await Clipboard.setData(
          ClipboardData(text: buildCurl(entry, redact: redactSensitiveData)),
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('cURL copied to clipboard')),
        );
      case _ShareAction.text:
        await Clipboard.setData(
          ClipboardData(
            text: buildPlainText(entry, redact: redactSensitiveData),
          ),
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Details copied to clipboard')),
        );
      case _ShareAction.share:
        try {
          await shareText(buildPlainText(entry, redact: redactSensitiveData));
        } catch (_) {
          // Fallback to clipboard when the platform has no share sheet.
          await Clipboard.setData(
            ClipboardData(
              text: buildPlainText(entry, redact: redactSensitiveData),
            ),
          );
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Share unavailable — copied to clipboard'),
            ),
          );
        }
    }
  }
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
              width: ThemeSize.size18,
              height: ThemeSize.size18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.replay),
    );
  }

  Future<void> _resend(BuildContext context) async {
    final dio = widget.entry.sourceDio?.target;
    if (dio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resend failed: source Dio not available'),
        ),
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
      messenger.showSnackBar(const SnackBar(content: Text('Request resent')));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        messenger.showSnackBar(const SnackBar(content: Text('Request resent')));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Resend failed')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Resend failed')));
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
  }
}
