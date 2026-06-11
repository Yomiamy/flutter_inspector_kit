# 功能規格：發布 package 到 pub.dev

- **日期**：2026-06-11
- **狀態**：待使用者確認（含 3 個待決事項，見「待使用者決策」）
- **類型**：發布作業（不涉及功能代碼變更）

## 1. 背景與目標

本專案是一個 in-app 多功能 debug overlay（Console / Network / Navigator / Database），目前僅以 GitHub repo 形式存在。發布到 pub.dev 的目標：

- 讓使用者能以 `dependencies: <package>: ^x.y.z` 直接安裝，而非 git dependency
- 取得 pub.dev 的版本管理、文件託管（dartdoc）與 package score 曝光
- 建立正式的版本發布節奏（CHANGELOG 與 semver 對齊）

### 關鍵阻礙（調查發現）

**`flutter_inspector` 名稱已被佔用。** pub.dev 上已存在同名 package（v0.1.0，2025-12-27 由 Shivam-dev925 發布，repo: `github.com/Shivam-dev925/flutter_inspector`）。pub.dev 的 package 名稱為先到先得且不可重複，本專案**必須改名**才能發布。這是本次規格範圍內最大的工作項。

## 2. 使用者故事

1. **作為 Flutter 開發者**，我想在 pubspec.yaml 加一行依賴就能安裝這個 inspector，而不需要設定 git dependency，以便快速整合到專案。
2. **作為 package 維護者（Yomiamy）**，我想要一個乾淨的發布流程：dry-run 零錯誤、套件內容不含開發產物、版本號與 CHANGELOG 一致，以便每次發版都可重複執行。
3. **作為 pub.dev 瀏覽者**，我想在 package 頁面看到正確渲染的 README（截圖、用法範例）、example、與合理的 package score，以便評估是否採用。

## 3. 驗收條件

### 必要（發布門檻）

- [ ] **AC1 — 名稱可用**：新 package 名稱經 `https://pub.dev/api/packages/<name>` 回傳 404 確認可用（候選名稱已於 2026-06-11 全數驗證可用，見第 6 節）。
- [ ] **AC2 — dry-run 全綠**：`flutter pub publish --dry-run` 結果為 **0 error、0 warning、0 hint**（改名後「version earlier than published」hint 應消失）。
- [ ] **AC3 — 套件內容乾淨**：dry-run 檔案清單不含 `build/`、`coverage/`、`scripts/`、`docs/`、`doc/`；壓縮後 archive 大小 < 1 MB（現況為 19 MB，主因是 62 MB 的 `build/test_cache/*.dill`）。
- [ ] **AC4 — 命名一致性**：
  - pubspec `name` 為新名稱
  - library 進入點檔名為 `lib/<新名稱>.dart`（符合 pub convention）
  - README、`example/lib/main.dart`、`example/pubspec.yaml`、test 檔案中的 `package:` import 全部更新為新名稱
- [ ] **AC5 — 版本與 CHANGELOG 一致**：CHANGELOG 的 `## Unreleased` 段落收斂為正式版本號段落，且與 pubspec `version` 完全一致。
- [ ] **AC6 — 品質檢查通過**：`flutter analyze` 0 issue、`dart format` 無 diff、`flutter test` 全數通過（注意：`magical_tap_test` 有既有的 10 分鐘 timeout 設定，屬已知狀態，非本次引入）。
- [ ] **AC7 — 變更已推上 GitHub**：改名後的 pubspec 已 push 到 repo 預設分支，使 pub.dev 的 repository verification（pana 會比對 repo 內 pubspec 與發布內容）能通過。

### 期望（pub.dev score 相關，盡力達成）

- [ ] **AC8 — pana 自評**：本機執行 `dart pub global run pana` 無「Failed」項目（description 長度 60–180 字元已符合：現為 121 字元）。
- [ ] **AC9 — README 渲染正確**：截圖使用 GitHub raw 絕對 URL（現況已是），在 pub.dev 頁面可正常顯示。
- [ ] **AC10 — topics**：pubspec 加入 `topics`（如 `debugging`、`developer-tools`、`network`、`logging`）提升可發現性。

### 最終發布（人工步驟）

- [ ] **AC11 — 實際發布由使用者手動執行**：`flutter pub publish`（非 dry-run）需要 pub.dev 帳號 OAuth 驗證與最終確認，**一律由使用者本人執行**，不納入自動化流程。

## 4. 範圍邊界（明確不做）

