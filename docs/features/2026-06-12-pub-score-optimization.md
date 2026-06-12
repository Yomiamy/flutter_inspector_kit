# Pub.dev Score Optimization: 130 → 160 pub points

> 日期：2026-06-12
> 對象套件：`flutter_inspector_kit` 0.2.0（已發布 130/160）
> 證據來源：本地 `pana 0.23.12` 完整報告（與 pub.dev 同版分析器）

## 問題（What & Why）

pub.dev score 有兩個扣分區塊，合計 -30 分：

### 1. Support up-to-date dependencies：20/40（-20）

- **失敗項目**：`Compatible with dependency constraint lower bounds`（0/20）
- **根因**：`pubspec.yaml` 宣告 `dio: ^5.0.0`，但 `lib/src/integrations/dio_interceptor.dart:56` 使用了 `DioException`——此類別在 **dio 5.2.0** 才引入（取代 `DioError`）。pana 的 downgrade analysis 把 dio 降到 5.0.0 後編譯失敗：
  ```
  UNDEFINED_CLASS - dio_interceptor.dart:56:16 - Undefined class 'DioException'
  ```
- 其餘兩個子項（依賴皆最新、支援最新 SDK）均已滿分。

### 2. Platform support：10/20（-10）

- **六大平台全數通過**（pana 明確標示 ✓ Android/iOS/Windows/Linux/macOS/Web；報告中的「does not support platform X」列在 *"do not affect the score"* 區塊，源頭是 share_plus 上游宣告，不扣分）。
- **真正扣 10 分的是 WASM 不相容**：
  > "This package supports Web but is not WASM-compatible, resulting in a partial score."
- **根因鏈**（pana 逐層追出）：
  ```
  network_detail_view.dart
    → share_plus/share_plus.dart
    → share_plus_web.dart → share_plus_platform_interface
    → method_channel_share.dart → path_provider
    → package:platform/local_platform.dart → dart:io   ← WASM 殺手
  ```
- `share_plus` 在本套件**只用於一處**：`network_detail_view.dart:230`，分享 network log 純文字（且已有 Clipboard fallback）。

## 解決方案

### Fix 1：dio 下限改 `^5.2.0`（確定 +20）

一行修改。`DioException` 自 5.2.0 起存在，下限對齊實際 API 使用。

### Fix 2：以條件式 import 隔離 share_plus（目標 +10）

不破壞既有 UX（行動端保留原生 share sheet），只把 web/wasm 路徑從 share_plus 的 import graph 切開：

- 新增 `lib/src/utils/share_text.dart` 薄抽象：`Future<void> shareText(String text)`
- `share_text_io.dart`：委派 `SharePlus.instance.share(...)`（Android/iOS/desktop 原行為不變）
- `share_text_web.dart`：用 `package:web` 呼叫 `navigator.share`，不支援時丟例外讓既有 Clipboard fallback 接手
- 入口以 `import 'share_text_io.dart' if (dart.library.js_interop) 'share_text_web.dart';` 切換
- `network_detail_view.dart` 改呼叫 `shareText(...)`，行為與錯誤處理不變

> 風險註記：修掉 share_plus 鏈後，pana 可能揭露下一個 WASM 阻擋者（候選：`flutter_local_notifications`，初查 lib/ 無無條件 `dart:io` import，風險低但需實證）。驗收以本地 pana 重跑為準。

## 驗收條件

1. `flutter pub downgrade && flutter analyze` 無錯誤（lower-bound 檢查通過）
2. `flutter analyze` / `flutter test` 全綠（升級後一般路徑）
3. 本地 `pana` 報告：
   - `Support up-to-date dependencies: 40/40`
   - `Platform support: 20/20`（WASM compatible）
   - 總分 `160/160`
4. 行動端分享行為不變（share sheet 正常）；web 端 share 失敗時 fallback 到 Clipboard（原邏輯）

## 範圍邊界

- **不做**：移除 share_plus 依賴本身（native 端仍使用）、touch flutter_local_notifications（除非 pana 實證它是下一個 wasm 阻擋者）、任何 UI 變更
- **公開 API 零變動**（純內部重構 + pubspec 約束調整），版本建議 0.2.1（patch）
