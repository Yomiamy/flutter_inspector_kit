# B6 · release 四處版號一致性防護（P0）

> **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §8.2 🔴 B6（P0 建議項目）
> **狀態**：功能規格（What & Why）· 2026-09-24

---

## 1. 🔴 背景與現況分析

本專案在 `CLAUDE.md` §4 明確規範了發布新版本時，版本號必須在以下 **四處** 保持嚴格一致：

1. `pubspec.yaml` (`version: x.y.z`)
2. `lib/src/version.dart` (`const String packageVersion = 'x.y.z';`)
3. `README.md` (`flutter_inspector_kit: ^x.y.z`)
4. `CHANGELOG.md` (`## x.y.z`)

### 1.1 歷史事故與現存漏洞

- **歷史事故（已發生）**：在 v1.6.0 發布時，`lib/src/version.dart` 漏改、停留在 `1.5.0`，導致執行時期呼叫 `FlutterInspector.version` 輸出錯誤版號，事後以 commit `0bd3b7e` 補修。
- **現存漏洞一（Guide 缺漏）**：`.claude/skills/gen-update-publish-info/SKILL.md`（及 `.agents/skills/gen-update-publish-info/SKILL.md`）目前僅列出 `pubspec.yaml`、`README.md`、`CHANGELOG.md` 三處，文內多次強調「三處都要改」，完全漏掉了 `lib/src/version.dart`。依循該 skill 很容易再次遺漏。
- **現存漏洞二（Sensor 覆蓋不足）**：`test/version_test.dart` 僅有 20 行，且只檢查 `pubspec.yaml` 與 `packageVersion`（`version.dart`），完全未對 `README.md` 與 `CHANGELOG.md` 的版本進行斷言。
- **環境特性（無 CI）**：本 repo 明訂無遠端 CI，本機測試套件與 Git hook 是唯一具有強制力的阻擋機制（Sensor）。如果測試沒抓，錯誤就會直接被推送並打上 release tag。

---

## 2. 使用者故事

**主要場景（防止發布漏改版號）**

> 身為套件維護者，當我使用 `gen-update-publish-info` 進行新版本發布或 bump 版號時，我希望技能指引清楚明列四處修改點，並且測試套件能在任何一處版號未同步時立即報錯，以避免發布帶有不一致版號或執行期版本錯誤的套件。

**反面場景（避免手動失誤未被攔截）**

> 身為套件維護者，若我在編輯 `README.md` 或 `CHANGELOG.md` 時筆誤打錯版號（例如漏打小數點或多打一位），我希望執行 `flutter test` 能精確指出「哪一個檔案與 `pubspec.yaml` 不符」，而不是在 pub.dev 發布後才被使用者發現。

---

## 3. 範圍邊界

### 3.1 做什麼 (In Scope)

| # | 項目 | 說明 |
|:-:|:---|:---|
| 1 | 擴充 `gen-update-publish-info/SKILL.md` | 將檢查清單從「三處」更新為「四處」，明確補上 `lib/src/version.dart`，並同步更新 `.claude/` 與 `.agents/` 兩處的 skill 定義 |
| 2 | 強化 `test/version_test.dart` | 擴充測試用例，以 `pubspec.yaml` 為基準，同時驗證：<br>① `lib/src/version.dart` 的 `packageVersion`<br>② `README.md` 引用範例中的 `^x.y.z`<br>③ `CHANGELOG.md` 最新發布章節標題 `## x.y.z` |
| 3 | 驗證測試的反向證偽性 | 驗證當任一處版本不匹配時，測試能精確 FAIL 並指出具體檔案與差異 |

### 3.2 不做什麼 (Out of Scope)

| 項目 | 理由 |
|:---|:---|
| **修改目前套件版號** | 目前四處均一致為 `2.6.0`，本次為健全防護機制，非發布新版本 |
| **修改其他發布流程步驟** | 不涉及 git tag 命名、git push 或 pub.dev 認證流程 |
| **引入額外的外部套件** | 使用 Dart SDK 內建之 `dart:io` 與 `package:flutter_test` 即可完成，維持零新相依 |

---

## 4. 驗收條件

### 4.1 功能面

| # | 條件 | 驗證方式 |
|:-:|:---|:---|
| AC-1 | `gen-update-publish-info/SKILL.md` 表格明確列出四處檔案（`pubspec.yaml`, `lib/src/version.dart`, `README.md`, `CHANGELOG.md`）與對應欄位 | 人工檢視 `.claude/` 與 `.agents/` 的 SKILL.md 內容 |
| AC-2 | `test/version_test.dart` 驗證 `packageVersion == pubspecVersion` | 執行測試通過 |
| AC-3 | `test/version_test.dart` 驗證 `README.md` 包含 `flutter_inspector_kit: ^$pubspecVersion` | 執行測試通過 |
| AC-4 | `test/version_test.dart` 驗證 `CHANGELOG.md` 最新章節為 `## $pubspecVersion` | 執行測試通過 |
| AC-5 | 測試失敗訊息清晰可辨（指出哪一個檔案與預期版本不符） | 檢視斷言訊息設計 |

### 4.2 不可回歸（Never break userspace）

| # | 條件 | 驗證方式 |
|:-:|:---|:---|
| AC-6 | 現有測試全數通過 | 執行 `flutter test`，全部測試 PASS |
| AC-7 | 靜態分析無新增警告 | 執行 `flutter analyze lib/ test/`，維持既有 baseline |

---

## 5. 設計方向

### 方案 A：在 `test/version_test.dart` 內加入專用群組與清晰正則匹配（推薦）

將單元測試拆分為獨立 group 或明確測試項目：
1. `packageVersion in lib/src/version.dart matches pubspec.yaml`
2. `install instruction in README.md matches pubspec.yaml`
3. `latest release entry in CHANGELOG.md matches pubspec.yaml`

- 優點：測試顆粒度細，任何一處出錯，測試報告能直接點名該檔案。
- 實作：透過簡單字串包含或正則表達式提取，邏輯透明直接。
