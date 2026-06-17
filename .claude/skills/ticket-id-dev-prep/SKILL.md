---
name: issue-id-dev-prep
description: 當使用者提供 GitHub issue id 連同已解析的 issue brief，並希望 Codex 從安全的 base 建立新的 git branch 與 worktree、沿用既有命名規則、且不依賴當前 branch 名稱即完成最小開發設定時，使用此 skill。
---

# Issue Id Dev Prep

當使用者給出明確的 GitHub issue id（例如 `2351`）連同已解析的 issue brief，且想要的是 branch/worktree 準備、而非從頭到尾的 issue 調查時，使用此 skill。

## 目標

把貼上的已解析 issue brief 轉為一個安全、可立即開工的工作區：

1. 從已解析的 issue brief 出發
2. 將 issue 濃縮為一個用於命名的簡短英文 slug
3. 建立新的 worktree
4. 建立新的 branch
5. 完成務實的設定檢查，讓開發能立即開始

## 工作流程

1. 從使用者訊息讀取 issue id。
2. 優先使用使用者在當前對話中貼上的已解析 issue brief。
3. 若同一對話稍早已有可靠的已解析 brief，可重複使用。
4. 若尚無可靠的已解析 brief，先在任何命名或 git 寫入工作之前，執行或請求 `ticket-code-investigator` 的等效調查流程。
5. 所有命名與設定決策都以解析結果為依據，尤其是：
   - 問題或目標
   - 可能的實作區域
   - 此工作屬於 bug fix、feature 還是 maintenance task
   - 任何可能讓命名不可靠的模糊之處
6. 將該解析結果濃縮為一段以 `zh-tw` 撰寫的簡短實作 brief。
7. 產出一個精簡的英文命名片語，可同時用於：
   - branch slug
   - worktree suffix
8. 依解析出的 issue 意圖選擇 branch prefix：
   - `fix/` 用於 bug、regression、error、mismatch 或 validator 問題
   - `feature/` 用於新功能或面向使用者的擴充
   - `chore/` 用於 refactor、maintenance、內部工具，或非面向使用者的清理
9. base branch 預設為 `origin/main`，除非使用者明確要求其他 base。
10. 從該 base 建立 worktree，並同時建立新 branch。
11. 執行確認新工作區就緒所需的最小設定檢查：
   - 確認 branch 與路徑
   - 檢視 repo 狀態
   - 當來源 worktree 存在時，同步真實開發與本地 build 所需的僅限本地設定檔，例如 `.env`、Android 簽章／Firebase 設定，以及 iOS Firebase／fastlane 簽章設定
   - 當來源 worktree 存在 `android/app/google-services.json` 與 `ios/Runner/GoogleService-Info.plist` 時，驗證它們已複製；若任一缺少，在 bootstrap 前明確回報
   - 本地設定同步後，以 `flutter pub get` 執行此 repo 的相依套件 bootstrap
12. 回報結果，附上已解析的 issue brief、選定的 slug、branch 名稱、worktree 路徑與任何後續備註。

## 已解析 Brief 規則

貼上的已解析 issue brief 是以下項目的真實來源：

- 實作 brief
- branch prefix 選擇
- slug 產生
- 應保持可見於 prep 結果中的不確定性

若貼上的 brief 與當前對話脈絡衝突，提出此不一致，並在任何 git 寫入工作前詢問是否要重新調查。

## 已解析輸入規則

把已解析的 issue brief 視為設定決策的真實來源。

始終區分：

- 來自解析結果的事實
- prep 過程中所做的命名推論
- 仍需確認的未解模糊之處

brief 應涵蓋：

- 問題或目標
- 面向使用者的影響
- 解析過程中已識別的明確需求
- 解析過程中已觀察到的技術線索
- 風險或缺漏的細節

不要發明不存在的 acceptance criteria。

若解析結果表示該 issue 可能不存在或仍需驗證，把此不確定性保留在 prep 輸出中，而非藏在一個看似篤定的 slug 背後。

## Slug 規則

英文命名片語應簡短、具體且可重複使用。

要求：

- 以已解析的 issue brief 為依據，而非只看 issue key
- 偏好 2 到 6 個英文單字
- 最終 slug 形式為小寫 kebab-case
- 與實作相關，不要過於籠統
- 避免填充詞，例如 `handle`、`update`、`improve`、`fix-issue`、`issue-work`
- 偏好仍能清楚標示該工作的最短片語

良好範例：

- `password-fields-validator-error`
- `member-card-expired-state`
- `checkout-delivery-note`
- `apple-login-token-refresh`

避免：

- `2351`
- `misc-fix`
- `update-something`
- `temporary-change`

## Branch 與 Worktree 規則

依此順序組出名稱：

1. branch 名稱：`<prefix><ISSUE-ID>-<slug>`
2. worktree 目錄名稱：`<repo-name>-<ISSUE-ID-lowercase>-<slug>`

範例：

