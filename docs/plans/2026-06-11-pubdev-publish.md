# 實作計畫：發布 package 到 pub.dev（改名為 flutter_inspector_kit）

- **日期**：2026-06-11
- **對應規格**：`docs/features/2026-06-11-pubdev-publish.md`
- **狀態**：待執行
- **類型**：發布作業（不涉及功能代碼變更）

## 0. 已確認決策（覆寫規格第 6 節）

| 決策 | 結果 |
|---|---|
| 新 package 名稱 | **`flutter_inspector_kit`**（2026-06-11 二次驗證 pub.dev API 回 404，可用） |
| 首發版本號 | **`0.1.0`**（Unreleased + 0.0.1 收斂為首發） |
| GitHub repo 改名 | **同步改名**為 `flutter_inspector_kit`（推翻規格原「不做」邊界）。以 `gh repo rename` 執行，並同步更新 pubspec 三個 URL 與本地 remote。GitHub 對舊 URL 自動 redirect。 |

## 1. 範圍邊界重申（明確不做）

- **不修改任何功能代碼**：`lib/src/` 內邏輯、類別名稱（`FlutterInspector` 等）一律不動。
- **不更動 notification channel ID**：`flutter_inspector_network_v2` 與 legacy `flutter_inspector_network`（`lib/src/notifications/network_notifier.dart:33,40`、README 第 133 行、CHANGELOG）是**執行期識別字**，改了會破壞既有使用者的通知設定 — Never break userspace。所有批次替換必須避開。
- **實際 `flutter pub publish`（非 dry-run）一律由使用者手動執行**（AC11），不納入本計畫任何任務。
- 不設定 verified publisher、不做 CI/CD 發布 pipeline、不補 dartdoc、不升級依賴。

## 2. 實作方向 trade-off 分析

### 方向 A：全域 `sed s/flutter_inspector/flutter_inspector_kit/g` 一次替換

- ✅ 最快，一個指令。
- ❌ **會誤殺**：channel ID `flutter_inspector_network_v2`（lib + README + CHANGELOG 共 4 處）、legacy channel ID、CHANGELOG 歷史段落。誤改 channel ID = 破壞既有使用者的系統通知設定，屬不可接受的回歸。
- ❌ 出錯後難以局部回滾。

### 方向 B：精準前綴替換 + 分檔案責任區（採用）

- 利用一個關鍵觀察：所有**必須**改的程式引用都帶有 `package:flutter_inspector/` 前綴（27 種 import、23 個 test 檔 + example），而所有**不能**改的字串都不帶此前綴。兩步替換即可零誤殺：
  1. `package:flutter_inspector/flutter_inspector.dart` → `package:flutter_inspector_kit/flutter_inspector_kit.dart`（umbrella import，檔名也變）
  2. `package:flutter_inspector/` → `package:flutter_inspector_kit/`（其餘 src import）
- 非 import 的散落點（pubspec name、example 依賴名、README 安裝範例與截圖 URL）各自獨立成任務、明確檔案 scope，可並行且可獨立驗證。
- ✅ 每個任務寫入檔案互不重疊 → 最大化並行。✅ grep 殘留檢查可機械化驗證。
- ❌ 任務數較多 — 但每個都是 2–5 分鐘粒度，符合流程要求。

### 方向 C：開新 repo / 新 package skeleton 再搬移歷史

- ❌ 丟失 commit 歷史與 issue，GitHub redirect 也拿不到。純屬自找麻煩，否決。

**結論：採方向 B。**

## 3. 全域慣例

- **工作分支**：`feature/202606/pubdev-publish-rename`（本 repo 慣例走 PR merge）。
- **共享檔案規則**：`pubspec.yaml` 只由 T2 寫入；`README.md` 只由 T6 寫入；其餘任務檔案 scope 互斥。
- **複雜度等級**（供 implementer 分派 model）：
  - `[機械]` → 快/便宜 model：固定字串替換、跑指令、grep 驗證
  - `[標準]` → 標準 model：需語意判斷哪些字串該改/該留、判讀工具輸出
  - `[最強]` → 最強 model：本計畫**無**此類任務（無設計判斷需求）
- **外部不可逆操作**（T15、T16）：執行前**必須由總指揮向使用者逐項確認**，標註 ⚠️。

## 4. 任務清單

### Phase 0 — 前置

---

#### T1：建立 feature branch `[機械]`

