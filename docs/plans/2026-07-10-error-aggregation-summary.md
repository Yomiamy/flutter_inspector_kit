# 實作計畫：錯誤聚合摘要（Error Aggregation Summary）

> **功能規格**：[docs/features/2026-07-10-error-aggregation-summary.md](../../features/2026-07-10-error-aggregation-summary.md)
> **日期**：2026-07-10
> **狀態**：Draft — 待使用者確認

---

## 任務總覽

| # | 任務 | 複雜度 | 檔案 | 依賴 |
|---|------|--------|------|------|
| 1 | Model + 聚合純函式 | Low | `lib/src/utils/network_utils.dart` | 無 |
| 2 | Error Summary Banner UI + 整合 | Medium | `lib/src/ui/dashboard/tabs/network_tab.dart` | Task 1 |
| 3 | 聚合邏輯 Unit Tests | Low | `test/utils/network_utils_test.dart` | Task 1 |
| 4 | Banner Widget Tests | Low | `test/ui/tabs/network_tab_test.dart` | Task 2 |

**並行判定**：Task 1 → Task 2（序列）。Task 3 可在 Task 1 完成後獨立跑。Task 4 在 Task 2 完成後獨立跑。**Task 3 與 Task 4 可並行**（寫入路徑不重疊）。

```
Task 1 ──→ Task 2 ──→ Task 4
   │
   └────→ Task 3（可與 Task 2 並行，或 Task 2 後序列）
```

---

## Task 1：Model + 聚合純函式

**檔案**：`lib/src/utils/network_utils.dart`（擴充既有檔案）
**複雜度**：Low

### 新增內容

#### 1a. `NetworkErrorGroup` 類別

在 `network_utils.dart` 尾部新增：

```dart
/// An aggregated group of network errors sharing the same
/// [statusCode] and [errorType].
@immutable
class NetworkErrorGroup {
  const NetworkErrorGroup({
    required this.statusCode,
    required this.errorType,
    required this.count,
    required this.firstSeen,
    required this.lastSeen,
    required this.label,
  });

  /// HTTP status code (null for transport-layer failures).
  final int? statusCode;

  /// Dio error classification (null for server-error responses).
  final DioExceptionType? errorType;

  /// Number of matching entries in the buffer.
  final int count;

  /// Timestamp of the earliest matching entry.
  final DateTime firstSeen;

  /// Timestamp of the most recent matching entry.
  final DateTime lastSeen;

  /// Human-readable label (e.g. "502 Bad Gateway", "Connection Timeout").
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkErrorGroup &&
          statusCode == other.statusCode &&
          errorType == other.errorType;

  @override
  int get hashCode => Object.hash(statusCode, errorType);
}
```

**設計決策**：
- `@immutable` 遵循專案慣例
- `==` / `hashCode` 只看 `statusCode` + `errorType`（聚合 key），讓 `_selectedErrorGroup` 比對直覺正確
- `label` 由聚合函式計算，不在 model 內推導——保持 model 純粹

#### 1b. `aggregateNetworkErrors()` 純函式

```dart
/// Groups error entries by (statusCode, errorType), returning
/// groups sorted by count descending.
List<NetworkErrorGroup> aggregateNetworkErrors(List<NetworkEntry> entries) {
  // ... 見下方邏輯
}
```

**聚合邏輯**（虛擬碼）：

1. 過濾出 error entries：`entry.error != null || (entry.statusCode != null && entry.statusCode! >= 400)`
2. 以 `(statusCode, errorType)` 為 key，用 `Map` 做 groupBy：
   - 每組追蹤 `count++`、`firstSeen = min(timestamps)`、`lastSeen = max(timestamps)`
3. 產生 `label`：
   - `statusCode != null` → `"$statusCode"` （如 `"502"`）
   - `statusCode == null && errorType != null` → errorType 的人類可讀名（如 `"Connection Timeout"`）
   - 都是 null → `"Unknown Error"`
4. 結果按 `count` 降序排列
5. 回傳 `List<NetworkErrorGroup>`

#### 1c. `errorTypeLabel()` 輔助函式

