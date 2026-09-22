# 工具選擇

> 本檔隨專案走。下列工具屬**個人環境**（各自需另行安裝 MCP server），未安裝時對應規則自動失效——用內建的 Read / Grep / Glob / Bash 即可，不影響任何流程。

## 🟢 工具選擇

| 任務 | 用 |
|------|-----|
| 探索程式結構 | codebase-memory-mcp（非 grep） |
| 語意化編輯符號 | Serena |
| 函式庫文件 | Context7（非 WebSearch） |
| 深度多步分析 | sequential-thinking |
| 瀏覽器測試 | Playwright / chrome-devtools |
| Flutter/Dart 操作 | dart-mcp-server（非 shell） |

## 觸發條件（不是工具名，是什麼時候該換工具）

上表只給了對應關係。實務上「該用哪個」的判斷點在這裡：

### 探索 vs 改寫的分界

- **探索**（找符號、追呼叫鏈、讀原始碼）→ codebase-memory-mcp：
  `search_graph` 找符號 / `trace_path` 追呼叫鏈 / `get_code_snippet` 讀原始碼。
  未建索引先跑 `index_repository`。
- **改寫** → Serena，且只在這兩種情況值得：
  - **改動跨多處的符號契約**（函式簽章、欄位、建構式參數）：先
    `find_referencing_symbols` 取得完整引用清單——它回傳**所屬符號路徑**而非行號，
    自動排除註解與文件誤傷，直接當待辦清單用；再 `replace_symbol_body`。
  - **跨檔 rename**：一律 `rename_symbol`（走 LSP，所有呼叫端原子更新），
    不要用 Grep + 逐檔 Edit。
- **單處字串替換仍用 Edit**，別為了用 Serena 而繞路。

> 實測佐證（本 repo，`RingBuffer/onMutate`）：`find_referencing_symbols` 回 10 處
> 語意引用並標出所屬符號；`grep -rn` 回 34 行、含 6 筆註解，另誤傷 `docs/` 七個檔。

### 何時退回 Grep / Glob / Read

codebase-memory 是程式碼優先的工具，下列情況直接用內建工具更快：

- 字串常值、錯誤訊息、config 值
- 非程式碼檔案（Dockerfile、shell script、yaml、markdown）
- graph 查詢結果不足時

### 文件查詢

`mcp__context7__resolve-library-id` → `mcp__context7__query-docs`。
查函式庫 API、設定、版本遷移時用，**別憑記憶回答**。
