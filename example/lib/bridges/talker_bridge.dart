import 'package:flutter_inspector_kit/flutter_inspector_kit.dart' as kit;
import 'package:talker/talker.dart';

/// Forwards one talker record to [inspector] as exactly one log entry.
///
/// Shared by all three [TalkerObserver] callbacks: [TalkerError] and
/// [TalkerException] are [TalkerData] too, and carry their own level.
void forwardTalkerData(kit.FlutterInspector inspector, TalkerData data) {
  final message = [
    data.message,
    data.exception,
    data.error,
  ].nonNulls.where((p) => '$p'.isNotEmpty).join('\n');
  inspector.log(
    message,
    level: _toInspectorLevel(data.logLevel),
    stackTrace: data.stackTrace?.toString(),
  );
}

// Exhaustive switch: a level talker adds later fails to compile here instead
// of being filed silently. A record without a level is debug, as in talker.
kit.LogLevel _toInspectorLevel(LogLevel? level) => switch (level) {
  LogLevel.error || LogLevel.critical => kit.LogLevel.error,
  LogLevel.warning => kit.LogLevel.warning,
  LogLevel.info => kit.LogLevel.info,
  LogLevel.debug || null => kit.LogLevel.debug,
  LogLevel.verbose => kit.LogLevel.verbose,
};

/// Routes every talker callback into [forwardTalkerData].
///
/// talker has a single observer slot: if you already use one, call
/// [forwardTalkerData] from it instead of replacing it.
class InspectorTalkerObserver extends TalkerObserver {
  const InspectorTalkerObserver(this._inspector);

  final kit.FlutterInspector _inspector;

  @override
  void onLog(TalkerData log) => forwardTalkerData(_inspector, log);

  @override
  void onError(TalkerError err) => forwardTalkerData(_inspector, err);

  @override
  void onException(TalkerException err) => forwardTalkerData(_inspector, err);
}
