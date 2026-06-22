---
name: gen-pr-comment
description: |
  分析指定 branch 到 main 的差異，並依照 pr-comment.md 格式產出 PR comment 寫入 pr-desc.md。
  觸發條件：gen pr-comment <branch-name>
allow-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Generate PR Comment

## 解析 Branch Name

從觸發指令中解析 branch name。
- 輸入格式：`gen pr-comment <branch-name>`
- 範例：`gen pr-comment fix/202603/BUG-1704-addon_confirm_button_initial_disabled`
- 若未提供 branch name，詢問使用者輸入。

將解析到的 branch name 記為 `$BRANCH`。

---

## 執行步驟

### 1. 確認 branch 存在

```bash
git branch -a | grep "$BRANCH"
```

若不存在，報錯並停止。

---

### 2. 取得 diff 摘要

```bash
# 取得變更的檔案列表
git diff main...$BRANCH --name-status

# 取得完整 diff（含內容）
git diff main...$BRANCH

# 取得 commit 訊息
git log main..$BRANCH --oneline
```

---

### 3. 讀取 PR comment 參考格式
讀取 `reference/pr-comment.md`，理解格式與寫作風格：
- `**[修正問題]**`：描述原本的問題與背景
- `**[修正方式]**`：條列說明修正的具體做法、邏輯流程

---

### 4. 分析變更並撰寫 PR Comment

依據 diff 內容，按照 `pr-comment.md` 的格式撰寫：

```markdown
**[修正問題]**

<描述這個 branch 解決了什麼問題，原本的行為是什麼，為何需要修正>

**[修正方式]**

<條列說明修正的具體方式，包含：
- 修改了哪些檔案/類別/方法
- 邏輯判斷的前後變化
- 關鍵的判斷順序或流程（若有）>
```

撰寫原則：
- 使用繁體中文
- 問題描述要說明「原本行為」與「預期行為」的差異
- 修正方式要具體，包含程式碼層面的說明（類別名稱、欄位名稱）
- 避免泛泛而談，聚焦在核心邏輯變化

---

### 5. 寫入 pr-desc.md

將完成的 PR comment 寫入 `eslite_v3/pr-desc.md`（**覆蓋**既有內容）：

```bash
# 確認路徑
ls eslite_v3/pr-desc.md
```

使用 Write tool 將內容寫入 `eslite_v3/pr-desc.md`。

---

### 6. 輸出確認

完成後輸出：
```
✅ PR comment 已寫入 eslite_v3/pr-desc.md
Branch: <branch-name>
變更檔案數：<n>
```

並在終端顯示寫入的內容摘要（前幾行），讓使用者確認格式正確。
