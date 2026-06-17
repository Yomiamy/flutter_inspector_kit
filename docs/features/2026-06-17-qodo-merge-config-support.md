# 功能規格：Qodo Merge 設定支援

- **日期**：2026-06-17
- **Workflow ID**：wf-1781708822-2be9
- **Stage**：0a（功能規格 — What & Why）
- **狀態**：待使用者確認

---

## 1. 背景與動機（Why）

本 repo 目前以 **Gemini Code Assist** 作為 PR 自動審查工具，設定落在 repo 根目錄的兩個檔：

| 檔案 | 角色 |
|------|------|
| `.gemini/config.yaml` | 審查行為開關（嚴重度門檻、PR 開啟時自動跑哪些動作） |
| `.gemini/styleguide.md` | 團隊風格指南 + 審查人格（The Versatile Poet，含文學收尾規範） |

使用者希望 **Qodo Merge** 也能用「跟著 repo 走」的設定檔達到對等效果——亦即不靠 web dashboard，而是把審查規範版本控管在 repo 內，與既有 `.gemini` 模式並存。

調查確認 repo 既有慣例正是「第三方工具設定放根目錄、用工具名前綴、規範用 Markdown、行為開關用結構化格式」，本功能完全沿用此慣例，無需新模式。

---

## 2. 範圍邊界（Scope）

### ✅ In Scope

1. 在 repo 根目錄提供 Qodo Merge **v1（Qodo Merge / PR-Agent）路線**的設定檔：
   - `.pr_agent.toml` — 對應 `.gemini/config.yaml` 的行為設定
   - `best_practices.md` — 對應 `.gemini/styleguide.md` 的風格指南，供 `/review`、`/improve` 自動載入
2. 設定內容與 `.gemini` 的既有行為**對等**：繁中評論、術語保留英文、MEDIUM 以上嚴重度、PR 開啟自動 `/describe` + `/review`、文學收尾規範。
3. 設定檔欄位需經 Qodo 官方權威來源（開源 `configuration.toml`）**校正為有效 key**。

### ❌ Out of Scope（明確不做）

- **不**改動或移除既有 `.gemini/` 設定——兩套並存，互不影響（Never break userspace）。
- **不**處理 Qodo **v2（web dashboard / Rule System / Centralized Governance）** 的線上設定；本功能只走 repo 內檔案的 v1 路線。
- **不**新增 CI workflow（雲端版 GitHub App 由 Qodo 端自動觸發，repo 內不需 workflow 檔）。
- **不**自行安裝 / 設定 Qodo GitHub App（屬使用者帳號操作）。

---

## 3. 使用者故事（User Stories）

- **US-1**：身為維護者，當我開啟一個 PR，Qodo Merge 能像 Gemini 一樣自動產出 PR 摘要與繁中審查意見，讓我不必手動觸發。
- **US-2**：身為維護者，Qodo 的審查與程式碼建議能依據 `best_practices.md` 的 Flutter/Dart 規範（命名、註解、BLoC、Retrofit、測試），而非通用泛論。
- **US-3**：身為維護者，Qodo 的審查只回報 MEDIUM 以上的實質問題，避免風格瑣事噪音。
- **US-4**：身為維護者，審查結尾保有既有的「文學體裁收尾」個性（絕句/新詩/俏皮話/順口溜），與 Gemini 體驗一致。
- **US-5**：身為維護者，這兩個 Qodo 設定檔不影響既有 `.gemini` 設定，可同時保留兩套工具。

---

## 4. 驗收條件（Acceptance Criteria）

| # | 條件 | 驗證方式 |
|---|------|---------|
| AC-1 | `.pr_agent.toml` 與 `best_practices.md` 存在於 repo 根目錄 | `ls` 確認 |
| AC-2 | `.pr_agent.toml` 所有 TOML key 皆為 Qodo 有效欄位（無已廢棄/不存在的 key） | 對照官方 `configuration.toml` 逐一核對 |
| AC-3 | `.pr_agent.toml` 行為對應 `.gemini/config.yaml`：MEDIUM 門檻、PR 開啟自動 `/describe`+`/review` | 欄位對照表 |
| AC-4 | `best_practices.md` 完整涵蓋 `styleguide.md` 的**技術規範**（命名、註解、結構、錯誤處理、Flutter、BLoC、測試、Retrofit、DTO 決策） | 章節對照 |
| AC-5 | 文學收尾規範（含**範例詩句**）有被保留，AI 有足夠樣本可模仿 | 檢查 `extra_instructions` 或 `best_practices.md` 是否含範例 |
| AC-6 | 既有 `.gemini/config.yaml`、`.gemini/styleguide.md` 內容**零改動** | `git diff` 對 `.gemini/` 應為空 |
| AC-7 | 設定檔明確標註走 v1 路線、v2 風險已書面說明 | 檔內註解 / 文件 |

---

## 5. 已知缺口（待 STAGE 0b 計畫處理）

調查交叉比對發現目前 working tree 的兩檔有以下落差，需在實作計畫中決定處理方式：

1. **G-1（內容缺口）**：`styleguide.md` 的「文學體裁**範例詩句**」（如「變數命名亂如麻…」五言絕句等 4 段範例）**未搬移到任何檔案**。目前 `.pr_agent.toml` 的 `extra_instructions` 只有規範定義、無範例。→ 影響 AC-5，會降低 AI 文學收尾品質。
2. **G-2（涵蓋度）**：`best_practices.md`（136 行）是 `styleguide.md`（550 行）的精簡版，部分子小節的具體範例程式碼被省略。需確認精簡是否丟失了審查所需的關鍵判準（如 Singleton 範例、建構式預設值兩種寫法）。
3. **G-3（路線標註）**：v1/v2 分歧的風險目前只在對話中說過，**未寫進 repo 任何檔案**。需在設定檔或文件補一句書面說明，避免日後誤解。
4. **G-4（文件提及，可選）**：`README.md` 未描述 code review / PR 流程。可選擇性補一行指向設定檔。

---

## 6. 非目標的明確聲明（避免過度設計）

- 不為了「完美對等」而把 styleguide 550 行**全文**塞進 `best_practices.md`——Qodo 官方建議 best practices 精簡。只補回**審查真正會用到**的判準與範例。
- 不引入任何鎖、索引或額外抽象；兩個純文字設定檔即是全部交付物。

---

**下一步**：使用者確認本規格後 → STAGE 0b 產出實作計畫（How：決定 G-1～G-4 各自的處理動作與檔案異動）。
