# 實作計畫：無回應請求慢查詢標記與狀態指示（§Z1-3 / §P8 既有缺陷修正）

- **日期**：2026-10-17
- **規格**：`docs/features/2026-10-17-pending-request-slow-indicator.md`
- **Effort**：low

---

## 1. 資料結構與設計

**不新增額外模型類別與狀態變數。**

於 `NetworkEntry` 中直接定義純計算方法：
```dart
/// Round-trip duration if complete, or elapsed time from [timestamp] to [now].
Duration elapsedAt(DateTime now) => duration ?? now.difference(timestamp);
```

- 若請求已記錄完成時間（`duration != null`），回傳實際往返時間。
- 若請求尚未完成（`duration == null`），以傳入的時間計算自 `timestamp` 至今之耗時。
- 零額外複製、零狀態儲存、零破壞既有欄位契約。

調用端替換：
1. `_EntryTile` (`network_tab.dart`):
   - `isSlow = entry.elapsedAt(now) >= slowRequestThreshold`
   - `statusText` 於未完成時顯示 `no response · ${entry.elapsedAt(now).inSeconds}s`
   - `subtitle` 於未完成時省略無意義的 `- ms`
2. `_NetworkErrorSummaryHeader` (`network_tab.dart`):
   - `slowCount` 改依 `entry.elapsedAt(now) >= slowRequestThreshold` 統計
3. `_NetworkEventTile` (`console_tab.dart`):
   - `entry.elapsedAt(now) >= inspector.slowRequestThreshold`

---

## 2. 任務拆分

**總任務數：1（單一任務）**

### Task 1 · `NetworkEntry.elapsedAt` 實作 + NetworkTab / ConsoleTab 判定與標籤 + 測試 + CHANGELOG

**寫入路徑**：
- `lib/src/models/network_entry.dart`（新增 `elapsedAt` 方法）
- `lib/src/ui/dashboard/tabs/network_tab.dart`（`_EntryTile` 與 `_NetworkErrorSummaryHeader` 判定與副標題更新）
- `lib/src/ui/dashboard/tabs/console_tab.dart`（`_NetworkEventTile` 判定更新）
- `test/models/network_entry_test.dart`（`elapsedAt` 單元測試）
- `test/ui/tabs/network_tab_test.dart`（未完成請求慢查詢與標籤 Widget 測試）
- `test/ui/tabs/console_tab_test.dart`（未完成請求慢查詢標籤 Widget 測試）
- `CHANGELOG.md`（Unreleased 記錄）

#### 1a. 實作

1. `lib/src/models/network_entry.dart`:
   ```dart
   /// Round-trip duration if complete, or elapsed time from [timestamp] to [now].
   Duration elapsedAt(DateTime now) => duration ?? now.difference(timestamp);
   ```

2. `lib/src/ui/dashboard/tabs/network_tab.dart`:
   - 在 `_EntryTile.build`:
     ```dart
     final now = DateTime.now();
     final isSlow = entry.elapsedAt(now) >= slowRequestThreshold;
     final statusText = entry.isComplete
         ? '${entry.statusCode ?? entry.error ?? '-'}'
         : 'no response · ${entry.elapsedAt(now).inSeconds}s';
     final durationText = entry.duration != null
         ? '${entry.duration!.inMilliseconds} ms'
         : null;
     final subtitleParts = [
       statusText,
       if (durationText != null) durationText,
       formatBytes(totalSize),
       timeOf(entry.timestamp),
     ];
     ```
     `subtitle` 改為 `Text(subtitleParts.join(' · '), ...)`
     `trailing` 的 `if` 改為 `if (isSlow)`
   - 在 `_NetworkErrorSummaryHeader.build`:
     ```dart
     final now = DateTime.now();
     final slowCount = entries
         .where((e) => e.elapsedAt(now) >= slowRequestThreshold)
         .length;
     ```

3. `lib/src/ui/dashboard/tabs/console_tab.dart`:
   - 在 `_NetworkEventTile.build`:
     ```dart
     final now = DateTime.now();
     // ...
     if (entry.elapsedAt(now) >= inspector.slowRequestThreshold)
       Container(...)
     ```

#### 1b. 測試

1. `test/models/network_entry_test.dart`:
   - 驗證 `elapsedAt` 在 `duration != null` 時回傳 `duration`
   - 驗證 `elapsedAt` 在 `duration == null` 時回傳 `now.difference(timestamp)`
2. `test/ui/tabs/network_tab_test.dart`:
   - 驗證發起時間早於閾值且未完成的請求在列表中顯示 `🐢 SLOW`
   - 驗證未完成請求之副標題顯示 `no response · <N>s`，且不包含 `- ms`
   - 驗證 Error Summary 的慢查詢計數包含超時未完成請求
3. `test/ui/tabs/console_tab_test.dart`:
   - 驗證未完成且超過閾值的請求在 Console Tab 中顯示 `🐢 SLOW`

#### 1c. 文件

- `CHANGELOG.md` 於 Unreleased 增列修正項目。

---

## 3. 驗證

```bash
flutter test test/models/network_entry_test.dart
flutter test test/ui/tabs/network_tab_test.dart
flutter test test/ui/tabs/console_tab_test.dart
flutter test
flutter analyze lib/ test/
```

---

## 4. 刻意不做

| 項目 | 理由 |
|:---|:---|
| 新增 Timer 定時觸發 setState | 避免每秒重繪造成無謂 CPU 耗損與觀察者效應，維持使用者切換／刷新時按當前時間評估 |
| 標記為 STALLED / TIMED_OUT | 未完成請求可能仍在等待服務端處理，以 `no response · Xs` 中性描述最精確 |
| 變更 NetworkDetailView 協議狀態 | 保持 DetailView 中原始 HTTP 欄位之呈現 |

---

## 5. 風險與回滾

純粹為判定式由 `entry.duration != null && entry.duration! >= threshold` 擴充至 `entry.elapsedAt(now) >= threshold`，以及未完成行副標題之字串格式微調。零資料結構破壞，零破壞性變更。回滾只需恢復相關檔案即可。
