import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/log_level.dart';

/// Signature for the function used to log a performance warning.
typedef PerformanceLogCallback =
    void Function(
      String message, {
      required LogLevel level,
      String? stackTrace,
      Map<String, dynamic>? data,
      DateTime? timestamp,
      String? activeRoute,
    });

/// Monitors frame rendering timings via [SchedulerBinding.addTimingsCallback],
/// recording discrete [LogLevel.warning] events when single-frame rendering
/// exceeds [threshold] (default 700ms, aligned with Android Vitals frozen frame).
///
/// Continuous frozen frames are merged into a single streak event to avoid
/// flooding the log buffer during heavy jank (e.g. frantic scrolling).
class PerformanceHandler {
  /// The function called to log a performance warning.
  final PerformanceLogCallback onLog;

  /// Optional supplier of a label for the current top-most page, appended to
  /// the log message (e.g. `Frozen frame (820ms) · HomePage (/home)`).
  final String? Function()? topPageLabel;

  /// The duration threshold to classify a frame as frozen. Defaults to 700ms.
  final Duration threshold;

  /// Supplier of current wall-clock time; overridable for deterministic tests.
  final DateTime Function() _clock;

  bool _attached = false;
  bool _selfInducedReassemblePending = false;

  // Streak tracking state
  int _streakCount = 0;
  Duration _streakTotalSpan = Duration.zero;
  Duration _streakVsyncOverhead = Duration.zero;
  Duration _streakBuildDuration = Duration.zero;
  Duration _streakRasterDuration = Duration.zero;
  DateTime? _streakTimestamp;
  String? _streakPageLabel;
  int? _lastRasterFinishMicros;

  /// Max inter-frame gap (in microseconds) to treat two frozen frames as
  /// consecutive. 300ms is well above normal frame rates (16-66ms) but short
  /// enough to distinguish a continuous stutter from two separate user actions.
  static const int _kMaxConsecutiveGapMicros = 300000;

  /// Creates a new PerformanceHandler instance.
  PerformanceHandler({
    required this.onLog,
    this.topPageLabel,
    this.threshold = const Duration(milliseconds: 700),
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now()) {
    if (threshold <= Duration.zero) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'must be greater than zero',
      );
    }
  }

  /// Registers this handler via [SchedulerBinding.instance.addTimingsCallback].
  void attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Removes this handler from [SchedulerBinding.instance].
  ///
  /// Safe to call when not attached, and flushes any pending frozen frame streak.
  void detach() {
    if (_attached) {
      _attached = false;
      try {
        SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      } catch (_) {
        // Ignored if SchedulerBinding is already torn down.
      }
    }
    _flushStreak();
  }

  /// Discards any pending frozen frame streak without logging it.
  void reset() => _resetStreak();

  /// Marks that a self-induced reassemble (e.g. toggling debug layout boundaries)
  /// was triggered by the inspector. The subsequent frozen frame timing will be
  /// ignored to prevent self-observing jank from polluting the timeline.
  void markSelfInducedReassemble() {
    _flushStreak();
    _selfInducedReassemblePending = true;
  }

  /// Processes a batch of frame timings. Visible for testing.
  @visibleForTesting
  void handleTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    for (final t in timings) {
      if (_selfInducedReassemblePending && t.totalSpan >= threshold) {
        _selfInducedReassemblePending = false;
        continue;
      }
      _processTiming(t);
    }
    _selfInducedReassemblePending = false;
  }

  void _onTimings(List<FrameTiming> timings) {
    try {
      handleTimings(timings);
    } catch (e, s) {
      debugPrintStack(
        stackTrace: s,
        label: 'inspector performance timing failed: $e',
      );
    }
  }

  void _processTiming(FrameTiming t) {
    if (t.totalSpan >= threshold) {
      final vsyncStart = t.timestampInMicroseconds(FramePhase.vsyncStart);
      final isConsecutive =
          _streakCount > 0 &&
          _lastRasterFinishMicros != null &&
          (vsyncStart - _lastRasterFinishMicros!) <= _kMaxConsecutiveGapMicros;

      if (!isConsecutive && _streakCount > 0) {
        _flushStreak();
      }

      if (_streakCount == 0) {
        _streakCount = 1;
        _streakTotalSpan = t.totalSpan;
        _streakVsyncOverhead = t.vsyncOverhead;
        _streakBuildDuration = t.buildDuration;
        _streakRasterDuration = t.rasterDuration;
        _streakTimestamp = _resolveTimestamp(t);
        _streakPageLabel = topPageLabel?.call();
      } else {
        _streakCount++;
        _streakTotalSpan += t.totalSpan;
        _streakVsyncOverhead += t.vsyncOverhead;
        _streakBuildDuration += t.buildDuration;
        _streakRasterDuration += t.rasterDuration;
      }
      _lastRasterFinishMicros = t.timestampInMicroseconds(
        FramePhase.rasterFinish,
      );
    } else {
      if (_streakCount > 0) {
        _flushStreak();
      }
    }
  }

  DateTime _resolveTimestamp(FrameTiming t) {
    final wallTimeMicros = t.timestampInMicroseconds(
      FramePhase.rasterFinishWallTime,
    );
    if (!kIsWeb && wallTimeMicros > 0) {
      return DateTime.fromMicrosecondsSinceEpoch(wallTimeMicros);
    }
    return _clock();
  }

  void _flushStreak() {
    if (_streakCount == 0) return;
    final page = _streakPageLabel;
    final suffix = (page == null || page.isEmpty) ? '' : ' · $page';
    final count = _streakCount;
    final totalMs = _streakTotalSpan.inMilliseconds;
    final message = count > 1
        ? 'Frozen frame (${totalMs}ms, $count frames)$suffix'
        : 'Frozen frame (${totalMs}ms)$suffix';

    final data = <String, dynamic>{
      'totalSpanMs': totalMs,
      'vsyncOverheadMs': _streakVsyncOverhead.inMilliseconds,
      'buildDurationMs': _streakBuildDuration.inMilliseconds,
      'rasterDurationMs': _streakRasterDuration.inMilliseconds,
      if (count > 1) 'frameCount': count,
    };

    final timestamp = _streakTimestamp;
    _resetStreak();

    onLog(
      message,
      level: LogLevel.warning,
      data: data,
      timestamp: timestamp,
      activeRoute: page,
    );
  }

  void _resetStreak() {
    _streakCount = 0;
    _streakTotalSpan = Duration.zero;
    _streakVsyncOverhead = Duration.zero;
    _streakBuildDuration = Duration.zero;
    _streakRasterDuration = Duration.zero;
    _streakTimestamp = null;
    _streakPageLabel = null;
    _lastRasterFinishMicros = null;
  }
}