- **目標**：所有變更在 feature branch 上進行，不碰 main。
- **步驟**：
  ```bash
  cd /Users/yomiry/StudioWorkspace/flutter_inspector
  git status   # 確認 clean
  git checkout -b feature/202606/pubdev-publish-rename
  ```
- **寫入檔案**：無（僅 git 狀態）
- **驗證**：`git branch --show-current` 輸出 `feature/202606/pubdev-publish-rename`
- **依賴**：無。**後續 T2–T8 全部依賴本任務。**

---

### Phase 1 — 改名連動與內容修正（T2–T8 檔案 scope 互斥，可全部並行）

---

#### T2：pubspec.yaml — name / version / URLs / topics `[標準]`

- **目標**：pubspec.yaml 一次到位（本檔案唯一寫入者，集中修改避免並行衝突）。
- **步驟**：編輯 `/Users/yomiry/StudioWorkspace/flutter_inspector/pubspec.yaml`：
  1. `name: flutter_inspector` → `name: flutter_inspector_kit`
  2. `version: 0.0.1` → `version: 0.1.0`
  3. 三個 URL 改指新 repo 名：
     ```yaml
     homepage: https://github.com/Yomiamy/flutter_inspector_kit
     repository: https://github.com/Yomiamy/flutter_inspector_kit
     issue_tracker: https://github.com/Yomiamy/flutter_inspector_kit/issues
     ```
  4. 在 `issue_tracker` 下方新增（AC10）：
     ```yaml
     topics:
       - debugging
       - developer-tools
       - network
       - logging
     ```
  5. `description` 不動（121 字元已達標）。
- **寫入檔案**：`pubspec.yaml`
- **驗證**：
  ```bash
  grep -E "^(name|version):" pubspec.yaml          # flutter_inspector_kit / 0.1.0
  grep -c "flutter_inspector_kit" pubspec.yaml      # 應為 4（name + 3 URL）
  grep -A4 "^topics:" pubspec.yaml                  # 4 個 topic
  ```
- **依賴**：T1。**可與 T3–T8 並行。**

---

#### T3：library 進入點檔名改名 `[機械]`

- **目標**：符合 pub convention：`lib/<package_name>.dart`。
- **步驟**：
  ```bash
  git mv lib/flutter_inspector.dart lib/flutter_inspector_kit.dart
  ```
  檔案內容**不需修改**（內部皆為 `export 'src/...'` 相對路徑）。
- **寫入檔案**：`lib/flutter_inspector.dart` → `lib/flutter_inspector_kit.dart`（rename only）
- **驗證**：
  ```bash
  ls lib/                       # 只有 flutter_inspector_kit.dart 與 src/
  head -3 lib/flutter_inspector_kit.dart   # 內容為相對 export，無 package: import
  ```
- **依賴**：T1。**可與 T2、T4–T8 並行。**

---

#### T4：example 更新（pubspec + import + lock 重生）`[機械]`

- **目標**：example app 指向新名稱並可解析依賴。
- **步驟**：
  1. 編輯 `example/pubspec.yaml`：
     - `description: "Example app demonstrating flutter_inspector usage."` → `"Example app demonstrating flutter_inspector_kit usage."`
     - 依賴名 `flutter_inspector:`（path: ../）→ `flutter_inspector_kit:`
  2. 編輯 `example/lib/main.dart`：
     `import 'package:flutter_inspector/flutter_inspector.dart';` → `import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';`
  3. 重生 lock：`cd example && flutter pub get`（example/pubspec.lock 第 153 行仍記舊名，需更新）
- **寫入檔案**：`example/pubspec.yaml`、`example/lib/main.dart`、`example/pubspec.lock`（pub get 自動產出）
- **驗證**：
  ```bash
  grep -rn "flutter_inspector" example/pubspec.yaml example/lib/ | grep -v "flutter_inspector_kit"   # 應為空
  grep -n "flutter_inspector_kit" example/pubspec.lock   # path dep 已更新
  ```
- **依賴**：T1。注意：步驟 3 的 `pub get` 解析 path 依賴時讀取根 pubspec 的 name，**若 T2 尚未完成會解析失敗** — 故步驟 1–2 可與 T2 並行，但**步驟 3 須等 T2 與 T3 完成後執行**（或整個 T4 排在 T2/T3 之後，最簡單）。
- **複雜度備註**：建議直接序列在 T2、T3 之後，消除這個特殊情況。

