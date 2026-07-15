# 實作計畫：一鍵診斷報告（Diagnostic Report）

> **規格**：[docs/features/2026-07-15-diagnostic-report.md](../features/2026-07-15-diagnostic-report.md)（24 條 AC，已確認）
> **日期**：2026-07-15
> **基準**：v1.4.0 / branch `main`
> 本文件只寫 **How**。AC 一律以編號引用，不重述規格內容。

---

## 1. 資料結構與介面設計

### 1.1 版本單一真相（前置項 P-1）

**調查結果（實際查證，非臆測）**：

```text
lib/src/core/flutter_inspector.dart:24   static const String version = '1.1.0';
pubspec.yaml:3                           version: 1.4.0
test/flutter_inspector_test.dart:12      expect(FlutterInspector.version, '1.1.0');   ← 元凶
```

**沒人發現的根因就在那條測試**：它把常數硬編碼字串跟常數自己比對，永遠會過，什麼都沒驗證。這是一條「驗證了一個恆等式」的假測試。

**可行方案盤點**：
- ❌ **執行期讀 `pubspec.yaml`**：Dart 做不到。package 的 pubspec 不會被打包進 app，要讀只能宣告成 Flutter asset + `rootBundle`（需要 widget binding，違反 AC-1 的純函式要求，且污染宿主的 asset bundle）。
- ❌ **build-time codegen**：套件的 `dev_dependencies` 只有 `flutter_test` + `flutter_lints`（Makefile 的 `build_runner` target 是專案模板殘留，pubspec 裡根本沒有 `build_runner`）。為了一個字串引入 codegen 相依 = 過度工程。
- ✅ **人工同步 + 測試把關**：唯一常數放 `lib/src/version.dart`，寫一條**真的會失敗**的測試——用 `dart:io` 讀 `pubspec.yaml`（unit test 跑在 VM，cwd = package root），parse 出 `version:` 那行，斷言與 `packageVersion` 相等。版本漂移 → 紅燈。

**採用 C**。這是唯一不加相依、又真的會擋住漂移的做法。

```dart
lib/src/version.dart          const String packageVersion = '1.4.0';   ← 單一真相
lib/src/core/flutter_inspector.dart
    static const String version = packageVersion;                       ← 公開 API 不變（AC-22）
```

放在獨立檔的理由（不是為了分層，是為了相依）：`FlutterInspector` import 了 `package:flutter/widgets.dart`，而報告產生器必須是 Flutter-free（AC-1 / AC-24）。builder 直接 import `version.dart` 就拿得到版本，不會把 Flutter 拖進 `utils/`。

### 1.2 Device / app info 注入介面（AC-4 / AC-5 / AC-6）

形狀直接抄 `database_browser_source.dart` 的先例（抽象 source + 值物件同檔、在 barrel export）：

```
lib/src/models/diagnostic_info.dart

  @immutable
  class DiagnosticInfo {            // 全欄位 nullable → builder 印 N/A
    final String? appVersion;       // e.g. "2.3.1+45"
    final String? deviceModel;      // e.g. "iPhone15,2"
    final String? osVersion;        // e.g. "iOS 17.4"
  }

  abstract class DiagnosticInfoSource {
    Future<DiagnosticInfo> collect();
  }
```

**為什麼是固定欄位而不是 `Map<String, String>`**：AC-4 要求「未注入時顯示 `N/A`」——你沒辦法對一個自己都不知道 key 的 map 印 N/A。固定三欄位讓報告表頭的形狀跨宿主一致，也讓 AC-4/AC-5 可測。

**為什麼 `collect()` 是 async 但 builder 是 sync**：`device_info_plus` / `package_info_plus` 都是 async。**async 邊界留在 UI**（export sheet 的 `onPressed` 本來就是 async），builder 收到的是已 resolve 的 `DiagnosticInfo?`。這樣 builder 保持純同步 → AC-1 的 unit test 不需要 `pumpEventQueue`，也不需要 widget binding。

`FlutterInspector` 新增可選建構參數（比照 `redactSensitiveData` / `databaseSources` 的既有模式）：

```
FlutterInspector({ ..., this.diagnosticInfoSource })   // default null
final DiagnosticInfoSource? diagnosticInfoSource;
```

