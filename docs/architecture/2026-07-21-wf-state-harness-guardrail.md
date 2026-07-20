# wf-state.sh: Execution Harness 與 Guardrail 機制解析

> **核心信條**：把 LLM 當成一台不受控、隨時可能暴衝的引擎。單靠 Markdown 提示詞去約束 LLM 就像用「道德勸說」在管教程式碼；我們必須在底層實作「硬體級別的防呆機制」。

`wf-state.sh` 是 `gen-dev-workflow` 技能的專屬狀態機 (State Machine) 腳本。它被設計為工作流狀態檔 (State JSON) 的**唯一存取入口**。

在這支腳本裡，**Harness（基礎執行設施）** 與 **Guardrail（邊界防護）** 有著明確的職責劃分：Harness 負責提供標準化的掛載點讓 LLM 驅動流程；而 Guardrail 負責擋下所有愚蠢、出格或破壞性的行為。

---

## 1. Harness 機制（基礎執行設施）

Harness 的目標是**抹平底層系統複雜度**，讓 LLM 不需要親自處理檔案競爭、型別轉換或 JSON 序列化，只要呼叫標準 API 即可。

### 1.1 唯一掛載點的封裝
腳本提供了標準的 `init`, `promote`, `get`, `set`, `advance` 等指令介面。它將繁瑣的 shell 指令隱藏起來，讓 LLM 統一透過這個介面讀寫狀態，而非使用原始的 `cat`、`sed` 或 `echo`，這為自動化執行提供了穩定的軌道。

### 1.2 檔案層級的競爭與原子性 (`claim_new`, `atomic_write`)
*   **排他佔位**：`claim_new` 利用 `set -C; : > file` 實作排他創建，消除「檢查存在到創建檔案」中間的併發窗口 (Race Condition)。
*   **原子寫入**：`atomic_write` 強制資料先寫入暫存檔 (`mktemp`)，確認 JSON 解析成功且內容合法後，才使用 `mv` 覆蓋原檔。確保腳本中途當機時，磁碟絕不會留下寫壞一半的 JSON。

### 1.3 型別與變數轉換的基礎設施 (`jq_val`, `apply_sets`)
幫 LLM 處理 Bash 傳遞參數到 JSON 儲存時的型別地雷。例如自動辨識字串、布林值，並阻擋「帶前導零的假數字」（這會破壞 JSON 格式），讓 LLM 不會因為處理引號和型別而寫出崩潰的 bash 邏輯。

---

## 2. Guardrail 機制（邊界防護與斷路器）

Guardrail 的設計哲學充滿了對 LLM 的「極度不信任」。它的任務是：一旦發現不對勁，立刻 `exit 1` 讓流程當機，**絕對拒絕靜默失敗 (Silent Failure)**。

### 2.1 資料結構守護 (`validate`)
每次讀寫都會強制跑 `jq -e` 檢查 Schema 的完整性與欄位型別（如 `workflow_id` 必須是字串，`completed_tasks` 陣列不可混入非數字元素）。任何異常都會中斷寫入，確保**爛資料連磁碟的邊都摸不到**。

### 2.2 強制暫停棘輪 (Pause Point Ratchet)
這是防範 LLM「無聲遺忘與越權」的最強防護欄。
腳本規定，在觸發 `stage-done` 或 `task-done` 後，狀態檔會被強制鎖上 `awaiting_confirmation=true`。如果 LLM 試圖在未經使用者同意的情況下呼叫 `advance` 推進流程，只要未攜帶 `--confirmed` 旗標，腳本就會無情報錯：
> `有暫停點等待使用者確認中。先在對話中暫停詢問，獲確認後帶 --confirmed 重跑`
這強迫 LLM 在程式碼層級證明「確實有停下來等使用者確認」。

### 2.3 寫死狀態機轉移表 (`legal_transition`)
不容許 LLM 憑感覺跳關。在 `sequence` 模式下，腳本直接查表匹配合法路徑：
`0a→0b→1→2→3→4→done`。
若試圖從 `0a` 直接跳到 `2`，腳本會判定為非法轉移並直接 `exit 1`。

### 2.4 寫入權限白名單 (`apply_sets`)
腳本明確限制了 `set` 指令可以修改的欄位（白名單：`spec|plan|branch|issue|pr|total_tasks|interrupted_by`）。如果 LLM 試圖用 `set` 去走後門竄改 `stage` 或 `awaiting_confirmation`，腳本會拒絕操作，強制其必須走 `advance` 這個具備嚴格審查的正規管道。

### 2.5 任務完整性驗證
在進入下一個階段（如 STAGE 3）前，攔截器會檢查 `completed_tasks` 的長度是否符合 `total_tasks` 的聲明，防止 LLM 在實作未完成時強行推進流程。

---

## 總結

*   **Harness** 告訴 LLM：「你要開車，方向盤和油門在這裡。」
*   **Guardrail** 告訴 LLM：「你敢開出車道、闖紅燈或不繫安全帶，我就直接熄火，把你踹下車。」

用 Markdown 文件規範 LLM 行為，最終只會淪為願望清單。真正的工程實踐，是將這些規範寫入無法被繞過的底層腳本，用 `exit 1` 來保證系統的正確性。
