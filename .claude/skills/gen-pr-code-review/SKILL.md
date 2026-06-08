---
name: gen-pr-code-review
description: |
  對 PR 或指定 Branch 進行深度代碼審查，僅將修改建議顯示在 Terminal 中。
  觸發條件：gen pr-review <pr-number/branch-name>
allow-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Generate PR Code Review (Terminal Only)

## 指令解析

- 輸入格式：`gen pr-review <pr-number/branch-name>`
- 範例：`gen pr-review 961` 或 `gen pr-review fix/bug-1920-store-reservation-missing-tab-bar`

若輸入為數字，則視為 PR 號碼；若輸入為字串，則視為 Branch 名稱。

---

## 執行步驟

### 1. 獲取變更內容 (Fetch & Diff)

#### 若為 PR 號碼：
使用 `gh pr view` 獲取 PR 資訊，並 fetch 分支：
```bash
gh pr view <PR_NUMBER> --json number,title,body,headRefName,baseRefName
# 獲取 $HEAD_REF_NAME
git fetch origin $HEAD_REF_NAME:$HEAD_REF_NAME
git diff main...$HEAD_REF_NAME
```

#### 若為 Branch 名稱：
```bash
git fetch origin <BRANCH_NAME>:<BRANCH_NAME>
git diff main...<BRANCH_NAME>
```

---

### 2. 深度代碼分析

讀取 `code-review-commons` 技能與 `RULES.md` 作為標準：
- **Persona**：Principal Software Engineer / Code Review Architect。
- **Focus**：邏輯正確性、架構分層、效能、安全性、可維護性。
- **Rules**：
    - 嚴格遵守 `RULES.md` 的分層架構（Presentation -> Domain -> Data）。
    - 檢查命名規範、DI 注入、Retrofit 封裝、BLoC 狀態管理。

---

### 3. 輸出審查建議 (Terminal Only)

將審查建議直接輸出在 Terminal 中。**禁止調用任何 API 往 PR 提交 comment。**

輸出格式：
```markdown
### PR Code Review: [PR Title / Branch Name]

#### [檔案名稱]
- **Severity**: [CRITICAL/HIGH/MEDIUM/LOW]
- **Issue**: [簡短描述問題]
- **Suggestion**: [提供具體的重構建議或代碼片段]
```

---

## 審查重點清單 (Checklist)

1. **架構分層**：UI 是否直接調用 Data 層？UseCase 是否依賴 Repository 介面？
2. **錯誤處理**：Retrofit/API 請求是否有 try-catch 或 error handling？
3. **狀態管理**：BLoC State 是否具備 `copyWith`、`props` 並包含 `status` 欄位？
4. **效能優化**：是否存在 N+1 查詢？Widget rebuild 是否過於頻繁？
5. **程式碼壞味**：是否有硬編碼的索引（如 `index == 3`）或魔法數字？
6. **測試覆蓋**：核心邏輯是否有對應的 Unit Test (Success/Failure)？

---

## 注意事項

- **絕對禁止**：向 GitHub 提交任何 Review Comment。
- **使用語言**：繁體中文 (Traditional Chinese)。
- **精準定位**：建議應具體到類別、方法或變數名稱。
