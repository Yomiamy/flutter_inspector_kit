---
name: gen-pr-reply
description: 讀取 GitHub PR 的 review inline comments，自行判斷每則意見是否需要修復——技術正確且合理者修復後 commit、push 並回覆附 commit SHA；不需修復者直接以中文回覆技術理由。觸發時機：使用者說「回覆 PR comment」、「針對 review 回覆修正」、「gen-pr-reply PR {number}」，或要針對 code review 的每個 inline comment 回覆修正 commit。
---

# gen-pr-reply

讀取 PR inline comments → 自主技術判斷 → 該修就修、commit、push、回覆 SHA → 不該修就 pushback 並回覆理由。

## 核心原則

**如同 receiving-code-review：外部 review 是待評估的建議，不是必須服從的命令。**

- **驗證優先**：先查 codebase 現況，不盲從
- **技術判斷**：基於程式碼事實決定修或不修
- **零表演**：不寫感謝語、不客套、不「You're absolutely right」
- **行動代替廢話**：該修就直接修，不需冗長解釋為何同意

## 流程

### 1. 取得必要資訊

同時執行：

```bash
# repo 名稱（不可假設）
gh repo view --json nameWithOwner

# PR inline comments（含 comment id、path、diff_hunk、body）
gh api repos/{owner}/{repo}/pulls/{pr}/comments

# 近期 commits（識別已修正項目）
git log --oneline -20
```

### 2. 建立 comment 清單

整理所有 inline comments，每則包含：
- `comment_id`、`path`、`body`、`diff_hunk`
- 同一 thread 的 comments 視為同一主題，以最後一則未回覆的意見為準

### 3. 自主評估每則 comment

對每一則 comment，**自行**執行以下判斷流程：

```
FOR each comment:
  1. READ: 完整理解 review 意見
  2. VERIFY: 讀取被評論的檔案，查看目前程式碼狀態
  3. EVALUATE:
     - 技術上正確嗎？（對 THIS codebase）
     - 會破壞現有功能嗎？
     - 當初這樣寫的理由是什麼？
     - 是否違反 YAGNI？（建議加的東西根本沒用到）
     - 是否與專案架構決策衝突？
  4. DECIDE: 修 or 不修
```

### 4. 判斷結果分類與行動

| 判斷 | 條件 | 行動 |
|------|------|------|
| **🔧 需要修復** | 意見技術正確、確實改善程式碼品質 | 修 code → commit → push → 回覆附 SHA |
| **✅ 已修正** | git log 中已有對應修正 commit | 直接回覆指向該 commit |
| **⛔ 不需修復** | 意見技術錯誤、缺乏上下文、違反 YAGNI、或與架構決策衝突 | 回覆技術理由 pushback |
| **🔄 設計如此** | 現行實作是有意的設計決策 | 回覆說明設計理由 |

### 5. 修復流程（當判斷為「需要修復」）

1. **實作修復**——用 code edit 工具修改程式碼
2. **驗證**——必要時跑相關測試確認不 break
3. **Commit**——僅 stage 本次修復相關檔案：
   ```bash
   git add <修改的檔案>
   git commit -m "<type>(<scope>): <修復摘要>"
   ```
4. **Push**：
   ```bash
   git push
   ```
5. **回覆** comment thread（見步驟 7）

> **合併修復**：多則 comment 指向相同問題時，合併為一次修復、一個 commit。
> 在所有相關 comment thread 各回覆一則，指向同一個 SHA。

### 6. Pushback 流程（當判斷為「不需修復」）

直接回覆 comment thread，說明技術理由：

- 引用具體程式碼或 commit 作為證據
- 若涉及架構決策，說明設計意圖
- 若意見基於誤解，指出實際行為

### 7. 回覆方式（inline thread reply）

**必須 reply 到 comment thread**，不可發頂層 PR comment：

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies \
  -X POST \
  -f body="{中文內容}"
```

回覆格式：

- **已修正**：`已修正，對應 commit \`{sha7}\`。{一句話說明修正內容}`
- **設計如此**：`{說明設計決策與技術理由}`
- **Pushback**：`{指出為何不適用，引用程式碼或事實}`

### 8. 呈現處理摘要

所有 comments 處理完畢後，向使用者展示：

```
處理結果：
  🔧 已修復並回覆：N 則
  ✅ 已修正（既有 commit）：M 則
  ⛔ Pushback（不需修復）：K 則
  🔄 設計如此：J 則
```

若有任何新 commit，顯示 `git log --oneline -N`。

## 規則

- **自主判斷**：不逐一問使用者，自行決定修或不修——但判斷必須基於 codebase 事實
- **逐一回覆**：每則 comment 對應一個 reply，不合併回覆（修復 commit 可合併）
- **commit 訊息**：conventional commits 格式，主旨行 ≤ 72 字元，不附署名 trailer
- **SHA 用 7 位短碼**
- **push 時機**：每批修復 commit 後立即 push，確保 SHA 在 remote 可見
- **回覆語言**：中文，聚焦技術事實，禁止感謝語或客套話
- **找不到明確 commit 時**，如實說明，不亂填 SHA
- **不確定時寧可保守**：無法驗證的建議，向使用者說明限制再決定
