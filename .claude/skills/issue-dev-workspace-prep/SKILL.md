---
name: issue-dev-workspace-prep
description: 在 context-collector 產出 issue context 後、且使用者想準備開發分支或 worktree 時使用。以 .agent-output/context/* 作為 issue id、slug、work type 與 blockers 的來源；建立新的 worktree 時，必須在任何 issue-doc-writer 或 issue-spec-writer 執行前，把目前的 context 輸出複製到新的 worktree。
---

# Issue Dev Workspace Prep

使用此 skill，從 context 輸出準備開發工作區。

## 可以修改

- Git branch / worktree 狀態。
- 目標 worktree 中 `.agent-output/context/*` 底下複製過去的 context 檔案。

## 不可修改

- Production code。
- Tests。
- `docs/issues/*`。
- `docs/issues/specs/*`。
- PRs。
- GitHub 留言或 State。

## 必要輸入

- 一份位於 `.agent-output/context/*` 的最新 `context-collector` 輸出檔。

若缺少，導向 `context-collector`。

## 工作流程

1. 讀取 context 檔。
2. 確認 `Handoff` 為 `workspace-prep-ready`。
3. 解析 issue id（若有）、work type、slug 與 blockers。
4. 檢視目前 branch/status 與既有 worktrees。
5. 選擇 `current-branch`、`current-worktree-new-branch`、`new-worktree` 或 `no-prep`。
6. 執行所選的工作區策略。
7. 若建立 `new-worktree`，把目前的 context 檔複製到目標 worktree。
8. 驗證複製過去的 context 檔存在於目標 worktree。
9. 回報工作區結果與下一個 skill。

## 新 Worktree 腳本

建立新的 worktree 時，優先使用內附腳本：

```bash
scripts/prepare_ticket_dev_workspace.sh --ticket-id "<ISSUE-ID>" --prefix "<fix/|feature/|chore/>" --slug "<slug>"
```

無 ticket 的 issue 則省略 `--ticket-id`：

```bash
scripts/prepare_ticket_dev_workspace.sh --prefix "<fix/|feature/|chore/>" --slug "<slug>"
```

此腳本也會把僅限本地的開發設定同步進目標 worktree，包括：

- 根目錄的 `.env` 與 `.env.*`
- `android/key.properties`
- `android/app/google-services.json`
- Android 簽章檔，例如 `*.keystore` 與 `*.jks`
- `ios/Runner/GoogleService-Info.plist`
- iOS / Android 的 `fastlane` 私密簽章或憑證檔

僅在使用者明確表示不要複製本地設定時，才使用 `--skip-local-config-sync`。

## 強制 Context 交接

若策略為 `new-worktree`：

```text
copy .agent-output/context/<subject>.md from source workspace to target worktree
verify target .agent-output/context/<subject>.md exists
stop if copy or verification fails
```

在執行 `issue-doc-writer` 或 `issue-spec-writer` 之前完成此步。

## 命名

有 issue id 時使用 issue id，否則使用 slug。

Branch 範例：

- `fix/<ISSUE-ID>-<slug>`
- `feature/<ISSUE-ID>-<slug>`
- `chore/<ISSUE-ID>-<slug>`
- 無 issue id 時：`<type>/<slug>`

## 輸出規則

回報：

- 使用的 context 檔。
- 策略。
- branch。
- worktree。
- context 複製結果。
- blockers。
- 下一個 skill：通常是 `issue-doc-writer`。

主要語言：`zh-tw`。
