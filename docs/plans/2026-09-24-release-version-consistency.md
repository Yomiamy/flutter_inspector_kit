# B6 · release 四處版號一致性防護 — 實作計畫

> **規格**：[`docs/features/2026-09-24-release-version-consistency.md`](../features/2026-09-24-release-version-consistency.md)
> **日期**：2026-09-24 ｜ **優先序**：P0 ｜ **預估 Effort**：低（改動小、防護高）

---

## 1. 核心判斷與設計原則

**這是一個典型的「Guide 漏寫 + Sensor 盲區」導致歷史事故復發的防禦型任務。**

- **歷史教訓**：v1.6.0 發布曾漏改 `lib/src/version.dart` 導致執行期輸出舊版號，事後補修；成因原封不動躺在 `gen-update-publish-info/SKILL.md` 的「三處都要改」表格中。
- **Linus 好品味原則**：消滅特殊情況與人為記憶依賴。既然本 repo 無 CI，**單元測試套件就是唯一不可繞過的強制力閘門（Sensor）**。
- **單一真相來源 (SSOT)**：以 `pubspec.yaml` 的 `version` 欄位為單一真相基準，其餘三處（`lib/src/version.dart`、`README.md`、`CHANGELOG.md`）必須與之完全同步。

---

## 2. 資料流與四處版號模型

```text
                  pubspec.yaml (SSOT: version: x.y.z)
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
lib/src/version.dart         README.md             CHANGELOG.md
packageVersion = 'x.y.z'  flutter_inspector_kit: ^x.y.z  ## x.y.z
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                     test/version_test.dart
            (Sensor: 執行 flutter test 逐一斷言一致性)
```

---

## 3. 檔案異動清單

| # | 檔案 | 動作 | 說明 |
|:-:|:---|:---|:---|
| 1 | `test/version_test.dart` | 修改 | 重構並擴充為 4 個獨立 test：驗證 pubspec 解析、`packageVersion`、`README.md` 安裝依賴範例、`CHANGELOG.md` 最新發布標題 |
| 2 | `.claude/skills/gen-update-publish-info/SKILL.md` | 修改 | 將發布步驟、表格、git add 與清單從「三處」修訂為「四處」，明確納入 `lib/src/version.dart` |
| 3 | `.agents/skills/gen-update-publish-info/SKILL.md` | 修改 | 同步更新 `.agents` 下之 skill 定義，保持雙目錄完全一致 |

**不動的檔案**：
- `pubspec.yaml`、`lib/src/version.dart`、`README.md`、`CHANGELOG.md`（目前四處均已為 `2.6.0`，本次不 bump 版號）。
- `scripts/wf-state.sh`（流程狀態機不變）。

---

## 4. 任務拆分與執行規劃 (TDD 導向)

### Task 1: 擴充 `test/version_test.dart` 支援四處版號斷言
- **目標**：讓單元測試全面覆蓋四處版號檢查。
- **檔案**：`test/version_test.dart`
- **實作內容**：
  1. 使用 `group('Release version consistency')` 組織。
  2. 提取 `pubspec.yaml` 的 `version` 欄位作為基準。
  3. 測試 1：`pubspec.yaml has valid semver`。
  4. 測試 2：`packageVersion in lib/src/version.dart matches pubspec.yaml`。
  5. 測試 3：`README.md dependency version matches pubspec.yaml`（檢查 `flutter_inspector_kit: ^$pubspecVersion`）。
  6. 測試 4：`CHANGELOG.md latest release header matches pubspec.yaml`（檢查首個 `## ` 標題為 `## $pubspecVersion`）。
  7. 提供清晰的 `reason` 失敗訊息，指出具體哪個檔案不符。
- **驗證**：`flutter test test/version_test.dart` 全綠。

### Task 2: 更新 `gen-update-publish-info/SKILL.md` 檢查清單為「四處同步」
- **目標**：修復技能指引缺漏，杜絕發布時遺漏 `version.dart`。
- **檔案**：
  - `.claude/skills/gen-update-publish-info/SKILL.md`
  - `.agents/skills/gen-update-publish-info/SKILL.md`
- **實作內容**：
  1. §1.1 Issue 模板 Fix：從 A/B/C 三項擴充為 A/B/C/D 四項（納入 `lib/src/version.dart`）。
  2. §3 更新版本資訊：標題從「三處」改為「四處」，表格增列 `lib/src/version.dart`（`const String packageVersion = '$VERSION';`）。
  3. §6.2 暫停與發布：`git add` 加入 `lib/src/version.dart`。
  4. Quick Reference：改版號守則明列四處都要改。
- **驗證**：Grep 檢查兩份 SKILL.md 無「三處」殘留，`version.dart` 出現在表格與命令中。

### Task 3: 證偽性驗證與全套回歸測試
- **目標**：進行 mutation testing，證明測試在版號不一致時確實會抓到並失敗。
- **動作**：
  1. 暫時在記憶體或臨時編輯中驗證：若 README 或 CHANGELOG 或 version.dart 版號錯誤，測試報錯。
  2. 執行全套測試 `flutter test`，確認無回歸。
  3. 執行 `flutter analyze lib/ test/`，確認無 linter 警告。

---

## 5. 驗證協定 (Verification Protocol)

1. **單元測試通過**：
   ```bash
   flutter test test/version_test.dart
   ```
2. **整套測試全綠**：
   ```bash
   flutter test
   ```
3. **靜態分析通過**：
   ```bash
   flutter analyze lib/ test/
   ```
4. **Git diff 審查**：
   確認僅異動 `test/version_test.dart` 及兩處 `gen-update-publish-info/SKILL.md`。
