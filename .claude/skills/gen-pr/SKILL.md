---
name: gen-pr
description: 當使用者想要針對合併至 origin/main 的變更撰寫、改寫、縮短或標準化 Pull Request (PR) 描述草稿時，請使用此技能。在審閱後可選擇發布 PR。此技能會產出精簡的 zh-tw Markdown，並保留必要的 en-us 技術術語。若未明確指定基準分支，預設與 origin/main 進行比較。若分支名稱開頭包含可解析的 GitHub 議題編號，則會在 Summary 中自動加上議題資訊。
---

# PR 描述產生器（zh-TW）

## 輸入解析

從觸發指令中解析 branch name（選填）。

- 輸入格式：`gen pr [branch-name]`
- 範例：`gen pr fix/202604/BUG-1691-product-gift-layout-issue`
- 若未提供 branch name，預設使用當前 HEAD 所在 branch。

將解析到的 branch name 記為 `$BRANCH`。

確認 branch 存在：

```bash
git branch -a | grep "$BRANCH"
```

若不存在，報錯並停止。

---

## 總覽

本技能用於產生以 `origin/main` 為目標的 PR 描述，分兩個階段執行：

- **階段一**：產生或修訂 PR 描述草稿，交由使用者審閱。
- **階段二**：使用者明確確認後，推送 branch（若尚未推送）並以 `gh pr create` 建立 GitHub PR。

當 repository 提供 checklist 項目時，本技能應依據 repository 證據評估第 `1`、`3`、`4`、`5` 項，並直接把結果反映在 PR markdown 的 checklist 行內。第 `2` 項一律保留給使用者在本機自行驗證。

若 repository 含有 PR 模板（例如 `.github/PULL_REQUEST_TEMPLATE.md`），在最終 PR 內文的最前面保留模板的必要內容，移除佔位提示行（例如 `Please explain the changes you made **HERE**.`），並把產生的摘要內容放在模板標題段落之後，而不是取代模板。

輸出可直接複製的 markdown，依序恰好兩個段落，包在 `md` 圍籬程式碼區塊內：

```md
### Summary
[{ISSUE-ID}](issue-url) Issue title

**[修正問題]**

<描述這個 PR 解決了什麼問題，原本的行為是什麼，為何需要修正>

**[修正方式]**

<條列說明修正的具體方式，包含修改了哪些檔案/類別/方法、邏輯判斷的前後變化、關鍵的判斷順序或流程>
```

只有在能從 branch name 解析出對應 issue 時，才加入 issue 行。

## 工作流程

1. 除非使用者另有指示，一律視為合併進 `origin/main`。
2. 所有 git 操作以 `$BRANCH`（來自輸入或當前 HEAD）為來源 branch。commit 範圍預設 `origin/main..$BRANCH`，diff 摘要預設 `origin/main...$BRANCH`。
3. 讀取 repository 的 PR 模板（若存在），例如 `.github/PULL_REQUEST_TEMPLATE.md`。
4. 保留模板最上方的標題、checklist 項目與必要說明文字，但移除純佔位、本來就該被實際內容取代的提示行。
5. 將產生的 PR 描述放在模板的描述標題段落之後，除非使用者明確要求其他排版。
6. 以 `$BRANCH` 作為 issue 擷取與摘要脈絡的依據。
7. 檢視 branch 路徑前段，嘗試從早期的路徑或 slug 片段中取出可解析的 GitHub issue key。
8. 不要求固定的 branch 前綴，也不限制 issue key 的形狀——只要 GitHub 實際解析得出即可。
9. `APP-1234`、`Bug-4321` 這類 issue key 僅為範例，不是限制。
10. 撰寫前先解析 issue metadata：
    - 有 branch name 時，一律先從中解析 issue id。
    - 若使用者本次提供的 brief 已含可信的 issue 摘要／標題，直接採用，不要為了重抓同一份摘要再查一次。
    - 否則優先使用 GitHub MCP 工具取得 `idReadable`、`summary` 與 URL metadata。
    - MCP 不可用或查詢失敗時，改用隨附的 branch issue 腳本（若存在），例如 `bash ./.codex/skills/branch-issue-solution-advisor/scripts/read_branch_issue.sh`。
    - 使用該腳本時，允許它從當前 shell 或 `~/.codex/config.toml` 的 `[mcp_servers.github.env]` 讀取 `AUTH_HEADER`。
    - 腳本查詢也失敗時，退回使用者已在當前脈絡中提供的任何 issue brief。
    - 仍然失敗時，保留 issue id 並依該 id 組出標準 GitHub issue URL，不要因此卡住草稿。
    - 唯有在無法取得可信的 issue id 時，才完全省略 issue 行。
