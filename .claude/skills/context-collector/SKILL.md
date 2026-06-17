---
name: context-collector
description: 當 Codex 需要在 issue docs、specs、workspace prep、實作或工作流程路由之前，從 GitHub issues、使用者 briefs、QA 報告、branch 脈絡或聚焦的 repo 證據進行正規 issue context 蒐集時使用。在不修改 source、tests、specs、PRs 或 GitHub state 的前提下，產生或更新 .agent-output/context/<issue-id-or-slug>.md 作為 facts/inference/open-questions 的主要來源。
---

# Context Collector

把此 skill 作為正規的 issue context 來源。

## 角色

- 角色：issue context 蒐集者。
- 策略：事實只蒐集一次，讓下游 skills 讀取同一來源。

## 可以修改

- `.agent-output/context/*`。

## 不可修改

- Production code。
- Tests。
- `docs/issues/*`。
- `docs/issues/specs/*`。
- PRs。
- GitHub 留言或 State。

## 輸入

接受任何 issue 來源：

- GitHub issue id。
- 使用者提供的 issue brief。
- QA 報告。
- Feature request。
- 當前 branch 脈絡。
- 既有 issue doc 或 spec 的更新請求。

## 工作流程

1. 解析 subject。
2. 視情況從 GitHub issue、使用者 brief、branch 脈絡、QA 證據與聚焦的 repo 檢視中讀取來源事實。
3. 區分事實、推論與未解問題。
4. 只檢視理解可能受影響區域所需的程式碼。
5. 寫入或更新 `.agent-output/context/<subject>.md`。
6. 在同一檔案內保留精簡的 `History` 表格。
7. 回報 context 檔路徑，以及它是否已可供 issue doc、workspace prep 使用，或處於 blocked。

## 路徑規則

每個 subject 使用單一正規檔案：

- 有 issue id：`.agent-output/context/<ISSUE-ID>.md`
- 無 issue id：`.agent-output/context/<slug>.md`

不要在檔名加上 `-context`，因為資料夾本身已定義 artifact 類型。

若更新同一 subject，覆寫同一檔案並更新 `History`。不要建立 `history/` 資料夾。

## 必要章節

使用此結構：

```markdown
# <Subject> Context

## Source

## Summary

## Facts

## Code Observations

## Inference

## Open Questions

## Suggested Slug

## Handoff

## History

| Time | Change | Source | Notes |
| --- | --- | --- | --- |
```

`Handoff` 必須為以下之一：

- `issue-doc-ready`
- `workspace-prep-ready`
- `blocked`

blocked 時附上 blocker 原因。

## History 規則

- 每次 context 更新新增一列表格。
- 摘要變更、來源與注意事項。
- 不要貼上完整舊內容或完整來源文字。

## 輸出規則

- 主要語言：`zh-tw`。
- 保留必要的 `en-us` 技術術語。
- 只回報 context 路徑、就緒度、blockers，與建議的下一個 skill。
