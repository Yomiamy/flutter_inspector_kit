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
git diff --stat
```

同時納入 staged 與 unstaged 變更。也要檢查屬於本次工作的 untracked 檔案。

### 2. 依功能單元將檔案分組

逐一檢視每個檔案的 `git diff` 內容以理解改了什麼，然後分群，使**同一群內所有檔案都服務於相同的邏輯目的**。

**分組原則：**

| 群組類型 | 典型檔案樣態 |
|---|---|
| `feat` | 新功能檔案 + 其直接對應的 tests |
| `refactor` | 跨相關檔案的樣式／常數／命名變更 |
| `test` | 僅 test 檔案（與實作解耦時） |
| `fix` | bug 修正檔案，通常範圍較窄 |
| `chore` | 設定、工具、Makefile、CI、lock 檔 |
| `build` / `ci` | build 腳本、pubspec、package.json、pipelines |
| `docs` | 僅文件的變更 |

**關鍵原則：** 一個 commit = 一個變更理由。若兩個檔案能用同一句話解釋，它們就該放在一起。

### 3. 排序 commits

依相依順序 commit —— 基礎性變更優先（例如設定先於產生的檔案、常數先於使用它們的 UI）。

### 4. 執行 commits

對每一群，只 stage 該群檔案並 commit：

```bash
git add <file1> <file2> ...
git commit -m "$(cat <<'EOF'
<type>(<optional scope>): <short imperative summary>

<optional body explaining why, not what>
EOF
)"
```

**訊息規則：**
- Type：`feat` / `fix` / `refactor` / `test` / `chore` / `build` / `ci` / `docs`
- Subject 行 ≤ 72 字元，使用祈使語氣（"add"、"fix"、"remove" —— 不要 "added"、"fixes"）
- Body：解釋*為何*或*改了什麼*，而非逐行摘要

### 5. 確認

所有 commit 完成後，執行 `git log --oneline -N`（N = 本次 commit 數量）並把結果呈現給使用者。

## 邊界情況

- **Untracked 檔案**：若明顯屬於某個邏輯單元就納入；除非產生檔或二進位檔正是 commit 的重點，否則略過。
- **單一邏輯變更**：一個 commit 即正確 —— 不要刻意拆分。
- **產生的檔案**（例如 `*.gen.dart`、`pubspec.lock`）：與觸發其產生的設定／原始碼分在同一群，而非獨立成群。
- **分組模糊時**：寧可較少、較廣的 commit，也不要許多難以理解的微型 commit。