- branch：`fix/2351-password-fields-validator-error`
- worktree：`../ai-chat-2351-password-fields-validator-error`

附加規則：

- branch 名稱中保留 issue id 的大小寫
- worktree 目錄 suffix 使用小寫 issue id
- 偏好在當前 repo 旁建立新的 worktree，除非使用者要求其他位置
- 若目標 branch 已存在於本地，停止並回報，而非默默重用
- 若目標 worktree 路徑已存在，停止並回報，而非覆蓋任何東西

## Git 執行規則

優先使用內附腳本以取得可重現的設定：

[`scripts/prepare_issue_dev_workspace.sh`](./scripts/prepare_issue_dev_workspace.sh)

用法：

```bash
./scripts/prepare_issue_dev_workspace.sh \
  --issue-id "2351" \
  --prefix "fix/" \
  --slug "password-fields-validator-error"

./scripts/prepare_issue_dev_workspace.sh \
  --issue-id "412" \
  --prefix "feature/" \
  --slug "member-card-expired-state" \
  --base "origin/main"
```

行為：

- 在任何 git 寫入前驗證必要輸入
- base branch 預設為 `origin/main`
- worktree parent 預設為當前 repo 的上層目錄
- 當 base ref 指向 `origin/*` 時 fetch 該 ref
- 若目標 branch 已存在於本地則停止
- 若目標 worktree 路徑已存在則停止
- 預設把來源 worktree 的常見僅限本地設定檔複製進新 worktree
- 當前 worktree 缺少這些本地設定檔時，回退至已具備這些檔案的同層 git worktrees
- 印出描述已建立或預定建立工作區的正規化 JSON

本地設定同步在檔案存在時納入此 repo 常見的僅限開發檔案，例如：

- 任何 `.env` 或 `.env.*` 檔
- `android/key.properties`
- `android/app/google-services.json`
- Android 簽章檔，例如 `*.keystore` 與 `*.jks`
- `ios/Runner/GoogleService-Info.plist`
- iOS / Android 的 `fastlane` 私密簽章或憑證檔，例如 `*.json`、`*.plist`、`*.p8`、`*.p12` 與 `*.mobileprovision`

若你明確想要一個不複製本地機密的乾淨 worktree，以 `--skip-local-config-sync` 執行腳本。

手動回退流程：

```bash
git fetch origin main --prune
git worktree add -b "<branch-name>" "<worktree-path>" "origin/main"
```

若使用者要求不同的 base branch，相應替換 `origin/main`。

建立 worktree 後：

1. 驗證 `git branch --show-current`
2. 驗證 `git status --short`
3. 執行 `flutter pub get`

當目標是隔離的 issue 開發時，不要在已經 dirty 的當前 worktree 內建立 branch。

## 設定完成規則

此 skill 應以一個可用的開發工作區收尾，而不只是命名建議。

預設完成檢查清單：

1. 新 worktree 存在
2. 新 branch 存在且已在該處 checkout
3. 新 worktree 在新編輯之前的 repo 狀態為乾淨
4. 當來源 worktree 存在所需本地設定檔時，已複製進新 worktree
5. `flutter pub get` 已成功完成
6. 若設定無法自動完成，註記任何必要的後續指令

對此 repo 有幫助時，也執行以下一項或多項：

- 檢視 package 或 workspace 的相依檔
- 確認是否需要 code generation 或其他 bootstrap 步驟

對此 repo，除非使用者明確要求略過，否則優先採用以下具體初始化流程：

1. 把僅限本地的設定同步進新 worktree
2. 在 repo 根目錄執行 `flutter pub get`

偏好能快速解除開發阻礙的最小安全設定。

## 安全規則

- 在此 skill 中絕不從當前 branch 推斷 issue id；必須由使用者提供。
- 若尚無可靠的已解析 brief，在任何 git 寫入操作前停止，先執行或請求調查。
- 若 issue 摘要過於模糊而無法產生可靠 slug，給出你能做到的最佳精簡 slug，並說明這是命名推論。
- 若當前 repo 有無關的 dirty 變更，不要修改它們；仍偏好建立獨立的 worktree。
- 若 `git fetch` 或其他依賴網路的 git 指令因環境限制失敗，清楚回報。
- 不要覆蓋既有目錄或強制建立 branch。

## 輸出規則

讓回應精簡且以執行為導向。

偏好的輸出形態：

1. `Issue`：issue key 與摘要
2. `Issue 摘要`：簡短實作 brief
3. `English Slug`：命名片語
4. `Branch`：最終 branch 名稱
5. `Worktree`：最終 worktree 路徑
6. `Setup`：建立了什麼，或什麼阻擋了建立
7. `待確認`：僅在仍有實質模糊時

## 風格規則

- 主要語言：`zh-tw`
- 允許的例外：必要的 `en-us` 專有名詞與技術術語，例如 `GitHub`、`State`、`branch`、`worktree`、`slug`、`API`、`UI`、`Backend` 與 issue keys
- 偏好語氣：精簡、可靠、可直接執行
