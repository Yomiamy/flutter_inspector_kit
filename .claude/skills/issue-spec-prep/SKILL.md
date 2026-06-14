---
name: issue-spec-prep
description: 在 branch-ticket-issue-doc 已於選定的開發工作區建立 docs/issues/<ticket-id>.md，且 Codex 需建立或更新 docs/issues/specs/<ticket-id>.md 作為該 issue 的實作 spec 時使用此 skill；先讀 issue doc，僅在需要時檢視程式碼，且不進行程式碼實作變更。
---

# Issue Spec Prep

在 `branch-ticket-issue-doc` 之後使用此 skill。

目標：從 issue 文件與當前 worktree 程式碼脈絡，建立或更新 `docs/issues/specs/<ticket-id>.md`。

不要在此變更產品程式碼。不要在此執行實作重構。

## 前置條件

1. 確認當前目錄是 `ticket-id-dev-prep` 選定的開發工作區。
2. 從使用者輸入、branch 名稱或既有 issue docs 解析 ticket id。
3. 先讀取 `docs/issues/<ticket-id>.md`。
4. 若 issue doc 缺少，停止並先執行 `branch-ticket-issue-doc`。
5. 若 `docs/issues/specs/` 不存在則建立。

## 工作流程

1. 讀取 `docs/issues/<ticket-id>.md`。
2. 擷取：
   - 問題陳述
   - 預期與實際行為
   - 受影響的流程
   - 已知事實、推論與未解問題
3. 只檢視足以讓 spec 可執行的程式碼：
   - 可能的檔案或模組
   - 當前邏輯邊界
   - 既有 tests 或缺漏的測試面
   - 共用工具或重複的流程
4. **agy 優先策略**：收集完 issue doc 內容與程式碼觀察後，優先委派 antigravity-cli（`agy`）生成 spec 文件本文：
   - 透過 Bash 以 stdin 管道委派（`printf '%s' "<填入下方 prompt>" | agy -p --print-timeout 180s`），prompt 如下（以實際資料填入；務必在結尾要求「只輸出 spec 本文，不要任何開場白或人設評論」）：
     ```
     你是一位資深 Flutter 工程師，請根據以下問題描述與程式碼觀察，用繁體中文撰寫一份實作規格文件（保留英文技術術語）。

     Ticket: <ticket-id> - <ticket summary>

     Issue 文件內容：
     <docs/issues/<ticket-id>.md 完整內容>

     程式碼觀察（已檢視的相關模組、邏輯邊界、測試缺口）：
     <Claude 的 rg / file read 觀察摘要>

     請嚴格按照以下 markdown 結構輸出，每個段落用簡潔的條列式說明：

     # <TICKET-ID> Spec

     ## 背景

     ## 目標

     ## 非目標

     ## 目前行為

     ## 目標行為

     ## 修正策略

     ## 影響範圍

     ### Affected Files / Modules

     ## Acceptance Criteria

     ## Test Plan

     ### Automated

     ### Manual

     ## Regression Risk

     ## Open Questions

     規則：
     - Acceptance Criteria 必須描述可觀察的行為
     - Test Plan 需具體指出 unit / widget / bloc / integration / manual 類型
     - 若有未知項目會阻塞實作，在 Open Questions 中清楚標記
     - 不要發明 issue 文件中未提及的需求
     只輸出 spec 文件內容，不要其他說明。
     ```
   - 若 `agy` 成功回傳包含 `## 背景` 與 `## Acceptance Criteria` 的 spec 結構，採用其內容。
   - **後處理（必做）**：`agy` 會讀取全域 CLAUDE.md 而附加 Linus 人設框架，且可能在生成時順手建立暫存檔。採用前須剝除人設包裝、只取目標 spec 結構；並確認 `agy` 未在工作區誤建檔案（如有則刪除）。`docs/issues/specs/<ticket-id>.md` 一律由 Claude 自行 Write 寫入，不依賴 `agy` 落檔。
   - 若 `agy` 不在 PATH、呼叫失敗或回傳格式不合法，回退至步驟 5 自行撰寫 spec。
5. （Fallback）自行依照 Spec Template 撰寫並 create or update `docs/issues/specs/<ticket-id>.md`。
6. 讓 acceptance criteria 可測試。
7. 讓 open questions 保持可見；不要把未知項目轉成需求。
8. 在實作前停止。

## 檔案命名

使用：

`docs/issues/specs/<TICKET-ID>-<description-suffix>.md`

其中 `<description-suffix>` 取自當前 branch 名稱的最後一段路徑，並移除開頭的 ticket id 部分。

範例：

- Branch：`fix/202605/BUG-2362-some-feature-fix`
- 最後一段：`BUG-2362-some-feature-fix`
- Description suffix：`some-feature-fix`
- 檔案：`docs/issues/specs/BUG-2362-some-feature-fix.md`

以下列指令解析 suffix：
```bash
git rev-parse --abbrev-ref HEAD | sed 's|.*/||' | sed 's/^[A-Z][A-Z]*-[0-9]*-//'
```

保留 ticket id 的大小寫。

## Spec Template

使用此結構：

```markdown
# <TICKET-ID> Spec

## 背景

## 目標

## 非目標

## 目前行為

## 目標行為

## 修正策略

## 影響範圍

### Affected Files / Modules

## Acceptance Criteria

## Test Plan

### Automated

### Manual

## Regression Risk

## Open Questions
```

偏好簡短、具體的條列。

## Spec 規則

- 需求以 issue doc 為依據。
- 用程式碼檢視來提升可行性，而非發明產品意圖。
- 僅在已檢視或有強烈跡象時才提及確切檔案。
- acceptance criteria 必須描述可觀察的行為。
- test plan 應指明可能的 unit、widget、bloc、integration 或 manual 檢查。
- 若某個 open question 阻塞實作，清楚說明。

## 輸出規則

偏好的輸出：

1. `Spec`：建立或更新的路徑
2. `依據`：issue doc 路徑與已檢視的程式碼脈絡
3. `修正方向`：簡短摘要
4. `測試重點`
5. `阻塞`：僅在 open questions 阻塞實作時
6. `Next`：唯有不存在阻塞性問題時，才能開始實作

## 風格規則

- 主要語言：`zh-tw`
- 保留必要的 `en-us` 技術術語，例如 `Acceptance Criteria`、`Test Plan`、`API`、`UI`、`Widget`、`Bloc`
- 精簡且以 spec 為導向