---

#### T5：test 檔 import 批次替換（23 檔、27 種 import 路徑）`[機械]`

- **目標**：所有 test 的 `package:flutter_inspector/...` import 改為新名稱。
- **步驟**（兩步精準替換，順序不可顛倒）：
  ```bash
  cd /Users/yomiry/StudioWorkspace/flutter_inspector
  # 步驟 1：umbrella import（檔名也變）
  grep -rl "package:flutter_inspector/flutter_inspector.dart" test | \
    xargs sed -i '' "s|package:flutter_inspector/flutter_inspector\.dart|package:flutter_inspector_kit/flutter_inspector_kit.dart|g"
  # 步驟 2：其餘 src import（僅前綴變）
  grep -rl "package:flutter_inspector/" test | \
    xargs sed -i '' "s|package:flutter_inspector/|package:flutter_inspector_kit/|g"
  ```
- **寫入檔案**：`test/**/*.dart`（23 檔，與其他任務互斥）
- **驗證**：
  ```bash
  grep -rn "package:flutter_inspector/" test/        # 應為空
  grep -rln "package:flutter_inspector_kit/" test/ | wc -l   # 23
  ```
- **依賴**：T1。**可與 T2、T3、T6–T8 並行。**

---

#### T6：README 更新 `[標準]`

- **目標**：安裝範例、import 範例、截圖 URL 更新為新名稱；**保留 channel ID 原文**。
- **步驟**：編輯 `README.md`：
  1. 第 30 行：`flutter_inspector: ^0.0.1` → `flutter_inspector_kit: ^0.1.0`
  2. 第 41 行：`import 'package:flutter_inspector/flutter_inspector.dart';` → `import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';`
  3. 第 18、22 行共 6 個截圖 URL：`github.com/Yomiamy/flutter_inspector/blob/...` → `github.com/Yomiamy/flutter_inspector_kit/blob/...`（repo 將同步改名；GitHub 對舊 URL 有 redirect，但 README 應指向正名）
  4. **第 133 行不動**：`flutter_inspector_network_v2` 是 Android channel ID，屬執行期識別字。
- **寫入檔案**：`README.md`
- **驗證**：
  ```bash
  grep -n "flutter_inspector" README.md | grep -v "flutter_inspector_kit" | grep -v "flutter_inspector_network"   # 應為空
  grep -c "flutter_inspector_network_v2" README.md   # 仍為 1（未被誤改）
  ```
- **依賴**：T1。**可與 T2–T5、T7、T8 並行。**
- **複雜度備註**：需判斷哪些字串該改/該留，標 `[標準]`。

---

#### T7：.pubignore 補排除規則 `[機械]`

- **目標**：修正 P1 問題 — `.pubignore` 存在時完全取代 `.gitignore`，需補上開發產物排除（現況 archive 19 MB，主因 `build/test_cache/*.dill` 62 MB）。
- **步驟**：在 `.pubignore` 既有內容（`docs/`、`.agents/`、`.claude/`、`.gemini/`、`.fvm/`）之後追加：
  ```
  build/
  coverage/
  scripts/
  doc/
  ```
  （`doc/screenshots` 截圖已用 GitHub raw URL，無需隨包散布；dotfile 類 pub 本來就自動排除。）
- **寫入檔案**：`.pubignore`
- **驗證**：`grep -c -E "^(build|coverage|scripts|doc)/$" .pubignore` 輸出 4。實質驗證在 T13 dry-run 檔案清單。
- **依賴**：T1。**可與 T2–T6、T8 並行。**

---

#### T8：CHANGELOG 收斂為 0.1.0 `[標準]`