11. 當 repository 模板含 checklist 時，檢視當前 diff、變更檔案與相關脈絡，評估第 `1`、`3`、`4`、`5` 項。
12. checklist 評估一律只依證據：
    - `1`：變更看起來是否遵循 repository 慣例，且未明顯違反既有模式。
    - `3`：當變更屬 bug fix 或 feature 時，是否補上測試。
    - `4`：diff 中若存在難以理解的區塊，是否加上註解。
    - `5`：變更若需要更新文件，是否已更新。
13. 直接更新模板的 checklist 行：
    - 有正面證據的項目用 `[x]`
    - 未滿足或須由使用者驗證的項目用 `[ ]`
    - 不要使用 `[v]` 或 `[?]`
14. 第 `2` 項明確排除在自動評估之外，保持 `[ ]` 交由使用者在本機驗證。
15. 證據不明確時，將該項留為 `[ ]`，不要猜測。
16. checklist 之後，以兩個固定段落撰寫描述本文：`**[修正問題]**` 與 `**[修正方式]**`。
17. `**[修正問題]**`：描述原本（壞掉的）行為以及為何需要修正，聚焦在實際行為與預期行為之間的落差。
18. `**[修正方式]**`：條列具體修正——改了哪些檔案／類別／方法、邏輯如何變化、以及重要的順序或流程調整。類別名稱與欄位名稱要取自 diff，寫具體。
19. 解析出 issue 時，把 `### Summary` 的 issue 行放在描述段落最上方，`**[修正問題]**` 緊接其後。
20. 結果以 `zh-tw` 撰寫，保留必要的 `en-us` 技術術語，例如 API 名稱、branch 名稱、套件名稱、程式碼識別字與原始 GitHub issue id。
21. 輸出保持精簡完整，不需額外編輯就能直接貼進 PR 內文。
22. 呈現草稿後，詢問使用者：**「草稿確認後，是否直接建立 PR？」**
23. 使用者確認後（例如「yes」「對」「建立」「發送」），進入階段二：
    - 檢查 `$BRANCH` 是否已推送到遠端：`git ls-remote --heads origin $BRANCH`
    - 尚未推送則先推送：`git push -u origin $BRANCH`
    - 從 issue 行或 `**[修正問題]**` 的第一句取出 PR 標題，並確保是英文（必要時翻譯）。
    - 執行 `gh pr create`，帶入 `--base main --head $BRANCH --title <title> --body <full PR body>`。
    - PR 內文以 HEREDOC 傳入以保留格式。
    - 回報建立好的 PR URL 給使用者。

## 輸出規則

