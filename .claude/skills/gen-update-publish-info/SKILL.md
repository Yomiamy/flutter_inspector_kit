---
name: gen-update-publish-info
description: 當使用者要為已合入 main 的變更發布新版本——更新版號（pubspec.yaml / README.md）、把使用者可見的新功能同步進 README、補上 CHANGELOG、並打 git tag 推上去時使用。觸發語如「更新版本資訊」、「bump 版號」、「調整版號為 vX.Y.Z 下 tag push」、「release vX.Y.Z」、「gen-update-publish-info vX.Y.Z」。
---

# Gen Update & Publish Info

依使用者指定的新版號，為**已合入 main 的變更**更新版本資訊並打 tag。範圍止於 push tag——**不執行 `flutter pub publish`**（互動認證且不可逆，留給使用者手動）。

## 觸發與輸入

- 輸入格式：`gen-update-publish-info <version>`，例如 `gen-update-publish-info v0.2.4` 或 `0.2.4`。
- 版號由**使用者明確指定**，skill 不自行猜測或從 commit 推導。未提供時，向使用者詢問目標版號。
- 記正規化後的版號：`$VERSION`（純語意版號，如 `0.2.4`）、`$TAG`（如 `v0.2.4`）。

## 前置檢查（缺一不可）

```bash
git branch --show-current        # 確認所在分支
git status --short               # 工作區必須乾淨；有未 commit 變更先停下問使用者
gh pr view <PR> --json state,mergedAt   # 若變更來自某 PR，確認已 MERGED
git checkout main && git pull --ff-only origin main   # 同步最新 main
grep "^version:" pubspec.yaml     # 確認當前版號
```

- **變更必須已在 main 上**。若對應 PR 尚未合併，停下告知使用者，不在未合併狀態打 tag。
- 工作區不乾淨 → 停，不要把無關變更混進 release commit。

## 流程

### 1. 建立 Release Issue（追蹤發布任務）

在建立 release 分支前，必須先在 GitHub 建立一個 Issue 來記錄本次更新任務。

#### 1.1 生成 Issue 描述內容
Issue 內容格式參考 `gen-gh-issue` 的五區段格式（用繁體中文撰寫，但保留必要的英文術語）：

```markdown
## 問題描述 (Problem)
需要發布新版本 $VERSION，將最近合併入 main 的核心變更打包，並更新版本號與說明文件。

## 根本原因（已驗證）(Root cause - verified)
目前的 `pubspec.yaml` 版本為 <舊版>，未包含最新變更，且 `README.md` 及 `CHANGELOG.md` 尚未同步最新 API 變動。

## 修復方案 (Fix)
- **A** `pubspec.yaml`：升級 `version` 至 `$VERSION`。
- **B** `README.md`：同步最新安裝版號，並更新用法說明（特別是 Dio 攔截器變更）。
- **C** `CHANGELOG.md`：新增 `$VERSION` 的 Added/Changed/Fixed 異動清單。

## 排除範圍 (Out of scope)
- 執行 `flutter pub publish`（由使用者後續手動發布）。

## 驗證方式 (Verification)
- `flutter analyze` 確保專案無 warning/error。
- `flutter test` 確保所有單元與 Widget 測試全綠。
```

#### 1.2 建立 Issue
執行以下指令建立 Issue 並取得分配的 `$ISSUE_ID`：
```bash
gh issue create --title "Release: Version $VERSION" --body "<上述生成的 Issue Body Markdown>"
```

### 2. 從 main 開 release 分支

分支命名固定格式 `release/release-$VERSION`：

```bash
git checkout -b release/release-$VERSION main
```

> **禁止**直接在 main 上 commit 版號變更——一律走分支 + PR。

### 3. 更新三處版本資訊

| 檔案 | 改什麼 |
|------|--------|
| `pubspec.yaml` | `version: <舊版>` → `version: $VERSION` |
| `README.md` | (a) 安裝範例 `flutter_inspector_kit: ^<舊版>` → `^$VERSION`（依實際 package 名）；(b) 把本次 release 影響「怎麼用」的新功能同步進對應章節（見步驟 4） |
| `CHANGELOG.md` | 在最上方新增 `## $VERSION` 區塊（見步驟 5） |

### 4. 同步 README 的功能描述

版號改完後，檢查本次 release 是否有功能需要在 README 反映。**範圍：只同步會影響使用者「怎麼用」的改動**——新 API、新建構子參數、新 Usage 步驟、既有用法的行為變更。

```bash
git log --oneline <上個 tag 或 main 分歧點>..HEAD   # 對照本次 release 的 commits
grep -n "^## \|^### " README.md                     # 盤點 README 既有章節結構
```