- **目標**：`## Unreleased` 與 `## 0.0.1` 合併為 `## 0.1.0`，與 pubspec version 一致（AC5）。新 package 在 pub.dev 上沒有 0.0.1 歷史，保留兩段反而誤導。
- **步驟**：重寫 `CHANGELOG.md` 為單一段落：
  ```markdown
  ## 0.1.0

  Initial release on pub.dev (package renamed from `flutter_inspector` to `flutter_inspector_kit`).

  * Console, Network, Navigator, and Database inspectors behind a single unified API.
  * In-app overlay FAB and full-screen Dashboard.
  * `Dio` interceptor for network traffic capture.
  * `MagicalTap` widget for gesture-based invocation.
  * Network notification heads-up banner: silent heads-up on Android (HIGH priority channel) and foreground banner on iOS, with automatic dismissal and visual feedback.
  * Notification throttling: consecutive network calls within a 2-second window update the notification in place without re-alerting.
  * Android notification channel `flutter_inspector_network_v2` (HIGH importance); the legacy `flutter_inspector_network` channel is automatically deleted during upgrade.
  * Dio interceptor updates the pending request entry in place when its response or error arrives (no duplicate "Pending" entries); `logNetwork` gained an optional `replaces` parameter and returns the stored entry.
  ```
  注意：channel ID 兩處原文保留。
- **寫入檔案**：`CHANGELOG.md`
- **驗證**：
  ```bash
  grep -c "^## " CHANGELOG.md            # 1
  grep -n "Unreleased" CHANGELOG.md       # 空
  head -1 CHANGELOG.md                    # ## 0.1.0，與 pubspec version 對齊
  ```
- **依賴**：T1。**可與 T2–T7 並行。**
- **複雜度備註**：合併內容措辭屬編輯判斷，標 `[標準]`。

---

### Phase 2 — 本地驗證（序列執行，全部依賴 Phase 1 完成）

---

#### T9：全 repo 殘留檢查 `[機械]`

- **目標**：機械化確認改名零遺漏、零誤殺，便宜且快，放在跑 analyze/test 之前先擋低級錯誤。
- **步驟**：
  ```bash
  cd /Users/yomiry/StudioWorkspace/flutter_inspector
  # 1. 不得殘留舊 package import
  grep -rn "package:flutter_inspector/" lib test example README.md && echo "FAIL" || echo "OK"
  # 2. 舊進入點檔案不得存在
  test ! -f lib/flutter_inspector.dart && echo "OK"
  # 3. channel ID 未被誤改（lib 2 處 + README 1 處 + CHANGELOG）
  grep -rn "flutter_inspector_network_v2" lib/src/notifications/network_notifier.dart README.md CHANGELOG.md
  # 4. pubspec name/version
  grep -E "^(name|version):" pubspec.yaml
  ```
- **寫入檔案**：無
- **驗證**：上述 4 項全部符合預期。
- **依賴**：T2–T8 全部完成。

---

#### T10：flutter analyze + dart format `[機械]`

- **目標**：AC6 前半 — 0 issue、無 format diff。
- **步驟**：
  ```bash
  flutter analyze                                  # 0 issue
  dart format --output=none --set-exit-if-changed .   # exit 0
  ```
- **寫入檔案**：無（若 format 有 diff，僅允許套用 `dart format .` 後重驗，不得手改邏輯）
- **驗證**：兩指令 exit code 0。
- **依賴**：T9。

---

#### T11：flutter test — 排除 magical_tap_test 跑全套 `[標準]`

- **目標**：AC6 後半。本次 import 全面改動，所有測試都受影響、必須重跑；但依專案 memory，`test/ui/magical_tap_test.dart` 有既有 10 分鐘 timeout，**先排除它**避免拖垮整套。
- **步驟**：
  ```bash
  flutter test $(find test -name "*_test.dart" ! -name "magical_tap_test.dart" | tr '\n' ' ')
  ```
- **寫入檔案**：無
- **驗證**：全數通過。若失敗：先檢查是否 import 替換遺漏（回 T9 線索），**不得跳過或註解測試**。
- **依賴**：T10。

---

#### T12：magical_tap_test 單獨跑 `[標準]`

- **目標**：補齊 AC6 覆蓋。此檔 import 也被 T5 改動，必須重驗一次。
- **步驟**：
  ```bash
  flutter test test/ui/magical_tap_test.dart   # 預期含既有 10 分鐘 timeout 情境，耐心等待
  ```
- **寫入檔案**：無
- **驗證**：通過（timeout 設定屬已知既有狀態，非本次引入）。
- **依賴**：T10。**可與 T11 並行**（若 implementer 環境允許兩個 flutter test 行程；保守做法為序列在 T11 後）。

---

#### T13：flutter pub publish --dry-run + archive 驗證 `[標準]`

- **目標**：AC2 + AC3 — 0 error / 0 warning / 0 hint；內容乾淨；archive < 1 MB。
- **步驟**：
  ```bash
  flutter pub publish --dry-run 2>&1 | tee /tmp/dryrun.log
  ```
