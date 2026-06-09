# 功能規格：flutter_inspector 可發布 package 骨架

- 日期：2026-06-09
- 狀態：已確認
- 對齊參考：`~/StudioWorkspace/flutter_go_router_extension`

## What & Why

作為套件作者，要把 `flutter_inspector` 從空 repo 改造成結構完整、可在後期
`flutter pub publish` 到 pub.dev 的 Flutter package。骨架對齊
`flutter_go_router_extension` 慣例，但 package 置於 **repo root**（標準發布布局，
非目標專案的子目錄做法）。本次只搭骨架，inspector 功能後續再實作。

## 驗收條件

1. repo root 有合法 `pubspec.yaml`，含 `name`、`description`、`version: 0.0.1`、
   `homepage`/`repository`/`issue_tracker`（指向 `Yomiamy/flutter_inspector`），
   SDK 約束對齊 Flutter 3.38.3（`sdk: ^3.10.1`）。→ `flutter pub get` 成功。
2. `lib/flutter_inspector.dart` 作為 public 進入點，`export` 一個 placeholder
   `lib/src/` 檔案。
3. `analysis_options.yaml` 引入 `flutter_lints`。→ `flutter analyze` 零錯誤。
4. `test/flutter_inspector_test.dart` 至少一個會通過的 smoke test。→ `flutter test` 綠燈。
5. `example/` 可執行的最小 Flutter app，demo import package。→ example 內 `flutter pub get` 成功。
6. `CHANGELOG.md` 有 `0.0.1` 初始條目。
7. `.metadata` 標記 `project_type: package`。
8. `LICENSE`、`README.md` 保留並補齊發布所需內容。→ `flutter pub publish --dry-run` 無致命缺漏。

## 範圍邊界

包含：package 結構、發布元資料、lint 設定、placeholder library code、最小 example、
最小 test、CHANGELOG。

不包含：
- 任何實際 inspector 功能邏輯（延後）
- 真正執行 `flutter pub publish`（只到 `--dry-run` 可過）
- CI/CD、平台特定設定（除 example 跑得起來所需的最小設定）

## 確認的預設值

- `version: 0.0.1`
- `description`: "A multi-inspector tool integration for Flutter."（發布前需 ≥60 字元）
- package `name`: `flutter_inspector`
- SDK: `sdk: ^3.10.1`
