/// 統一的排序契約：所有可進時序軸的 entry 都暴露一個 [timestamp]。
///
/// 用 abstract interface class（只能 implements、不能 extends），把它鎖死為窄契約：
/// 它存在的唯一理由是讓 [mergedTimeline] 能用單一型別索取排序鍵，
/// extension（[displayTime]）才得以掛在這個契約上。
abstract interface class TimestampedEntry {
  /// 事件發生時間，作為時序軸排序鍵。
  DateTime get timestamp;
}

/// [TimestampedEntry] 的衍生顯示。
///
/// [displayTime] 是 derived（不是 raw data），四種 model 格式統一、不依賴具體型別，
/// 因此用 extension 提供一份共用實作，避免四個 model 各抄一份（DRY）。
/// 格式為 `HH:mm:ss.mmm`（如 `14:30:01.123`），刻意不沿用 toIso8601String（帶日期+微秒太冗長）。
extension TimestampedEntryDisplay on TimestampedEntry {
  String get displayTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// 時序軸的來源類別，用於 [mergedTimeline] 過濾與 console_tab filter chip。
enum TimelineSource { log, network, nav, db }