```dart
/// Returns a human-readable label for a [DioExceptionType].
String errorTypeLabel(DioExceptionType type) {
  return switch (type) {
    DioExceptionType.connectionTimeout => 'Connection Timeout',
    DioExceptionType.sendTimeout       => 'Send Timeout',
    DioExceptionType.receiveTimeout    => 'Receive Timeout',
    DioExceptionType.badCertificate    => 'Bad Certificate',
    DioExceptionType.badResponse       => 'Bad Response',
    DioExceptionType.cancel            => 'Cancelled',
    DioExceptionType.connectionError   => 'Connection Error',
    DioExceptionType.unknown           => 'Unknown Error',
  };
}
```

**需新增 import**：`import 'package:dio/dio.dart';`（只引入 `DioExceptionType`，`dio` 已在 pubspec 依賴中）

### 不動的部分

- `NetworkFilter` 類別**不修改**——過濾互動由 UI 層的 `_selectedErrorGroup` state 處理
- `applyNetworkFilter()` 函式**不修改**
- `NetworkStatusGroup` enum**不修改**

---

## Task 2：Error Summary Banner UI + 整合

**檔案**：`lib/src/ui/dashboard/tabs/network_tab.dart`（修改既有檔案）
**複雜度**：Medium

### 修改內容

#### 2a. `_NetworkTabState` 新增狀態

```dart
// 新增 state
NetworkErrorGroup? _selectedErrorGroup;
bool _errorSummaryExpanded = true;
```

#### 2b. `build()` 方法修改

在現有 Column 的 `_SearchBar` 與 `_FilterChips` 之間插入 banner：

```dart
Column(
  children: [
    _SearchBar(...),                    // ← 既有
    // 🆕 Error Summary Banner（條件渲染）
    _ErrorSummaryBanner(
      entries: networkEntries,          // 用未過濾的完整 entries
      selectedGroup: _selectedErrorGroup,
      expanded: _errorSummaryExpanded,
      onGroupTap: (group) => setState(() {
        _selectedErrorGroup =
            _selectedErrorGroup == group ? null : group;  // toggle
      }),
      onExpandToggle: () => setState(() {
        _errorSummaryExpanded = !_errorSummaryExpanded;
      }),
    ),
    _FilterChips(...),                  // ← 既有
    const Divider(height: 1),           // ← 既有
    Expanded(child: ...),               // ← 既有
  ],
)
```

#### 2c. 過濾邏輯增強

在 `build()` 中，`applyNetworkFilter()` 之後追加 error group 過濾：

```dart
var entries = applyNetworkFilter(networkEntries, _filter);
// 🆕 追加 error group 過濾
if (_selectedErrorGroup != null) {
  entries = entries.where((e) =>
    e.statusCode == _selectedErrorGroup!.statusCode &&
    e.errorType == _selectedErrorGroup!.errorType
  ).toList(growable: false);
}
```

**設計決策**：不修改 `NetworkFilter` 類別。error group 過濾是疊加在既有 filter 之上的獨立 pass，邏輯分離、零破壞。

#### 2d. `_ErrorSummaryBanner` Widget（新增，私有）

```dart
class _ErrorSummaryBanner extends StatelessWidget {
  const _ErrorSummaryBanner({
    required this.entries,
    required this.selectedGroup,
    required this.expanded,
    required this.onGroupTap,
    required this.onExpandToggle,
  });

  final List<NetworkEntry> entries;
  final NetworkErrorGroup? selectedGroup;
  final bool expanded;
  final ValueChanged<NetworkErrorGroup> onGroupTap;
  final VoidCallback onExpandToggle;

  @override
  Widget build(BuildContext context) {
    final groups = aggregateNetworkErrors(entries);
    if (groups.isEmpty) return const SizedBox.shrink();
    // ... 展開/收起邏輯 + 水平卡片列表
  }
}
```

**展開時**：`SizedBox(height: ~72)` + 水平 `ListView`，每組一個 `_ErrorGroupCard`
**收起時**：一行文字 `"⚠ N errors (M types)"` + 展開 icon

