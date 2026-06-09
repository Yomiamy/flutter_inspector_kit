# 實作計畫：flutter_inspector 可發布 package 骨架

- 對應規格：`docs/features/2026-06-09-publishable-package-skeleton.md`
- 日期：2026-06-09
- 布局決策：package 置於 **repo root**（標準 pub.dev 布局）

## 資料結構 / 最終檔案佈局

```
flutter_inspector/                     ← repo root = package root
├── pubspec.yaml                       ← 發布元資料（新增）
├── analysis_options.yaml              ← flutter_lints（新增）
├── .metadata                          ← project_type: package（新增）
├── CHANGELOG.md                       ← 0.0.1 初始條目（新增）
├── LICENSE                            ← 既有，保留
├── README.md                          ← 既有，補齊發布內容
├── lib/
│   ├── flutter_inspector.dart         ← public 進入點，export src（新增）
│   └── src/
│       └── flutter_inspector_base.dart ← placeholder 實作（新增）
├── test/
│   └── flutter_inspector_test.dart    ← smoke test（新增）
└── example/
    ├── pubspec.yaml                    ← publish_to: none, path: ../（新增）
    ├── analysis_options.yaml           ← （新增）
    └── lib/
        └── main.dart                  ← 最小 app，import package（新增）
```

> .gitignore 已於前一 commit 處理（含 lib/gen/、worktrees 等），本計畫不再動它。
> example 的 android/ios 平台目錄：先不手建，靠任務 2 的 `flutter create` 補齊
> （或視需要僅保留 lib/ + pubspec 讓 `flutter pub get` 通過即可，不需真跑 app）。

## 任務拆分

各任務寫入路徑互不重疊，理論上可並行；但任務間有「pubspec 先就位才能 pub get / analyze」
的隱性依賴，故 **任務 1 → 2 序列**，其餘可並行。實際以序列執行為主，逐任務暫停確認。

### 任務 1：package 元資料核心 ★複雜度：機械性（1–2 檔）
建立發布元資料三件套，這是 pub get 與 analyze 的前提。
- 寫 `pubspec.yaml`：name=flutter_inspector, version=0.0.1, description（≥60 字元）,
  homepage/repository/issue_tracker → `https://github.com/Yomiamy/flutter_inspector`,
  `environment: sdk: ^3.10.1, flutter: ">=1.17.0"`, dependencies(flutter sdk),
  dev_dependencies(flutter_test sdk, flutter_lints ^6.0.0)
- 寫 `analysis_options.yaml`：`include: package:flutter_lints/flutter.yaml`
- 寫 `.metadata`：`project_type: package`，revision 對齊 stable channel
驗收：`flutter pub get` 成功。

### 任務 2：library 進入點 + placeholder 實作 ★複雜度：機械性
- `lib/src/flutter_inspector_base.dart`：一個最小 placeholder（如 `class FlutterInspector`
  附帶版本常數或一個 no-op 方法），有 dartdoc 註解
- `lib/flutter_inspector.dart`：`library;` + `export 'src/flutter_inspector_base.dart';`
驗收：`flutter analyze` 零錯誤。

### 任務 3：smoke test ★複雜度：機械性
- `test/flutter_inspector_test.dart`：import package，一個必過的 test
  （驗 placeholder class 可實例化 / 常數值正確）
驗收：`flutter test` 綠燈。

### 任務 4：最小 example app ★複雜度：機械性
- `example/pubspec.yaml`：name=example, `publish_to: 'none'`, sdk ^3.10.1,
  dependencies 含 `flutter_inspector: { path: ../ }` + cupertino_icons,
  dev_dependencies flutter_test/flutter_lints
- `example/analysis_options.yaml`
- `example/lib/main.dart`：最小 MaterialApp，import flutter_inspector，畫面顯示 placeholder
驗收：`example/` 內 `flutter pub get` 成功。

### 任務 5：發布文件（CHANGELOG + README）★複雜度：機械性
- `CHANGELOG.md`：`## 0.0.1` — Initial project skeleton.
- `README.md`：補上 Installation / Usage(placeholder) / License 段落，保留現有標題
驗收：`flutter pub publish --dry-run` 無致命缺漏（warning 可接受，因功能未實作）。

## 風險點

- pub.dev description 長度需 ≥60 字元、≤180 字元，任務 1 須注意。
- `flutter pub publish --dry-run` 可能因 example 平台目錄缺失或 README 內容不足而 warn；
  本次目標是「無致命 error」，warning 列出讓使用者知曉即可，不強制全清。
- SDK 約束 `^3.10.1` 需與本機 Flutter 3.38.3 帶的 Dart 版本相容，任務 1 後 pub get 驗證。