- **驗證**（判讀 /tmp/dryrun.log）：
  1. 結尾為 `0 warnings`、無 error/hint；改名後「version earlier than published」hint 應消失（新 package 無歷史版本）。
  2. 檔案清單**不含** `build/`、`coverage/`、`scripts/`、`doc/`、`docs/`。
  3. 輸出的 compressed archive 大小 < 1 MB。
- **寫入檔案**：無（`/tmp/dryrun.log` 為暫存，完成後刪除）
- **依賴**：T11、T12。

---

#### T14：（選做，AC8）pana 本機自評 `[標準]`

- **目標**：盡力項 — 無「Failed」項目。
- **步驟**：
  ```bash
  dart pub global activate pana
  dart pub global run pana --no-warning /Users/yomiry/StudioWorkspace/flutter_inspector 2>&1 | tail -40
  ```
- **驗證**：報告無 Failed。注意：pana 的 repository verification 在 repo 尚未改名前（T16 之前）可能對 URL 提出警告，屬預期，記錄即可、不阻擋。
- **寫入檔案**：無
- **依賴**：T13。**失敗不阻擋後續流程**（AC8 為盡力達成）。

---

### Phase 3 — 提交與外部操作（序列；⚠️ 項需使用者確認）

---

#### T15：commit 變更 `[機械]`

- **目標**：feature branch 上完成單一語意清楚的 commit。
- **步驟**：
  ```bash
  git add -A
  git diff --cached --stat   # 人工掃一眼：不應出現 lib/src 邏輯變更
  git commit -m "chore(release): rename package to flutter_inspector_kit and prepare 0.1.0 for pub.dev

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
  ```
- **寫入檔案**：無新檔（git commit）
- **驗證**：`git status` clean；`git log -1 --stat` 變更檔案清單符合 T2–T8 scope。
- **依賴**：T13（T14 不阻擋）。

---

#### T16：⚠️ GitHub repo 改名（外部不可逆，需使用者確認）`[機械]`

- **目標**：repo `Yomiamy/flutter_inspector` → `Yomiamy/flutter_inspector_kit`。
- **執行前確認**：總指揮須向使用者明示：「即將執行 `gh repo rename`，GitHub 會對舊 URL 建立自動 redirect（含 git remote 與網頁），但若未來有人以舊名建立新 repo，redirect 即失效。確認執行？」
- **步驟**：
  ```bash
  gh repo rename flutter_inspector_kit --repo Yomiamy/flutter_inspector --yes
  # gh 在 repo 目錄內執行時會自動更新本地 origin remote；仍需驗證：
  git remote -v
  # 若仍為舊 URL，手動更新：
  git remote set-url origin git@github.com:Yomiamy/flutter_inspector_kit.git
  ```
- **寫入檔案**：無（外部狀態 + git config）
- **驗證**：
  ```bash
  git remote -v                                   # 指向 flutter_inspector_kit
  gh repo view Yomiamy/flutter_inspector_kit --json name -q .name   # flutter_inspector_kit
  git fetch origin                                # 連線正常
  ```
- **依賴**：T15（先確保本地工作已 commit 再動外部狀態）。

---

#### T17：⚠️ push + PR merge 到 main（外部操作，需使用者確認）`[標準]`

- **目標**：AC7 — 改名後的 pubspec 進入 repo 預設分支，使 pub.dev repository verification 通過。
- **執行前確認**：總指揮須向使用者明示：「即將 push feature branch 並建立 PR merge 到 main，merge 後 main 即為發布基準。確認執行？」
- **步驟**：
  ```bash
  git push -u origin feature/202606/pubdev-publish-rename
  gh pr create --title "chore(release): rename to flutter_inspector_kit and prepare 0.1.0" \
    --body "$(cat <<'EOF'
  Rename package to flutter_inspector_kit and prepare first pub.dev release (0.1.0).

  - pubspec: name/version/URLs/topics
  - lib entry point renamed to lib/flutter_inspector_kit.dart
  - all package: imports updated (lib/example/test/README)
  - .pubignore: exclude build/, coverage/, scripts/, doc/
  - CHANGELOG consolidated into 0.1.0

  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  EOF
  )"
  # 經使用者同意後 merge：
  gh pr merge --merge
  ```