barrel（`lib/flutter_inspector_kit.dart`）新增 `export 'src/models/diagnostic_info.dart';`——這是 D-8 的**唯一例外**（宿主要 implement 它，不 export 就用不了），比照 `database_browser_source.dart` 已在 barrel 的處理。

### 1.3 報告產生器（AC-1，D-7 / D-8）

檔案：`lib/src/utils/diagnostic_report.dart`。**不 export 到 barrel**（沿用 `aggregateNetworkErrors()` 先例）。

```
String buildDiagnosticReport({
  required LogInspector logInspector,          // errorsOnly 要呼叫 entriesAtLevel（AC-13）
  required List<NetworkEntry> networkEntries,
  required List<NavigatorEntry> navigatorEntries,
  required List<DatabaseEntry> databaseEntries,
  required DateTime now,                        // 注入 → 時間窗可決定性測試（AC-8）
  DiagnosticInfo? info,                         // null → 全 N/A（AC-4）
  Duration? timeRange,                          // null → all（見下）
  Set<TimelineSource> sections = const {log, network, nav, db},
  bool errorsOnly = false,                      // 預設關閉（AC-11）
  bool redact = true,                           // 呼叫端傳 inspector.redactSensitiveData
})
```

只 import：`log_inspector.dart`、四個 model、`version.dart`、`network_formatters.dart`、`log_formatters.dart`、`navigator_stack_resolver.dart`。**零 `dart:io`、零 `package:flutter/material.dart`**（AC-21 / AC-24）。

### 1.4 三個過濾維度的形狀 — **不需要 options 物件**

Coordinator 問「能不能收斂成一個乾淨的 options 物件」。答案是：**收斂的重點不在包一個類別，在於幹掉那個 enum。**

| 天真作法 | 好品味作法 |
|---|---|
| `enum TimeRange { last5m, last1h, all }` → builder 裡 `switch` 把 enum 映射成 cutoff，`all` 是特例分支 | `Duration? timeRange`（**null == all**）→ `final cutoff = timeRange == null ? null : now.subtract(timeRange);` |
| 每個區段各自 `if (errorsOnly && source == log)` | 三個維度各作用在**不同的收斂點**，互不交纏 |

```dart
// 一個 nullable 幹掉整個 switch 與 all 特例：
final cutoff = timeRange == null ? null : now.subtract(timeRange);
bool inWindow(TimestampedEntry e) => cutoff == null || e.timestamp.isAfter(cutoff);
```

UI 的三顆時間 radio 直接是**資料**，不是程式碼分支：`[Duration(minutes: 5), Duration(hours: 1), null]`。

三個維度各自只有一個收斂點，沒有交叉的 if：

| 維度 | 型別 | 收斂點 |
|---|---|---|
| 時間窗 | `Duration?`（null = all） | 每個區段渲染前的 `.where(inWindow)` |
| 區段 | `Set<TimelineSource>`（**沿用既有 enum**，`mergedTimeline` 已在用） | 每個區段外層的 `if (sections.contains(...))` |
| errors-only | `bool` | **只在 log 區段的取數那一行**（AC-12：其他區段連碰都不碰） |

**結論：不新增 `DiagnosticReportOptions` 類別。** 三個具名參數 + 一個 nullable Duration 就完事了；包成物件只是多一層搬運，UI 端用三個 `State` 欄位直接餵具名參數即可。（YAGNI — 未來若 builder 有第二個呼叫端再說。）

### 1.5 各區段怎麼接既有零件（**複用清單**）