- 階段一一律只輸出 markdown。
- PR 內文草稿一律放在標註 `md` 的圍籬程式碼區塊內，方便使用者直接複製。
- 使用者審閱草稿並明確確認前，不得建立或發布 GitHub PR。
- repository 有 PR 模板時，最終輸出中模板置於產生的 `### Summary` 段落之前。
- 組出最終輸出前，先移除模板中的純佔位行，例如 `Please explain the changes you made **HERE**.`。
- 模板含 checklist 項目時，直接在 markdown 內文中回傳已更新的 checklist，不要另闢散文段落說明評估結果。
- 描述段落的標題一律使用 `### Summary`。
- 若從 branch name 或使用者 brief 解析出 GitHub issue id，於最上方加一行獨立的：`[{ISSUE-ID}](issue-url) Issue title`
- 只知道 issue id 而查詢失敗時，仍保留 issue 行與標準 issue URL，標題則取使用者脈絡中最合適的可用文字。
- issue 行之後（若無 issue 則直接接在 `### Summary` 下方）寫 `**[修正問題]**`，並以一段文字描述原本壞掉的行為與修正理由。
- 接著寫 `**[修正方式]**`，以編號或項目符號列出具體變更——類別名稱、欄位名稱、邏輯流程變化與重要順序。
- 除非使用者明確要求，避免逐檔列舉。
- 避免杜撰 diff、commit 或草稿無法支持的細節。
- branch 看似含 issue key 但查詢失敗時，不要卡住草稿：
    - 有使用者提供的 issue 摘要就沿用
    - 否則保留 issue id 與標準 issue URL，僅省略無法解析的標題文字
    - 唯有連 issue id 都不可信時，才整行移除
- 除非使用者明確要求改寫模板本身，不要刪除或壓縮 repository PR 模板中的必要 checklist 項目。
- 模板 checklist 行中，唯有正面證據時才用 `[x]`，其餘一律 `[ ]`。
- 除非使用者明確要求在 PR markdown 之外補充說明，絕不額外輸出 `Checklist 確認` 段落。
- 除非使用者明確要求 checklist 評註，不要在 markdown 內文之外另加第 `2` 項的說明。

## 風格規則

- 主要語言：`zh-tw`
- PR 標題：必須為 `en-us`（英文）
- 允許例外：必要的 `en-us` 專有名詞與技術術語
- 偏好語氣：精簡、中性、易讀、可直接貼上
- `**[修正問題]**` 應以白話描述原本壞掉的行為與預期行為，避免「有問題」這類含糊說法。
- `**[修正方式]**` 要具體：使用類別名稱、欄位名稱，精確描述邏輯變化，必要時納入關鍵順序或流程。
- 有 issue 行時，維持其為問題／修正段落之前的獨立一行。
- 使用者要求更短的版本時，壓縮用字但保留 `**[修正問題]**` / `**[修正方式]**` 結構。
- 使用者已提供草稿時，優先重新排版與壓縮，而非整份重寫。

## 範例

```md
## 👾 Checklist before requesting a review

- [x] My code, git commit, table naming ...etc, follow the guidelines
- [ ] Lint and tests pass locally with my changes
- [ ] Tests for the changes have been added (for bug fixes / features)
- [x] I have commented on my code, particularly in hard-to-understand areas
- [x] Docs have been added/updated (if necessary)

## 👻 Describe your changes

### Summary
[#1234](https://github.com/your-org/your-repo/issues/1234) 禮品商品版面異常

**[修正問題]**

禮品列表中，商品項目之間缺少間距，且當禮品圖片 URL 為 null 或空字串時，未做任何處理，導致版面排列錯誤。

**[修正方式]**

1. 在 `GiftItemWidget` 各項目之間新增 `SizedBox` 間距。
2. 在 `GiftItemWidget` 圖片載入前增加對 null 與空字串的判斷，改以 `placeholder_image.svg` 顯示。
3. 更新 `placeholder_image.svg` 為新版設計，簡化 SVG 結構。
```

## 預設值

- 基準 branch 預設為 `origin/main`。
- 來源 branch（`$BRANCH`）在輸入未提供時預設為當前 HEAD。
- 除非使用者明確給出衝突的 branch，不要再詢問確認基準 branch。
- 資訊不完整時，只摘要現有脈絡能支持的部分。
- branch 的 issue 偵測依據是「前段片段看起來是否為可信的 GitHub issue key」，而非固定前綴清單或固定範例格式。
- 當 issue id 已可由 branch 或使用者脈絡判定為可信時，issue 查詢失敗不得阻擋 PR 草稿產生。
- 發布 PR 屬獨立階段，必須在草稿審閱後由使用者明確要求才執行。
