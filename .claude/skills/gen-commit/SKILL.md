---
name: gen-commit
description: 分析 unstaged/staged 的 git 變更，依功能相關性將檔案分組，並建立多個語意化的單元 commit。當使用者說 "commit"、"gen-commit"、"依功能 commit"、"幫我 commit"、"進行功能單元 commit"，或任何要求智慧分組並 commit 目前變更的變體時使用。也適用於使用者想把變更檔案以有意義、結構良好、依功能領域組織的訊息 commit 時。
---

# gen-commit

分析目前的 git 變更，依功能相關性將檔案分組，並執行多個語意化 commit —— 每個邏輯單元一個 commit。

## 工作流程

### 1. 檢視變更

```bash
git status
git diff -U0
```

要讀實際的 diff 內容，不能只看 `--stat`。同時納入 staged 與 unstaged 變更，以及屬於本次工作的 untracked 檔案。

### 2. 依「變更意圖」分組（而非依檔案）

**分組的單位是變更，不是檔案。** 一個檔案可以承載數個互不相干的意圖，每個意圖都該有自己的 commit。把每個 hunk 分群，使**同一群內所有變更都服務於相同的邏輯目的**。

**分組原則：**

| 群組類型 | 典型變更 |
|---|---|
| `feat` | 新功能程式碼 + 其直接對應的 tests |
| `refactor` | 跨相關檔案的樣式／常數／命名變更 |
| `test` | 僅 test 檔案（與實作解耦時） |
| `fix` | bug 修正，通常範圍較窄 |
| `chore` | 工具、Makefile、lock 檔、雜項維護 |
| `build` / `ci` | 相依與工具鏈設定、pipelines |
| `docs` | 僅文件的變更 |

**關鍵原則：** 一個 commit = 一個變更理由。若兩個變更需要兩句不同的話才解釋得清楚，它們就該是兩個 commit —— 即使它們住在同一個檔案裡。

#### 常見「單檔多意圖」的檔案

以下檔案要**依區塊拆分**，每個有變動的區塊各自一個 commit：

| 檔案 | 區塊 | Commit |
|---|---|---|
| `pubspec.yaml` | `version:` | `chore(release): bump version to x.y.z` |
| | `dependencies:` | `build(deps): add/bump <package>` |
| | `dev_dependencies:` | `build(deps-dev): add/bump <package>` |
| | `environment:`（sdk / flutter 約束） | `build(env): raise Dart SDK floor to x.y` |
| | `flutter:` → `assets:` / `fonts:` | `chore(assets): register <asset>` |
| | `description` / `homepage` / `repository` | `docs(meta): update package metadata` |
| `package.json` | `dependencies` vs `scripts` vs metadata | `build(deps)` / `chore(scripts)` / `docs(meta)` |
| `analysis_options.yaml` | 新增 lint rule vs 排除路徑 | `chore(lint)` / `chore(analysis)` |
| CI workflow yaml | 新增 job vs 調整既有 job | 每個 job 各自 `ci(<job>)` |
| Barrel / export 檔 | 每個匯出的符號 | 跟著引入該符號的功能走 |
| 共用常數檔 | 每個常數 | 跟著它的使用端走 |

#### 什麼時候不該拆

拆分有硬底線 —— **每個 commit 都必須能獨立編譯並通過測試**：

- 新增相依 + 使用該相依的程式碼 → **同一個 commit**（拆開會讓中間那筆編不過）。
- 同一個 hunk 內的變更 → 同一個 commit；hunk 是能取得的最細粒度。
- 機械性連帶變更（rename 波及、`dart format`、重新產生的 `*.g.dart`）→ 跟著造成它的變更走。
- `pubspec.lock` → 跟著造成它變動的 `dependencies:` commit 走。

### 3. 排序 commits

依相依順序 commit —— 基礎性變更優先（例如 `environment:` 先於 `dependencies:`、`dependencies:` 先於使用它們的程式碼、常數先於使用它們的 UI）。

### 4. 執行 commits

若整個檔案只服務單一意圖，直接 stage 檔案：

```bash
git add <file1> <file2> ...
```

若某個檔案承載多個意圖，只 stage 對應的 hunk。`git add -p` 是互動式的、此環境無法使用，改用 patch 檔：

```bash
git diff -U0 -- <file> > /tmp/split.patch    # 每一輪都要重新產生，行號會自動對齊
# 編輯 /tmp/split.patch：只保留「本次 commit」要的 hunk，保留開頭 3 行檔頭
git apply --cached --unidiff-zero /tmp/split.patch
```

`--unidiff-zero` 是必要的 —— 少了它 `git apply` 會拒絕零 context 的 patch。commit 前先用 `git diff --cached` 確認內容；剩下的 hunk 會留在 unstaged，供下一輪使用。

接著 commit：

```bash
git commit -m "$(cat <<'EOF'
<type>(<optional scope>): <short imperative summary>

<optional body explaining why, not what>
EOF
)"
```

**訊息規則：**
- Type：`feat` / `fix` / `refactor` / `test` / `chore` / `build` / `ci` / `docs`
- Scope：標示受影響的*區域*而非檔案 —— 用 `build(deps)` 而非 `build(pubspec)`。當一個檔案拆成多筆 commit 時，scope 就是區分它們的依據。
- Subject 行 ≤ 72 字元，使用祈使語氣（"add"、"fix"、"remove" —— 不要 "added"、"fixes"）
- Body：解釋*為何*或*改了什麼*，而非逐行摘要

### 5. 確認

所有 commit 完成後，執行 `git log --oneline -N`（N = 本次 commit 數量）並把結果呈現給使用者。

## 邊界情況

- **Untracked 檔案**：若明顯屬於某個邏輯單元就納入；除非產生檔或二進位檔正是 commit 的重點，否則略過。
- **單一邏輯變更**：一個 commit 即正確 —— 因單一理由而修改的檔案就維持一個 commit。依意圖拆分，絕不依行數拆分。
- **產生的檔案**（例如 `*.gen.dart`、`pubspec.lock`）：與觸發其產生的設定／原始碼分在同一群，而非獨立成群。
- **分組模糊時**：若你無法用兩句不同的話說出那兩個意圖，那就是同一個意圖 —— 放在一起。最終裁決標準是 build：只有在拆完後每個 commit 都仍能獨立編譯並通過測試時才拆。