| 區段 | 複用什麼 | 怎麼接 |
|---|---|---|
| **表頭** | `version.dart` 的 `packageVersion` | `Generated / Package / Redaction: enabled\|disabled / App version / Device / OS`，null → `N/A` |
| **當前路由堆疊** | `NavigatorStackResolver().resolve(entries)` | ⚠️ **餵完整的 `navigatorEntries`，不餵時間窗過濾後的**——replay 必須從 buffer 頭跑起，餵截斷的事件會推導出錯誤的堆疊 |
| **Log 區段** | `buildLogPlainText(entry)`（既有）+ `logInspector.entriesAtLevel()`（既有，**從沒被呼叫過**） | 每筆包進 ``` fenced code block |
| **Network 區段** | `buildPlainText(entry, redact: redact)`（既有） | 同上。**redaction 全靠這條路徑**（AC-15/16/18），builder 自己不碰 header |
| **Nav / DB 區段** | 無現成 formatter | 各寫一個 **private 一行式** helper 放在 `diagnostic_report.dart` 內（`NavigatorEntry.displayName` / `DatabaseEntry.operation`+`tableName`+`affectedRows` 都是現成 getter）。**不新開 `navigator_formatters.dart` / `database_formatters.dart`**——單一消費者，YAGNI |
| **輸出** | `shareText(String)`（既有，io/web 條件匯出） | export sheet 的確認鍵 `await shareText(report)` |

**Markdown 包裝策略（最懶且誠實）**：`buildPlainText` / `buildLogPlainText` 吐的是 `=== General ===` 純文字區塊。報告**不重新序列化**，直接把每筆的純文字包進 Markdown fenced code block。零重寫、GitHub / Jira 都正常渲染。

### 1.6 errors-only 的實作（AC-10 / AC-11 / AC-13）

`entriesAtLevel(LogLevel)` 是**精確等級比對**，不是「≥ 某等級」：

```dart
final logs = errorsOnly
    ? ([
        ...logInspector.entriesAtLevel(LogLevel.error),
        ...logInspector.entriesAtLevel(LogLevel.warning),
      ]..sort((a, b) => b.timestamp.compareTo(a.timestamp)))   // 兩份 newest-first 合併後要重排
    : logInspector.entries;
