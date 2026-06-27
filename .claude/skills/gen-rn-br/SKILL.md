# 分支重命名工具 (gen-rn-br)

自動整理指定類別的 Git 分支。針對未依照 `YYYYMM`（年月）格式進行路徑分組的分支，將根據該分支最後一個提交（commit）的日期，自動移動至對應的年月目錄下。

## 觸發條件
- `gen-rn-br <前綴>`
- `整理 <前綴> 分支`
- `幫我重命名 <前綴> 分支`

## 核心邏輯
1. **參數輸入**：接收一個 `<前綴>`（prefix，例如：`feature`, `fix`, `chore`, `ci`, `refactor`）。
2. **類型規範化**（Normalization）：
   - `feat/`, `Feat/` 統一轉換為 `feature/`
   - `bug-`, `BUG-` 統一轉換為 `fix/`
   - `fix-` 統一轉換為 `fix/`
3. **路徑偵測**：掃描該前綴下的分支，識別名稱中尚未包含 `YYYYMM/` 子目錄結構的分支。
4. **日期獲取**：取得該分支最後一個提交（commit）的月份資訊（格式為 `YYYYMM`）。
5. **執行重命名**：將分支從 `<前綴>/<原始名稱>` 重新命名為 `<前綴>/YYYYMM/<原始名稱>`。
6. **排除受保護分支**：自動跳過 `main`, `rc/`, `prod/`, `test/` 等受保護的分支。

## 指令範例
```bash
# 邏輯範例 (以 Shell 腳本表示)
for branch in $(git branch --list '<前綴>/*' | sed 's/..//'); do
  if [[ ! $branch =~ ^<前綴>/[0-9]{6}/ ]]; then
    date=$(git log -1 --format=%cd --date=format:%Y%m "$branch")
    new_name="<前綴>/$date/${branch#<前綴>/}"
    git branch -m "$branch" "$new_name"
  fi
done
```

## 注意事項
- **本地操作優先**：此技能目前僅針對「本地分支」進行重新命名操作。
- **維護好品味**：若偵測到分支已合併（merged）至 `main`，應優先詢問使用者是否直接刪除，而非盲目移動。
- **避免破壞開發環境**：執行重命名前，若該分支關聯到正在使用的 Worktree 或為當前簽出（checkout）的分支，應給予明確提示。