#### 特別要求：多 Dio 實例接線說明
> [!IMPORTANT]
> 如果本次 Release 涉及網路攔截器（`FlutterInspectorDioInterceptor`）的用法變更，**在 `README.md` 中必須特別強調並示範「多個不同 Dio 實例」的接線情況**（例如 `authDio` 與 `publicDio`），說明如何傳入各自的 `sourceDio`，避免文檔只示範單一 Dio 實例而造成使用者誤解。

逐項判斷與落點：
- **新 API / 新參數**：在 README 對應的 Usage / Features 章節補上用法（程式碼範例 + 一句說明）。若 README 有頂部 Features 清單，也補一行。
- **既有用法的行為變更**：找到 README 描述舊行為的段落，**就地更新**，不要新增重複段落，也不要留下與現狀矛盾的舊描述。
- **移除的 API**：把 README 中引用該 API 的段落一併刪除或改寫，避免文件指向不存在的東西。
- **只是 bug fix / 視覺微調**：通常 README 無需改，跳過即可。

### 5. 撰寫 CHANGELOG 區塊

分析 release 涵蓋的 commits，**只收錄使用者可見的改動**，依類別分組（沿用既有 CHANGELOG 的英文 + `### Added/Changed/Fixed` 慣例）：

- **Added**：新功能、新 API。
- **Changed**：既有行為調整。
- **Fixed**：bug 修正。
- **排除純內部 refactor**（如重構 private helper 簽名）——使用者不可見，不寫進 CHANGELOG。

### 6. 使用 gen-pr 規範產出 PR 描述並關聯 Issue

#### 6.1 生成 PR 描述草稿
PR 描述格式必須嚴格遵循 `gen-pr` skill 的規範，以繁體中文撰寫，包含連結至剛才建立的 Release Issue，並 wrapped 於 fenced `md` code block 中：

```markdown
### Summary
[#$ISSUE_ID](https://github.com/Yomiamy/flutter_inspector_kit/issues/$ISSUE_ID) Release: Version $VERSION

**[修正問題]**
發布新版 `$VERSION`，整合最近合併入 `main` 的網路請求重放（Network Replay）等變更，並同步更新 `pubspec.yaml`、說明文檔與變更日誌。

**[修正方式]**
1. **`pubspec.yaml`**：更新版本號為 `$VERSION`。
2. **`README.md`**：更新安裝版號為 `^$VERSION`，新增多 Dio 實例的攔截器接線說明與 Replay 功能用法。
3. **`CHANGELOG.md`**：新增 `$VERSION` 的版本日誌，分類記錄各項 Added/Changed/Fixed 異動。
```

#### 6.2 暫停與發布
1. **暫停點**：展示 PR 描述草稿，詢問使用者是否確認。
2. **建立 PR**：使用者確認後，執行以下指令將分支推送到 remote 並建立 PR：
   ```bash
   git add pubspec.yaml README.md CHANGELOG.md
   git commit -m "chore(release): bump version to $VERSION"
   git push -u origin release/release-$VERSION
   gh pr create --base main --head release/release-$VERSION --title "chore(release): bump version to $VERSION" --body "<上述生成的 PR Body Markdown>"
   ```
3. **暫停點**：展示 PR 連結，問使用者要自行 review 合併，還是要 skill 幫忙 `gh pr merge`。

### 7. 合併後才打 tag（順序不可顛倒）

PR 合併進 main 後：

```bash
git checkout main && git pull --ff-only origin main
grep "^version:" pubspec.yaml     # 驗證 main 上版號 = $VERSION
git tag -a $TAG -m "Release $TAG" <merge-commit-sha>
git push origin $TAG
git ls-remote --tags origin $TAG  # 驗證 tag 已上 remote
```

- tag 打在**合併後的 merge commit** 上，不是 release 分支的 commit。
- 用 annotated tag（`-a`），tag message 簡述本次 release重點。

## 完成後

報告：PR 連結、tag、main 版號驗證結果。**主動提醒**使用者：打 tag **不等於**發布到 pub.dev；若需發布套件需另外手動跑 `flutter pub publish`（可先 `--dry-run` 驗證）。

## Quick Reference

| 步驟 | 關鍵動作 | 守則 |
|------|---------|------|
| 建立 Issue | 以 `gen-gh-issue` 五區段格式用 `gh issue create` 建立 release 追蹤 issue | 必先有 issue 記錄任務 |
| 開分支 | `release/release-$VERSION` from main | 不在 main 直接工作 |
| 改版號 | pubspec / README 安裝版號 / CHANGELOG | 三處都要改 |
| 多 Dio 示範 | 在 README 特別強調多個不同 Dio 實例的攔截器配置 | 確保文檔能對應真實的多 Dio 情境 |
| PR | 用 `gen-pr` 格式（Summary / 修正問題 / 修正方式）建 PR 且關聯 Issue | 確保 PR 的雙向關聯 |
| tag | 合併後打在 merge commit、push | **先合併才打 tag** |
