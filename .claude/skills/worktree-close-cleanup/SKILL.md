---
name: worktree-close-cleanup
description: |
  用於安全地關閉、移除、清理 git worktree 的收尾流程。檢查 worktree 狀態，乾淨且無殘留變更時直接移除、
  不需再詢問是否刪除；不觸碰任何 issue 或 ticket 的 State；只移除 worktree，對應 branch 一律保留不刪除。
  觸發條件：關閉 worktree, 移除 worktree, 清理 worktree, worktree 收尾, close worktree, remove worktree
---

# Worktree Close Cleanup（Worktree 關閉清理）

用此 skill 安全地移除一個 git worktree。

## 目標

移除 worktree 且不留下半刪除的 git metadata。此 skill **不**調整任何 issue 或 ticket 的 State——那是其他流程的職責，不在此範圍內。此 skill **只移除 worktree，不刪除對應的 branch**，branch 一律保留由使用者自行決定何時刪除。

## 執行流程

1. 從使用者請求或 `git worktree list` 判斷目標 worktree 路徑。
2. 檢查目標 worktree 的狀態。
3. 若有 dirty、staged 或 untracked 的變更，停下詢問使用者要保留、commit、stash 還是捨棄。
4. 若狀態乾淨，不需詢問是否刪除。
5. 盡可能從目標分支或 context 輸出解析出對應的 issue/ticket，僅供回報使用。
6. 用 `git worktree remove` 移除該 worktree——**只移除 worktree，不執行 `git branch -d`/`-D`**，對應分支保持原樣。
7. 用 `git worktree list` 驗證移除結果，並用 `git branch --list <branch-name>` 確認對應分支仍存在。

## 安全防護

- 目標 worktree 仍存在且尚未檢查前，不要一開始就用 `--force`。
- `git worktree remove --force` 僅用於處理半移除狀態的 worktree。
- 除非使用者在 Git 清理失敗後明確要求手動清理，否則不使用 `rm -rf`。
- 不刪除無關的 worktree。
- **不修改任何 issue 或 ticket 的 State**，即使能解析出對應的 issue/ticket 也一樣；不呼叫任何 issue 狀態異動流程。
- **絕不刪除 worktree 對應的 branch**，不管本地或遠端。即使使用者要求「順便清一清」，也只清 worktree 本身；若使用者明確要求連 branch 一起刪除，先向使用者覆述確認要刪除的 branch 名稱，取得明確同意後才執行，且僅在此 skill 之外另行處理，不併入本流程的自動步驟。

## 回報內容

回報以下資訊：

- 目標 worktree 路徑。
- 乾淨／dirty 狀態。
- 解析出的 issue id（若有，僅供參考）。
- 移除方式。
- 最終 `git worktree list` 的驗證結果。
- 對應 branch 名稱，並確認該 branch 仍保留（未被刪除）。

主要語言：`zh-tw`。