| 不做的事 | 理由 |
|---|---|
| 修改任何功能代碼（`lib/src/` 內的邏輯） | 本次純粹是發布作業；類別名稱（如 `FlutterInspector`）**不**因 package 改名而更動 |
| 自動執行真正的 `flutter pub publish` | 需要帳號驗證且不可逆，必須由使用者手動執行（AC11） |
| GitHub repo 改名 | 可選的後續作業；repo 名與 package 名不同不影響發布與 repository verification，僅需 pubspec URL 指向正確 repo |
| 設定 verified publisher（自訂網域） | 需要網域所有權驗證，超出本次範圍；以個人帳號 uploader 發布即可 |
| CI/CD 自動發布 pipeline（GitHub Actions + pub.dev token） | YAGNI；首次發布先走手動流程，未來有需求再另開規格 |
| 補寫缺漏的 dartdoc 註解以衝高 score | public API 文件覆蓋率屬持續改善項目，不阻擋首次發布 |
| 處理 `flutter pub outdated` 列出的 6 個可升級依賴 | 皆為 transitive/dev 依賴的小版本差異，與發布無關 |

## 5. Dry-run 調查結果與待修正問題清單（規格核心輸入）

`flutter pub publish --dry-run` 於 2026-06-11 執行結果：**0 error、0 warning、1 hint**，exit code 0。但通過 dry-run 不代表可發布——以下問題依嚴重度排列：

### P0 — 阻擋發布

1. **名稱衝突**：`flutter_inspector` 已被他人發布（v0.1.0）。實際 publish 會因無 uploader 權限被 pub.dev 拒絕（403）。dry-run 的 hint「The latest published version is 0.1.0. Your version 0.0.1 is earlier than that.」即是此衝突的徵兆。
   - **修正**：改名（候選清單見第 6 節），連動修改 pubspec name、`lib/flutter_inspector.dart` 檔名、所有 `package:flutter_inspector/` import（lib/example/test/README）。

### P1 — 必須修正（內容品質）

2. **`.pubignore` 覆蓋了 `.gitignore` 的排除規則**：根目錄存在 `.pubignore`（只列了 `docs/`、`.agents/`、`.claude/`、`.gemini/`、`.fvm/`）。依 pub 規則，`.pubignore` 存在時該目錄**完全取代** `.gitignore`，導致原本被 git 忽略的 `build/`（含 62 MB test cache dill）、`coverage/` 被打包進套件，壓縮後 archive 達 19 MB。
   - **修正**：在 `.pubignore` 補上 `build/`、`coverage/`、`scripts/`、`doc/`（截圖已用 GitHub raw URL，無需隨包散布）。
3. **版本號與 CHANGELOG 不同步**：pubspec 為 `0.0.1`，但 CHANGELOG 有未發布的 `## Unreleased` 段落（heads-up notification、throttling、pending entry fix 等）。改名後 pub.dev 上是全新 package，建議直接以 **0.1.0** 作為首發版本，將 Unreleased 與 0.0.1 內容收斂。
   - **修正**：bump pubspec version、整理 CHANGELOG（版本號最終值見「待使用者決策」）。

### P2 — 建議修正（score 與可發現性）

4. **缺 `topics` 欄位**：pubspec 未宣告 topics，影響 pub.dev 搜尋曝光。
5. **README 安裝範例版本**：`flutter_inspector: ^0.0.1` 需同步更新為新名稱與新版本。

### 現況已達標項目（無需處理）

- LICENSE：MIT，pub.dev 可識別 ✅
- description：121 字元，落在 60–180 建議區間 ✅
- homepage / repository / issue_tracker 三欄位齊備 ✅
- `example/` 完整可跑，pub.dev 會渲染 Example tab ✅
- `pubspec.lock` 由 pub 自動排除，未進入 archive ✅
- `example/build/` 等子目錄產物未進入 archive（子目錄無 `.pubignore`，`.gitignore` 仍生效）✅

## 6. 待使用者決策

1. **新 package 名稱**（以下皆已於 2026-06-11 驗證 pub.dev 可用）：
   - `flutter_inspector_kit`（建議：最貼近原名、語意清楚）
   - `flutter_multi_inspector`（呼應「multi-inspector」定位）
   - `inspector_kit` / `app_inspector` / `dash_inspector` / `yo_inspector` / `inspectorx`
2. **首發版本號**：建議 `0.1.0`（Unreleased + 0.0.1 合併為首發）；或保守用 `0.0.1`。
3. **GitHub repo 是否同步改名**：不改也能發布（pubspec URL 維持現 repo 即可）；若改名需同步更新 pubspec 三個 URL 欄位。

## 7. 後續流程

本規格經使用者確認（含第 6 節決策）後，進入 STAGE 0b 撰寫實作計畫 `docs/plans/2026-06-11-pubdev-publish.md`，任務粒度 2–5 分鐘，TDD/驗證優先（每步以 dry-run 或 analyze/test 驗證）。