- **寫入檔案**：無
- **驗證**：`gh pr view --json state -q .state` 為 `MERGED`；`git fetch origin && git log origin/main -1` 含本次 commit；瀏覽 `https://github.com/Yomiamy/flutter_inspector_kit/blob/main/pubspec.yaml` name 為新名稱。
- **依賴**：T16（repo 先改名，PR 與 URL 直接落在正名 repo 上）。

---

#### T18：收尾 — 交棒使用者手動發布 `[機械]`

- **目標**：AC11 — 明確交棒，不自動執行。
- **步驟**：向使用者輸出最終指引：
  1. 在 main 分支、clean working tree 下執行 `flutter pub publish`（需 pub.dev OAuth 與最終 y/N 確認）。
  2. 發布後到 `https://pub.dev/packages/flutter_inspector_kit` 確認 README 截圖渲染（AC9）、Example tab、topics 顯示。
  3. （可選）`git tag v0.1.0 && git push origin v0.1.0` 建立 release tag。
  4. 清理：`git branch -d feature/202606/pubdev-publish-rename`、刪除 `/tmp/dryrun.log`。
- **寫入檔案**：無
- **依賴**：T17。

---

## 5. 依賴與並行總覽

```
T1 ──┬─→ T2 (pubspec.yaml)        ─┐
     ├─→ T3 (lib 檔名)             │
     ├─→ T5 (test imports)         ├─→ T9 → T10 ─┬─→ T11 ─┐
     ├─→ T6 (README)               │             └─→ T12 ─┴─→ T13 → (T14) → T15 → ⚠️T16 → ⚠️T17 → T18
     ├─→ T7 (.pubignore)           │
     ├─→ T8 (CHANGELOG)           ─┘
     └─→ T2,T3 ─→ T4 (example，pub get 需新 name 存在)
```

| 並行群組 | 任務 | 說明 |
|---|---|---|
| **群組 A（可同時跑）** | T2、T3、T5、T6、T7、T8 | 寫入檔案完全互斥；`pubspec.yaml` 僅 T2 寫入、`README.md` 僅 T6 寫入 |
| **群組 B** | T4 | 序列在 T2、T3 之後（`flutter pub get` 解析 path 依賴需根 pubspec 已是新名） |
| **群組 C（序列）** | T9 → T10 → T11/T12 → T13 → T14 | 驗證鏈；T11 與 T12 可並行（兩個 test 行程），保守則序列 |
| **群組 D（序列＋確認）** | T15 → T16 → T17 → T18 | T16、T17 為外部不可逆操作，執行前由總指揮向使用者確認 |

**預估並行收益**：群組 A 6 任務並行，Phase 1 牆鐘時間從 ~20 分鐘壓到 ~5 分鐘。

## 6. 執行方式選項（供使用者選擇）

### 選項 1：subagent-driven（建議）

單一 session 由總指揮依第 5 節依賴圖派發 subagent：群組 A 一批 6 個並行 subagent（全部 `[機械]`/`[標準]`，用快/標準 model），驗證鏈與外部操作由總指揮親自序列執行（需與使用者互動確認 T16/T17）。
- ✅ 依賴管理集中、外部操作的使用者確認流程自然。
- ✅ 任務多為機械性，subagent 成本低。

### 選項 2：parallel session（git worktree）

開多個 worktree session 分頭做群組 A，再回主 session 整合驗證。
- ❌ 本案任務粒度小（2–5 分鐘）、總量小，worktree 建立/整合的 overhead 大於收益。
- ❌ T4 依賴 T2/T3 跨 session 協調麻煩。
- **不建議**，除非使用者有其他並行工作要同時進行。

## 7. 風險與回滾

| 風險 | 緩解 |
|---|---|
| sed 誤殺 channel ID | 方向 B 的前綴錨定替換天然避開；T9 第 3 項機械驗證 |
| repo rename 後 redirect 失效（未來有人佔用舊名） | GitHub 行為，無法根治；舊名在自己帳號下可另建 archive 占位 repo（本次不做，記錄即可） |
| dry-run archive 仍超標 | T13 檔案清單會列出元兇，回 T7 補排除規則 |
| T16/T17 之前任何步驟失敗 | 全部為本地變更，`git checkout main && git branch -D feature/...` 即可完全回滾 |
| T16 之後想反悔 | `gh repo rename flutter_inspector` 可改回（redirect 同樣重建），但應避免反覆 |
