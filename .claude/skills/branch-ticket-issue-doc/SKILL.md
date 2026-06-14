---
name: branch-ticket-issue-doc
description: 在 ticket-id-dev-prep 已選定或準備好開發工作區，且 Codex 需從 advisor 解析的 brief、YouTrack ticket 細節與當前工作區程式碼脈絡建立或更新 docs/issues/<ticket-id>.md 時使用此 skill；只聚焦於記錄問題，不撰寫 specs 或程式碼。
---

# Branch Ticket Issue Doc

在 `ticket-id-dev-prep` 選定的開發工作區中使用此 skill。

目標：建立或更新 `docs/issues/<ticket-id>.md`，作為該 branch 的正規問題文件。

不要在此建立 specs。不要在此變更產品程式碼。

## 前置條件

1. 確認當前目錄是預期的開發工作區。
2. 確認當前 branch 含 ticket id，或使用者明確提供 ticket id。
3. 優先使用來自 `branch-ticket-solution-advisor` 的已解析 brief。
4. 若無已解析 brief，閱讀 YouTrack ticket，並僅檢視足以記錄問題的程式碼脈絡。
5. 若 `docs/issues/` 不存在則建立。

若 `ticket-id-dev-prep` 選定了不同的工作區，在寫入前切換過去。若選定策略為 `current-branch` 或 `current-worktree-new-branch`，則允許在當前工作區寫入。

## 工作流程

1. 解析 ticket id。
2. 若存在則讀取既有的 `docs/issues/<ticket-id>.md`。
3. 若存在則讀取 `docs/issues/template.md`，並保留本地文件風格。
4. 蒐集來源素材：
   - advisor 已解析的 brief
   - YouTrack 標題與描述
   - 相關欄位，例如 `State`、`Type`、`Priority`、`Subsystem`
   - 透過針對性檢視得到的當前 worktree 程式碼觀察
5. **agy 優先策略**：收集完所有資料後，優先委派 antigravity-cli（`agy`）生成 issue doc 本文：
   - 透過 Bash 以 stdin 管道委派（`printf '%s' "<填入下方 prompt>" | agy -p --print-timeout 180s`），prompt 如下（以實際資料填入；務必在結尾要求「只輸出文件本文，不要任何開場白或人設評論」）：
     ```
     你是一位資深 Flutter 工程師，請根據以下 ticket 資料與程式碼觀察，用繁體中文撰寫一份問題文件（保留英文技術術語與 issue key）。

     Ticket: <ticket-id> - <ticket summary>
     State: <state>
     Type: <type>
     Priority: <priority>

     Ticket 描述摘要：
     <ticket description 摘要>

     Advisor 解析摘要（如有）：
     <branch-ticket-solution-advisor parsed brief，若無則填「無」>

     程式碼觀察（已檢視的相關模組、邏輯路徑）：
     <Claude 的 rg / file read 觀察摘要>

     請嚴格按照以下 markdown 結構輸出：

     # <TICKET-ID> <title>

     ## Ticket

     - URL:
     - State:
     - Type:
     - Priority:

     ## 問題描述

     ## 影響範圍

     ## 重現步驟

     1.

     ## 預期結果

     ## 實際結果

     ## 環境

     - App 版本：
     - 裝置：
     - OS 版本：
     - 測試帳號：

     ## 程式碼現況

     ## 已知事實

     ## 推論

     ## 待確認

     ## 截圖 / 錄影

     ## 備註

     規則：
     - 不要發明 ticket 中未提及的資訊
     - 無法確認的項目一律填入「待確認」
     - 保留原始錯誤訊息、欄位名稱、使用者可見字串
     - 若程式碼觀察與 ticket 敘述有矛盾，在「備註」中記錄不一致之處
     只輸出文件內容，不要其他說明。
     ```
   - 若 `agy` 成功回傳包含 `## 問題描述` 與 `## 已知事實` 的結構，採用其內容。
   - **後處理（必做）**：`agy` 會讀取全域 CLAUDE.md 而附加 Linus 人設框架，且可能在生成時順手建立暫存檔。採用前須剝除人設包裝、只取目標 markdown 結構；並確認 `agy` 未在工作區誤建檔案（如有則刪除）。`docs/issues/<ticket-id>.md` 一律由 Claude 自行 Write 寫入，不依賴 `agy` 落檔。
   - 若 `agy` 不在 PATH、呼叫失敗或回傳格式不合法，回退至步驟 6 自行撰寫 issue doc。
6. （Fallback）自行依照 Issue Doc Template write or update `docs/issues/<ticket-id>.md`。
7. 區分事實、推論與未解問題。
8. 讓 issue doc 聚焦於問題與當前行為。
9. 除了簡短的程式碼脈絡觀察外，不要加入實作策略。

## 檔案命名

使用：

`docs/issues/<TICKET-ID>-<description-suffix>.md`

其中 `<description-suffix>` 取自當前 branch 名稱的最後一段路徑，並移除開頭的 ticket id 部分。

範例：

- Branch：`fix/202605/BUG-2362-some-feature-fix`
- 最後一段：`BUG-2362-some-feature-fix`
- Description suffix：`some-feature-fix`
- 檔案：`docs/issues/BUG-2362-some-feature-fix.md`

以下列指令解析 suffix：
```bash
git rev-parse --abbrev-ref HEAD | sed 's|.*/||' | sed 's/^[A-Z][A-Z]*-[0-9]*-//'
```

保留 ticket id 的大小寫。

## Issue Doc Template

除非本地 template 要求更貼合的格式，否則使用此結構：

```markdown
# <TICKET-ID> <title>

## Ticket

- URL:
- State:
- Type:
- Priority:

## 問題描述

## 影響範圍

## 重現步驟

1.

## 預期結果

## 實際結果

## 環境

- App 版本：
- 裝置：
- OS 版本：
- 測試帳號：

## 程式碼現況

## 已知事實

## 推論

## 待確認

## 截圖 / 錄影

## 備註
```

僅在章節確實不適用時才省略空白章節。寧可填 `待確認`，也不要發明細節。

## 品質規則

- 問題文件必須不需讀完整 ticket 就能理解。
- 不要逐字複製冗長的 ticket 文字。
- 相關時保留確切的錯誤訊息、標籤、欄位名稱與使用者可見字串。
- 明確註記缺漏的重現資料。
- 若程式碼脈絡與 ticket 矛盾，記錄此不一致。

## 輸出規則

偏好的輸出：

1. `Issue Doc`：建立或更新的路徑
2. `來源`：advisor brief、YouTrack、程式碼檢視
3. `重點`：一段簡短的問題摘要
4. `待確認`：僅在存在時
5. `Next`：執行 `issue-spec-prep`

## 風格規則

- 主要語言：`zh-tw`
- 保留必要的 `en-us` 技術術語，例如 `YouTrack`、`State`、`API`、`UI`、`Backend`、`QA`
- 精簡且以文件為導向
