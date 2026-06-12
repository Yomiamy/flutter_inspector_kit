# 實作計畫：Pub.dev Score Optimization（130 → 160）

> 規格：docs/features/2026-06-12-pub-score-optimization.md
> 並行評估：Task 1 與 Task 2 都需修改 `pubspec.yaml`（共享資源單一 owner 規則）→ **序列執行**

## Task 1：dio 依賴下限修正（複雜度：機械性／快速 model）

**寫入檔案**：`pubspec.yaml`

1. `dio: ^5.0.0` → `dio: ^5.2.0`（`DioException` 自 5.2.0 引入）

**驗證**：
```bash
flutter pub downgrade && flutter analyze   # lower-bound 必須通過（pana 同款檢查）
flutter pub upgrade && flutter analyze && flutter test
```

## Task 2：share 條件式 import，切斷 web/wasm 對 share_plus 的依賴（複雜度：標準 model）

**寫入檔案**：
- `pubspec.yaml`（新增直接依賴 `web: ^1.1.0`——目前已是傳遞依賴，wasm-safe）
- `lib/src/utils/share_text.dart`（新增，條件式 import 入口）
- `lib/src/utils/share_text_io.dart`（新增）
- `lib/src/utils/share_text_web.dart`（新增）
- `lib/src/ui/dashboard/tabs/network/network_detail_view.dart`（改用 `shareText`）

**設計**：
```dart
// share_text.dart
export 'share_text_io.dart' if (dart.library.js_interop) 'share_text_web.dart';

// share_text_io.dart — 原行為，零變動
Future<void> shareText(String text) =>
    SharePlus.instance.share(ShareParams(text: text));

// share_text_web.dart — package:web 的 navigator.share；
// 瀏覽器不支援時 throw，讓呼叫端既有 catch → Clipboard fallback 接手
```

`network_detail_view.dart`：移除 `share_plus` import，`SharePlus.instance.share(...)` 改 `shareText(buildPlainText(entry))`。try/catch 與 SnackBar 邏輯**完全不動**。

**約束**：`share_plus` 保留在 pubspec（io 路徑仍用）；公開 API 零變動。

**驗證**：`flutter analyze && flutter test`

## Task 3：pana 總驗收 + 版本收尾（複雜度：機械性，但含判斷迴圈）

1. 本地重跑 `dart pub global run pana --no-warning .`
2. 驗收門檻：`Platform support: 20/20`、`Support up-to-date dependencies: 40/40`、總分 `160/160`
3. **若 wasm 仍未過**：讀取 pana 新揭露的 import 鏈，回到 Task 2 模式處理下一個阻擋者（候選：`flutter_local_notifications`，初查無無條件 `dart:io`，風險低）
4. 通過後：`version: 0.2.1`、補 `CHANGELOG.md`

**寫入檔案**：`pubspec.yaml`、`CHANGELOG.md`

## 完成定義

- [ ] `flutter pub downgrade && flutter analyze` 通過
- [ ] `flutter analyze` / `flutter test` 全綠
- [ ] 本地 pana = 160/160
- [ ] 行動端 share sheet 行為不變；web share 失敗 fallback Clipboard（原邏輯）
