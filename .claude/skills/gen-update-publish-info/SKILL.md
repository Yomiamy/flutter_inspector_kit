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

### 1. 從 main 開 release 分支

分支命名固定格式 `release/release-<version>`：

```bash
git checkout -b release/release-$VERSION main
```

> **禁止**直接在 main 上 commit 版號變更——一律走分支 + PR。

### 2. 更新三處版本資訊

| 檔案 | 改什麼 |
|------|--------|
| `pubspec.yaml` | `version: <舊版>` → `version: $VERSION` |
| `README.md` | (a) 安裝範例 `flutter_inspector_kit: ^<舊版>` → `^$VERSION`（依實際 package 名）；(b) 把本次 release 影響「怎麼用」的新功能同步進對應章節（見步驟 3） |
| `CHANGELOG.md` | 在最上方新增 `## $VERSION` 區塊（見步驟 4） |

### 3. 同步 README 的功能描述

版號改完後，檢查本次 release 是否有功能需要在 README 反映。**範圍：只同步會影響使用者「怎麼用」的改動**——新 API、新建構子參數、新 Usage 步驟、既有用法的行為變更。純視覺/內部微調（如某個 icon、顏色、private helper）**不**強制寫進 README。

```bash
git log --oneline <上個 tag 或 main 分歧點>..HEAD   # 對照本次 release 的 commits
grep -n "^## \|^### " README.md                     # 盤點 README 既有章節結構
```

逐項判斷與落點：

- **新 API / 新參數**：在 README 對應的 Usage / Features 章節補上用法（程式碼範例 + 一句說明）。若 README 有頂部 Features 清單，也補一行。
- **既有用法的行為變更**：找到 README 描述舊行為的段落，**就地更新**，不要新增重複段落，也不要留下與現狀矛盾的舊描述。
- **移除的 API**：把 README 中引用該 API 的段落一併刪除或改寫，避免文件指向不存在的東西。
- **只是 bug fix / 視覺微調**：通常 README 無需改，跳過即可。

> 判準與 CHANGELOG 一致但更嚴：CHANGELOG 收「使用者可見」，README 只收「**改變使用方式**」的子集。寫進 README 的東西要能回答「使用者要怎麼用到它」。

### 4. 撰寫 CHANGELOG 區塊

分析 release 涵蓋的 commits，**只收錄使用者可見的改動**，依類別分組（沿用既有 CHANGELOG 的英文 + `### Added/Changed/Fixed` 慣例）：

```bash
git log --oneline <上個 tag 或 main 分歧點>..HEAD
git show <sha> --stat --format="%s%n%n%b"   # 逐個確認 commit 實際做了什麼
```

- **Added**：新功能、新 API。
- **Changed**：既有行為調整。
- **Fixed**：bug 修正。
- **排除純內部 refactor**（如重構 private helper 簽名）——使用者不可見，不寫進 CHANGELOG。
- 描述要具體：寫「Status 列 value 與其他欄位對齊」而非「修了個 UI bug」。

### 5. 驗證、commit、push、開 PR

```bash
git diff                          # 親自核對三處變更正確（含 README 功能同步）
git add pubspec.yaml README.md CHANGELOG.md
git commit -m "chore(release): bump version to $VERSION"
git push -u origin release/release-$VERSION
gh pr create --base main --title "chore(release): bump version to $VERSION" --body "<摘要>"
```

⏸ **暫停點**：展示 PR 連結，問使用者要自行 review 合併，還是要 skill 幫忙 `gh pr merge`。

### 6. 合併後才打 tag（順序不可顛倒）

PR 合併進 main 後：

```bash
git checkout main && git pull --ff-only origin main
grep "^version:" pubspec.yaml     # 驗證 main 上版號 = $VERSION
git tag -a $TAG -m "Release $TAG" <merge-commit-sha>
git push origin $TAG
git ls-remote --tags origin $TAG  # 驗證 tag 已上 remote
```

- tag 打在**合併後的 merge commit** 上，不是 release 分支的 commit。
- 用 annotated tag（`-a`），tag message 簡述本次 release 重點。

## 完成後

報告：PR 連結、tag、main 版號驗證結果。**主動提醒**使用者：打 tag **不等於**發布到 pub.dev；若需發布套件需另外手動跑 `flutter pub publish`（可先 `--dry-run` 驗證）。

## Quick Reference

| 步驟 | 關鍵動作 | 守則 |
|------|---------|------|
| 前置 | 同步 main、確認 PR MERGED、工作區乾淨 | 變更必須已在 main |
| 開分支 | `release/release-$VERSION` from main | 不在 main 直接工作 |
| 改版號 | pubspec / README 安裝版號 / CHANGELOG | 三處都要改 |
| 同步 README 功能 | 把改變「怎麼用」的新功能補進 README 對應章節 | 只收改變使用方式的子集，視覺微調可略 |
| CHANGELOG | 新增 `## $VERSION` 區塊 | 只收使用者可見改動 |
| PR | commit + push + `gh pr create` | 暫停讓使用者決定合併方式 |
| tag | 合併後打在 merge commit、push | **先合併才打 tag** |

## Common Mistakes

| 錯誤 | 正解 |
|------|------|
| 在 PR 合併前就打 tag | 一律「合併進 main → 打 tag」，順序不可顛倒 |
| tag 打在 release 分支 commit 上 | 打在 main 的 merge commit 上 |
| 把內部 refactor 寫進 CHANGELOG | 只寫使用者可見的 Added/Changed/Fixed |
| 自己猜版號 | 版號由使用者指定，未提供就問 |
| 直接在 main commit 版號 | 走 `release/release-<version>` 分支 + PR |
| 順手跑 `flutter pub publish` | 不在範圍內；只提醒使用者，由其手動執行 |
| 忘記改 README 的安裝版號 | pubspec / README / CHANGELOG 三處都要改 |
| 只 bump 版號，沒把新功能寫進 README | 影響「怎麼用」的新 API/參數/用法要同步進 README 對應章節 |
| README 把每個 bug fix/視覺微調都寫一遍 | README 只收改變使用方式的子集；視覺/內部微調交給 CHANGELOG |
| 新增重複段落或留下與現狀矛盾的舊描述 | 行為變更要「就地更新」既有段落；移除的 API 一併從 README 刪除 |