#### 2e. `_ErrorGroupCard` Widget（新增，私有）

小型 `Card`，顯示：
- 左側：顏色條（沿用 `InspectorTheme.statusColor()`）
- 標籤（如 `502`、`Timeout`）
- 次數 `× N`
- 時間跨度（`firstSeen` ~ `lastSeen`，用 `HH:mm:ss` 格式）
- 被選中時有 selected 視覺狀態（border highlight）

#### 2f. 清除 buffer 時重置選擇

在既有的 `onClearAll` callback 中追加：
```dart
_selectedErrorGroup = null;
```

### 不動的部分

- `_SearchBar`、`_FilterChips`、`_EntryTile`、`_MethodBadge` — **完全不動**
- `NetworkFilter`、`applyNetworkFilter()` — **不修改**

---

## Task 3：聚合邏輯 Unit Tests

**檔案**：`test/utils/network_utils_test.dart`（擴充既有檔案）
**複雜度**：Low

### 測試案例

| # | 測試名稱 | 輸入 | 預期 |
|---|---------|------|------|
| 3a | `空 entries 回傳空 list` | `[]` | `[]` |
| 3b | `全部成功請求 → 無 error group` | 5 筆 200 OK | `[]` |
| 3c | `單一 502 error → 1 組, count=1` | 1 筆 502 | `[{502, null, 1}]` |
| 3d | `相同 502 × 3 → 1 組, count=3` | 3 筆 502 | `[{502, null, 3}]` |
| 3e | `502 × 2 + 404 × 1 → 2 組，按 count 降序` | 混合 | `[{502, 2}, {404, 1}]` |
| 3f | `transport error (statusCode=null) 以 errorType 分組` | 2 筆 connectionTimeout + 1 筆 cancel | `[{null, connectionTimeout, 2}, {null, cancel, 1}]` |
| 3g | `混合 server error + transport error` | 502 × 2 + timeout × 3 | `[{timeout, 3}, {502, 2}]` |
| 3h | `成功請求不被計入` | 200 × 5 + 502 × 2 | `[{502, 2}]` |
| 3i | `isReplay=true 的錯誤仍被計入` | 1 筆 502 isReplay=true | `[{502, 1}]` |
| 3j | `firstSeen/lastSeen 正確` | 3 筆同類 error 不同時間 | 驗證 min/max timestamp |
| 3k | `errorTypeLabel 映射正確` | 8 個 DioExceptionType | 各自對應正確字串 |

---

## Task 4：Banner Widget Tests

**檔案**：`test/ui/tabs/network_tab_test.dart`（擴充既有檔案）
**複雜度**：Low

### 測試案例

| # | 測試名稱 | 預期 |
|---|---------|------|
| 4a | `無錯誤時 banner 不渲染` | 找不到任何 error summary 相關 widget |
| 4b | `有錯誤時 banner 出現` | 找到 error summary 橫幅，顯示正確的分組數量 |
| 4c | `點擊 error group 卡片 → 列表過濾` | tap 卡片後 ListView 只剩該組的 entries |
| 4d | `再次點擊同組 → 清除過濾（toggle）` | 第二次 tap 恢復完整列表 |
| 4e | `清除 buffer → banner 消失` | tap delete → banner 不再渲染 |
| 4f | `收起 banner → 只顯示摘要文字` | tap toggle → 橫幅收縮為一行 |

---

## 檔案異動彙整

| 操作 | 檔案路徑 | 動幅 |
|------|---------|------|
| **修改** | `lib/src/utils/network_utils.dart` | +~60 行（model + 函式 + helper） |
| **修改** | `lib/src/ui/dashboard/tabs/network_tab.dart` | +~120 行（banner + card + state + 整合） |
| **修改** | `test/utils/network_utils_test.dart` | +~100 行（11 個 unit test） |
| **修改** | `test/ui/tabs/network_tab_test.dart` | +~80 行（6 個 widget test） |
| **不動** | `pubspec.yaml`、barrel file、其他所有檔案 | — |

**總計**：4 個檔案修改，~360 行新增，0 個新檔案，0 個新依賴。