```

複用既有函式（AC-13），不重寫等級過濾。合併後重排以維持 newest-first 慣例。

---

## 2. 檔案異動清單

### 新增

| 檔案 | 一句話 |
|---|---|
| `lib/src/version.dart` | 版本單一真相：`const String packageVersion = '1.4.0';` |
| `lib/src/models/diagnostic_info.dart` | `DiagnosticInfo` 值物件 + `DiagnosticInfoSource` 抽象注入介面 |
| `lib/src/utils/diagnostic_report.dart` | 純函式 `buildDiagnosticReport(...)` + nav/db 的 private 一行式 formatter |
| `lib/src/ui/dashboard/export_report_sheet.dart` | 匯出選項 bottom sheet（三維度 UI + 確認 → `shareText`） |
| `test/version_test.dart` | 讀 `pubspec.yaml` 斷言版本一致（P-1 把關） |
| `test/models/diagnostic_info_test.dart` | `DiagnosticInfo` 值語意 |
| `test/utils/diagnostic_report_test.dart` | builder 的主力 unit test（AC-1~18 絕大多數在這） |
| `test/ui/export_report_sheet_test.dart` | sheet 的 widget test（AC-19 / AC-20） |

### 修改

| 檔案 | 一句話 |
|---|---|
| `lib/src/core/flutter_inspector.dart` | `version` 改指向 `packageVersion`；新增 `diagnosticInfoSource` 可選參數（default null） |
| `lib/flutter_inspector_kit.dart` | 新增 `export 'src/models/diagnostic_info.dart';`（D-8 唯一例外） |
| `lib/src/ui/dashboard/dashboard_modal.dart` | AppBar 目前空的 `actions:` 加一顆 export IconButton |
| `test/flutter_inspector_test.dart` | 刪掉硬編碼 `'1.1.0'` 的假測試，改斷言 `== packageVersion` |
| `test/core/flutter_inspector_test.dart` | 補 `diagnosticInfoSource` 預設 null / 可注入 |
| `test/ui/export_report_sheet_test.dart` | 補 AppBar export action 存在 |
| `README.md` / `CHANGELOG.md` | 新公開 API（`DiagnosticInfoSource`）的用法與版本紀錄 |

**`pubspec.yaml` 不動**（AC-6）——沒有共享檔案的寫入競爭。

---

## 3. 任務拆分

> 每個任務 **TDD-first**：先寫（會紅的）測試 → 再實作 → 跑指定指令綠燈。
> 測試沿用專案既有慣例（`flutter_test` + `group`/`test`/`testWidgets`），**不引入新框架**。

### T1 — 版本單一真相（前置項 P-1）
- **複雜度**：`快/便宜`
- **寫入 scope**：`lib/src/version.dart`、`lib/src/core/flutter_inspector.dart`、`test/version_test.dart`、`test/flutter_inspector_test.dart`
- **AC**：AC-3、AC-22
- **步驟**：
  1. 寫 `test/version_test.dart`：`File('pubspec.yaml').readAsLinesSync()` 找 `version:` 開頭那行 → 取值 → `expect(packageVersion, pubspecVersion)`。此時應為**紅燈**（1.1.0 vs 1.4.0）。
  2. 建 `lib/src/version.dart`：`const String packageVersion = '1.4.0';`
  3. `flutter_inspector.dart:24` 改成 `static const String version = packageVersion;`（公開 API 簽章不變）。
  4. `test/flutter_inspector_test.dart:12` 把 `expect(FlutterInspector.version, '1.1.0')` 改成 `expect(FlutterInspector.version, packageVersion)`。
- **驗收**：`flutter test test/version_test.dart test/flutter_inspector_test.dart`
- **依賴**：無。**必須第一個做**（其他任務讀 `packageVersion`；且它與 T3 都要寫 `flutter_inspector.dart`）

### T2 — `DiagnosticInfo` + `DiagnosticInfoSource`
- **複雜度**：`快/便宜`
- **寫入 scope**：`lib/src/models/diagnostic_info.dart`、`test/models/diagnostic_info_test.dart`
- **AC**：（為 AC-4 / AC-5 鋪路）
- **步驟**：先寫值語意測試（`==` / `hashCode` / 全 null 可建構），再照 `database_browser_source.dart` 的體例寫 model + abstract source。**只有這兩個型別，不加 factory、不加預設實作。**
- **驗收**：`flutter test test/models/diagnostic_info_test.dart`
- **依賴**：無。**可與 T1 並行**（寫入路徑完全不重疊）

### T3 — `FlutterInspector.diagnosticInfoSource` + barrel export
- **複雜度**：`快/便宜`
- **寫入 scope**：`lib/src/core/flutter_inspector.dart`、`lib/flutter_inspector_kit.dart`、`test/core/flutter_inspector_test.dart`
- **AC**：AC-5、AC-6、AC-22
- **步驟**：先補測試（預設 null；傳入 fake source 可取回），再加可選參數 + `final` 欄位 + barrel export 一行。
- **驗收**：`flutter test test/core/flutter_inspector_test.dart`；`git diff pubspec.yaml` 為空（AC-6）
- **依賴**：T1（同檔 `flutter_inspector.dart` — **唯一 owner，必須序列**）、T2（型別）

### T4 — builder 骨架：簽章 + 表頭 + 時間窗 + 區段選擇 + 空狀態
- **複雜度**：`最強推論`（要定死 options 形狀、Markdown 結構、與五個既有零件的接線）
- **寫入 scope**：`lib/src/utils/diagnostic_report.dart`、`test/utils/diagnostic_report_test.dart`
- **AC**：AC-1、AC-2、AC-3、AC-4、AC-5、AC-8、AC-9、AC-14
- **步驟**：
  1. 測試先行：注入固定 `now` + 跨時間窗的假 entries，驗 `timeRange: null` / `5m` / `1h`；驗未勾選的 source 不出現（連標題都沒有）；驗 `info: null` → 表頭三欄全 `N/A`；驗空區段印 `(none)`。
  2. 實作 §1.3 的簽章；`cutoff` 用 §1.4 的 `Duration?` 寫法（**不准出現 TimeRange enum**）。
  3. 表頭印 `packageVersion`（來自 T1）。
- **驗收**：`flutter test test/utils/diagnostic_report_test.dart`
- **依賴**：T1、T2。**可與 T3 並行**（`utils/` vs `core/`+barrel，寫入不重疊）

### T5 — builder 區段內容：接 `buildPlainText` / `buildLogPlainText` / `NavigatorStackResolver`
- **複雜度**：`標準`
- **寫入 scope**：`lib/src/utils/diagnostic_report.dart`、`test/utils/diagnostic_report_test.dart`（**與 T4 同檔 → 序列**）
- **AC**：AC-7、AC-14、AC-15、AC-16、AC-17、AC-18
- **步驟**：
  1. 🔴 測試先行（redaction 紅線）：帶 `Authorization: Bearer secret` 的 `NetworkEntry` → `redact: true` 時報告字串**不含** `Bearer secret`、含 `••••`；`redact: false` 時含明文。表頭出現 `Redaction: enabled` / `disabled`。
  2. 測 nav 堆疊區段 == `NavigatorStackResolver().resolve(navigatorEntries)`（top-first）。⚠️ 加一條測試守住「堆疊 replay 餵的是**完整** buffer 而非時間窗過濾後的清單」——設一組「push 在時間窗外、pop 在窗內」的 entries，斷言堆疊仍正確。
  3. 實作：network 段一律走 `buildPlainText(entry, redact: redact)`，log 段走 `buildLogPlainText(entry)`，各自包 fenced code block；nav / db 段用 private 一行式 helper。
- **驗收**：`flutter test test/utils/diagnostic_report_test.dart`
- **依賴**：T4（同檔）

### T6 — builder 的 errors-only 維度
- **複雜度**：`快/便宜`
- **寫入 scope**：`lib/src/utils/diagnostic_report.dart`、`test/utils/diagnostic_report_test.dart`（**與 T4/T5 同檔 → 序列**）
- **AC**：AC-10、AC-11、AC-12、AC-13
- **步驟**：測試先行（勾選 → log 段只剩 error+warning；未勾選 → 全收且預設 `false`；勾選前後 network/nav/db 段字串**完全相同**）→ 實作 §1.6 的三行。
- **驗收**：`flutter test test/utils/diagnostic_report_test.dart`
- **依賴**：T5（同檔）

### T7 — 匯出 sheet + AppBar action
- **複雜度**：`標準`
- **寫入 scope**：`lib/src/ui/dashboard/export_report_sheet.dart`、`lib/src/ui/dashboard/dashboard_modal.dart`、`test/ui/export_report_sheet_test.dart`
- **AC**：AC-19、AC-20、AC-23
- **步驟**：
  1. `dashboard_modal.dart` 的 AppBar `actions:`（目前是空的）加一顆 IconButton → `showModalBottomSheet`。
  2. `_ExportReportSheet`（StatefulWidget）：4 個 source `CheckboxListTile` + 3 選 1 時間範圍（值為 `Duration(minutes:5)` / `Duration(hours:1)` / `null`）+ 1 個 errors-only `CheckboxListTile`（**預設 false**）+ 確認鍵。
  3. 確認鍵：`final info = await inspector.diagnosticInfoSource?.collect();` → `buildDiagnosticReport(..., now: DateTime.now(), redact: inspector.redactSensitiveData, info: info)` → `await shareText(report)`。
  4. **`ConsoleTab` 一行都不准動**（AC-23）。
- **驗收**：`flutter test test/ui/export_report_sheet_test.dart test/ui/tabs/console_tab_test.dart`
- **依賴**：T3、T6
- **⚠️ 測 AC-20 的已知限制**：`shareText` 是 conditional-export 的頂層函式，**無法 spy**（既有的 `network_detail_view_test` / `log_detail_view_test` 也沒 spy 它，只 mock `Clipboard.setData` 的 method channel）。做法：比照既有慣例 mock **share_plus 的 method channel** 並斷言收到一次呼叫 + 捕獲的字串。**channel 名稱請從 `pubspec.lock` 釘住的 share_plus 13.x 原始碼實地確認，不要憑記憶填**。若 channel 名稱驗證不了，退而求其次：斷言 sheet 的確認鍵可按且 sheet 關閉（報告**內容**已由 T4~T6 的 unit test 全覆蓋）。

### T8 — 文件
- **複雜度**：`快/便宜`
- **寫入 scope**：`README.md`、`CHANGELOG.md`
- **AC**：無（但新公開 API 需說明）
- **步驟**：README 加一節「Diagnostic Report」——如何 implement `DiagnosticInfoSource`（用 `device_info_plus` + `package_info_plus` 的範例，**明示這兩個套件由宿主自行安裝，本套件零相依**）；CHANGELOG 加版本條目。
- **🔴 README 的範例必須是「可直接複製貼上就能跑」的完整 class**（含 import、`implements DiagnosticInfoSource`、`collect()` 全實作、以及傳入 `FlutterInspector(diagnosticInfoSource: ...)` 的那一行），**不是**殘缺片段或「請自行實作」一句話。理由：Host 注入把「拿 device 資訊」的工作轉嫁給宿主開發者，若文件摩擦高，多數人不會接線，報告表頭永遠是 `N/A`，本功能最核心的痛點（QA 手打 device/OS/版本）就沒被解決。文件品質在這裡是功能的一部分，不是附屬品。
- **驗收**：人工閱讀
- **依賴**：T6。**可與 T7 並行**（`README/CHANGELOG` vs `lib/ui`，寫入不重疊）

### T9 — 全域驗收掃描
- **複雜度**：`快/便宜`
- **寫入 scope**：無（唯讀 + 最終 test run）
- **AC**：AC-6、AC-21、AC-24 + 全體迴歸
- **步驟**：
  1. `git diff --stat pubspec.yaml` 為空 → AC-6
  2. `grep -n "dart:io\|path_provider\|File(" lib/src/utils/diagnostic_report.dart` 無命中 → AC-21 / AC-24
  3. `grep -rn "diagnostic_report" lib/flutter_inspector_kit.dart` 無命中 → D-8（builder 沒被 export）
  4. `flutter analyze` + `flutter test`（全套）→ AC-22 / AC-23 迴歸
- **依賴**：全部

---

## 4. 並行性

| 批次 | 任務 | 並行？ | 理由 |
|---|---|---|---|
| **1** | **T1** ∥ **T2** | ✅ 並行 | T1 寫 `version.dart` + `core/flutter_inspector.dart`；T2 只寫 `models/diagnostic_info.dart`。零重疊 |
| **2** | **T3** ∥ **T4** | ✅ 並行 | T3 owns `core/flutter_inspector.dart` + **barrel**；T4 owns `utils/diagnostic_report.dart`。零重疊 |
| **3** | **T5** | ❌ 序列 | 與 T4 同檔 `diagnostic_report.dart` |
| **4** | **T6** | ❌ 序列 | 與 T4/T5 同檔 |
| **5** | **T7** ∥ **T8** | ✅ 並行 | T7 owns `ui/dashboard/*`；T8 owns `README/CHANGELOG`。零重疊 |
| **6** | **T9** | ❌ 序列 | 全域驗收，須在最後 |

**共享檔的唯一 owner（絕不並行寫）**：

| 檔案 | 唯一 owner |
|---|---|
| `lib/src/core/flutter_inspector.dart` | **T1 → T3**（依序，兩者都寫；批次 1 與 2 之間有 barrier） |
| `lib/flutter_inspector_kit.dart`（barrel） | **T3** |
| `lib/src/utils/diagnostic_report.dart` | **T4 → T5 → T6**（嚴格序列） |
| `lib/src/ui/dashboard/dashboard_modal.dart` | **T7** |
| `pubspec.yaml` | **無人**（AC-6：不得修改） |

---

## 5. 執行方式（供選擇）

| 方式 | 說明 | 適用 |
|---|---|---|
| **A. Subagent-driven（推薦）** | 依批次派工：批次 1 兩個 subagent 並行 → barrier → 批次 2 兩個並行 → T5/T6 單線接力 → 批次 5 兩個並行 → T9 收尾。複雜度標籤直接對應 model 選擇（`快/便宜` → 輕量 model；T4 的 `最強推論` → 最強 model） | 預設。批次間的 barrier 天然對應共享檔的 owner 切換 |
| **B. Parallel session** | 開兩個 session：session A 跑 `core/` + barrel 線（T1→T3→T7），session B 跑 `utils/` 線（T2→T4→T5→T6）。T7 需等 B 的 T6，收斂點在 T7 前 | 想要人工盯 UI 那條線時 |
| **C. 單線序列** | T1→T2→…→T9 全序列 | 最省心，但浪費批次 1/2/5 的並行度 |

---

## 6. 實作紅線（違反即在 STAGE 3 退回）

1. **不准出現 `TimeRange` enum**。時間窗就是 `Duration?`，null == all（§1.4）。
2. **不准新開 `navigator_formatters.dart` / `database_formatters.dart`**。單一消費者 → private helper 留在 `diagnostic_report.dart`。
3. **不准新增 `DiagnosticReportOptions` 類別**。具名參數就夠（§1.4）。
4. **不准重寫 redaction / 等級過濾 / 堆疊 replay**。一律複用 `buildPlainText(redact:)`、`entriesAtLevel()`、`NavigatorStackResolver`。
5. **不准動 `pubspec.yaml`**（AC-6）、**不准動 `ConsoleTab`**（AC-23）。
6. **`NavigatorStackResolver.resolve()` 必須餵完整 `navigatorEntries`**，不是時間窗過濾後的清單（T5 步驟 2）。
7. **`DiagnosticInfoSource` 是規格明訂的注入介面，是唯一允許的新抽象**。除此之外不准出現任何 interface / factory / 為未來預留的 scaffolding。
