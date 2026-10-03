# 多 Agent 編排框架模型與推理 Effort 調度機制分析暨 Thinking 停用 400 錯誤風險評估總整報告



> **專案**：`flutter_inspector`  
> **基準文件**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` (全文 2839 行)  
> **任務規範**：滿足 `ORIGINAL_REQUEST.md` 之 R1、R2、R3、R4 全部需求與驗收條件 (AC)  
> **語言規範**：繁體中文（技術術語與程式碼識別字保留原文）

---

## 執行摘要 (Executive Summary)

本專案歷經三位調查員（Survey Explorers）獨立調研、一位執行員（Worker）綜合整理，以及由兩位獨立審查員（Reviewers）、兩位對抗式挑戰員（Challengers）與一位法證鑑識審計員（Forensic Auditor）組成的驗證團隊深度檢驗，完成了對 `docs/brainstorm/2026-09-17-workflow-brainstorm.md` 全文的比對標的排查與上游實證。

### 五大核心收斂結論

1. **R1 地毯式盤點（無遺漏 48 項實體）**：全文 2839 行中實質比對標的共計 **48 項**（原初稿 42 項經對抗挑刺補正，獨立拆出 Inngest、Restate、DBOS、OpenHands、@miyago9267/pilotfish-codex 與 Ralph wiggumdev 版）。涵蓋學術多 Agent 框架、知名開發者實務工作流、評測論文、官方規範、對抗審查工具、耐久執行引擎與專用 Skill 體系。
2. **R2 上游調度機制與重大差異校正（「文件說 X / 上游實為 Y」）**：
   - **重大誤殺澄清**：文件記載 commit `a6fcd29` 移除 agent frontmatter 的 `effort:` 是因 Claude Code 不支援且會撞 400；**上游實況為 Claude Code 官方明確支援 frontmatter `effort: low|medium|high|xhigh|max`**。先前移除實為對 API 組合約束 400 錯誤的誤診與誤殺（Misattribution）。更關鍵的是，Claude Code 的子 Agent 派發 Tool 在 CLI 執行期**根本不支援動態傳遞 `effort` 參數**，因此在 frontmatter 宣告是實現角色差異化推理的唯一正規途徑。
   - **外部框架普遍無動態 Effort 階梯**：CrewAI、AutoGen、MetaGPT、LangGraph 均未在編排層實作隨 Stage 動態升降推理 Effort 的狀態機，多為靜態 Client 配置或底層連線重試。
3. **R3 HTTP 400 根因與世代性組合約束**：
   - **API 官方規範**：Anthropic Messages API 對 **Claude Opus 5 及更晚世代** 施加世代性組合約束（Combination Constraint），當 `output_config.effort` 為 `xhigh` 或 `max` 時，強制要求 `thinking` 必須啟用；若帶入 `thinking: {type: "disabled"}`，API 必然回傳：`400 output_config.effort 'xhigh' is not supported when thinking is disabled on this model`。
   - **世代區分**：Opus 4.8 撞 400 是因其根本不支援 `xhigh` 列舉值；Opus 5+ 撞 400 是因組合約束。兩者皆無法在 thinking 關閉時執行 `xhigh`。
   - **Claude Code Issue 狀態**：Issue #79798（WebSearch 子請求 hardcode disabled 撞 session effort 致 400）已於 **v2.1.221 修復 (Fixed)**；Issue #76689（使用者手動關閉 thinking 或組織策略禁止 extended thinking 時帶 effort xhigh 致 400）**目前仍為 OPEN 狀態**。
4. **本地 `gen-dev-workflow` 400 風險判定**：**「會 (Will Encounter)」**。
   - 派發合約（`SKILL.md:67`、`command-cheatsheet.md`、`delegation-and-parallel.md`）強制帶入 `effort: "xhigh"` / `"max"`。
   - 實查本地 `.claude/hooks/` 全部腳本與 `wf-state.sh`（421 行），確認為 **Zero Sensor Guards（零感測器防護）**。一旦環境停用 thinking，STAGE 0a 第一步必定直接觸發 400 崩潰。
   - 外部對照組在預設配置下判定為「不會」，但若使用者自訂配置同等參數組合，外部框架同樣缺乏防護。
5. **Linus 式架構重構方針**：修復誤殺，將 `effort:` 迎回 `.claude/agents/*.md` 的 frontmatter 宣告式契約；消除派發端各處 hardcode 幽靈參數；將道德勸說（Guide）升級為前置計算式 Sensor（Hook 攔截或安全降級）。

---

## 第一部分：R1 對照組完整地毯式盤點矩陣（48 項）

經審查團隊與對抗挑戰員逐行比對 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`（全文 2839 行），確認所有比對標的無一遺漏：

| # | 對照組名稱 (Target Name) | 類別 (Category) | 出現章節標題 (Section Title) | 精確行號 (Lines) | 編排／模型選擇／Effort／角色分工摘要 |
|:---:|:---|:---|:---|:---:|:---|
| 1 | **MetaGPT** | 開源多 Agent 框架 | 第二部分 §1.1, §1.2 | L496, L503–512, L518–521 | 基於 SOP 範本與強型別 Markdown 驅動；PM→架構師→工程師→QA 線性流水線；Pub/Sub 訊息總線；無動態 effort 分級。 |
| 2 | **AutoGen (Microsoft)** | 開源多 Agent 框架 | 第二部分 §1.1, §1.2 | L497, L503–512, L522–525 | 彈性對話網絡與 GroupChatManager；支援 `ALWAYS/NEVER/TERMINATE_ONLY` 暫停控制；啟發本專案 `pause_level`。 |
| 3 | **SWE-agent (Princeton)** | Issue 自動修復框架 | 第二部分 §1.1, §1.2 | L498, L503–512, L526–529 | 單一全能 Agent 搭配 ACI 工具；視窗截斷與滾動防注意力流失；軌跡日誌重放；啟發 `wf-truncate.sh`。 |
| 4 | **ChatDev (OpenBMB)** | 軟體公司模擬框架 | 第二部分 §1.1, §1.2 | L499, L503–512, L530–533 | 階段化 Chat Chain；雙角色對抗校驗（Reviewer↔Programmer 多輪修正）；交接時 Context 壓縮；啟發 reviewer↔responder 閉環。 |
| 5 | **teamwork-preview** (Antigravity) | 多智能體編排架構 | 第二部分 §5.1–§5.6 | L966–1270 | 3 Explorer 平行勘查；每任務全新 subagent；對抗式 Challenger；動態 Model 分級（flash/pro/inherit）；結構化 Handoff。 |
| 6 | **Ralph / Ralph Wiggum Loop** | 個人實務工作流 | 第三部分 §2.1 | L1367–1375, L1379–1397 | `while :; do cat PROMPT.md \| claude-code; done`；每輪全新 context；失敗靠 `git reset --hard`；佐證 context 重置價值。 |
| 7 | **ACE-FCA** (Dex Horthy) | 上下文工程工作流 | 第三部分 §2.2 | L1367–1375, L1398–1407 | research→plan→implement；狀態壓縮回 plan 檔；**Context 主動維持在 40–60%（主動巡航）**；審查重心在前段 plan。 |
| 8 | **spec→prompt_plan→todo** (Harper Reed) | 三件式文件工作流 | 第三部分 §2.3 | L1367–1375, L1408–1414 | 對話模型產 spec → 推理模型拆 `prompt_plan.md` → `todo.md` 跨 session 打勾維護狀態；佐證狀態持久化之必要。 |
| 9 | **16-session 分段 + oracle** (Mitchell Hashimoto) | 長流程分段工作流 | 第三部分 §2.4 | L1367–1375, L1415–1424 | 一功能拆 16 session；**Oracle（較慢較貴之唯讀模型）產計畫**，再逐 session 實作；穿插 anti-slop session 清理。 |
| 10 | **Augmented Coding** (Kent Beck) | TDD 嚴格引導工作流 | 第三部分 §2.5 | L1367–1375, L1425–1435 | TDD 紀律寫入 system prompt；只寫剛好通過的 code；獨立抓到 Agent 為了讓測試通過而刪測試，佐證需客觀驗證。 |
| 11 | **Harness Engineering** (Birgitta Böckeler) | 控制架構體系 | 第三部分 §2.6 | L1367–1375, L1436–1449 | `Agent = Model + Harness`；Guides（前饋提示，可被忽略）vs Sensors（回饋檢查，不可繞過）；計算式 sensor 優於推論式。 |
| 12 | **Superpowers** (Jesse Vincent) | Skill 插件體系 | 第三部分 §2.7 | L1367–1375, L1450–1457 | Claude Code skill plugin；強制使用 skill；自動建 worktree 平行隔離；TDD；subagent 逐任務實作與 review。 |
| 13 | **Just Talk To It** (Peter Steinberger) | 極簡反方立場 | 第三部分 §2.8 | L1375, L1458–1465 | 反對繁複規劃、反對 subagent、反對冗長 persona；主張精簡 prompt；本專案以 quick 模式回應其短任務適用性。 |
| 14 | **Self-Preference Bias** (Wataoka et al.) | 論文研究 | 第三部分 §3.5 R1 | L1588–1614 | arXiv:2410.21819；實驗證實 LLM 自審偏誤源於低 perplexity（偏好熟悉文本），與能力位階無關。 |
| 15 | **Cross-Model Adversarial** (Daniel Vaughan) | 跨模型審查架構 | 第三部分 §3.5 R1 | L1590–1614 | 主張跨訓練分佈審查（Claude 審 Codex）；同模型會再次合理化實作時之捷徑；Critic 須在 fresh session 執行。 |
| 16 | **Claude Code Best Practices** (Anthropic) | 官方實踐指引 | 第三部分 §3.5 R2 | L1617–1625 | 驗收 Session 衛生；Critic 須在無實作歷史的 fresh session 執行，只餵 spec+測試+diff，不餵產生變更的推理過程。 |
| 17 | **Claude Code Hooks** (Anthropic) | 官方擴充架構 | 第三部分 §3.5 R3, R4 | L1626–1650 | 官方 hooks 文件；證明 `exit 1` 為 non-blocking，僅 `exit 2` 具阻擋能力；多 hook 平行跑不短路；提供 PreToolUse, Stop 等。 |
| 18 | **Claude Code Worktrees** (Anthropic) | 官方隔離機制 | 第三部分 §3.5 R5 | L1651–1662 | 官方 worktrees 文件；執行期 fail-closed 攔截指令形狀與目錄逃逸；指出 `.git`、plugin 與 permission 為共享。 |
| 19 | **BMAD-METHOD** (BMad Code, LLC) | 敏捷工作流方法論 | 第三部分 §3.6 R8 | L1713–1725 | 具名退回邊（`bmad-correct-course`）；三值裁決 `PASS / CONCERNS / FAIL`；狀態機寫在 Markdown 易遭跳過。 |
| 20 | **Container Use** (Dagger) | 容器級軌跡稽核 | 第三部分 §3.6 R9 | L1726–1743 | 系統級側錄 Agent 真實指令歷史與日誌（客觀事實），而非讀取 Agent 自述報告；啟發本專案 worktree dev log。 |
| 21 | **ASDLC** (Ville Takanen) | 軟體生命週期模式 | 第三部分 §3.6 R10 | L1744–1756 | Phase 2 Context Swap（開新 session 審查，不餵推理過程）；Moderator 結構性職責分離；LLM 對否定句權重過低。 |
| 22 | **Falsifiable claims** (Patrick Hughes) | 驗證斷言協議 | 第三部分 §3.6 R11(a) | L1761–1764 | 定義 5 種 claim type 封閉集合，Agent 只能產出可機械驗證的斷言（如 grep 可查），消滅模糊自然語言報告。 |
| 23 | **Rel(AI)Build** | 轉移守衛論文 | 第三部分 §3.6 R11(b) | L1765–1768, L1782 | 轉移守衛檢查委派收據（delegation receipts）與安全掃描狀態；auto-fix 重試上限 3 次即升級人類的熔斷機制。 |
| 24 | **Decoupled HITL** (Cheng & Cheng) | 授權狀態論文 | 第三部分 §3.6 R11(c) | L1769–1775 | arXiv:2604.23049；在持久化狀態中區分人類親自確認與 autonomous 自動放行（`confirmed_by: human\|auto` 欄位）。 |
| 25 | **Adversarial Review** (alecnielsen) | 對抗審查工具 | 第三部分 §3.6 R12(a) | L1778–1783 | 以 `issues_hash` 集合比對驅動 circuit breaker；對稱批評 + 單邊仲裁（Claude 綜合改碼、Codex 唯讀不寫檔）。 |
| 26 | **Uzi** (devflowinc/uzi) | Worktree 編排工具 | 第三部分 §3.6 R12(b) | L1784–1788 | 多 worktree 平行時動態分配服務埠號（Port）；刻意不學其 `uzi auto` 自動過 trust prompt（違反暫停棘輪）。 |
| 27 | **Spec Kit** | 規格工具集 | 第三部分 §3.6 R13 | L1791 | 佐證流程骨架，但順序多寫在 markdown，執行層缺乏腳本強制。 |
| 28 | **Kiro Specs** | 規格規範體系 | 第三部分 §3.6 R13 | L1791 | 階段化規格定義；佐證文件驅動流程，但缺乏外部硬性 Sensor。 |
| 29 | **Agent OS** | Agent 作業系統概念 | 第三部分 §3.6 R13 | L1791 | 角色與權限管理框架；佐證以結構化狀態管理 Agent 行為。 |
| 30 | **Vibe Kanban** | 看板式任務調度 | 第三部分 §3.6 R13 | L1791 | 看板式任務推進；佐證任務隊列持久化之必要。 |
| 31 | **Claude Squad** | 多 Agent 協作工具 | 第三部分 §3.6 R13 | L1791 | 多角色協同團隊；依賴提示詞分配角色，執行層缺乏約束。 |
| 32 | **Stately Agent (XState)** | 狀態機 Agent 框架 | 第三部分 §3.6 R13 | L1791, L1793 | 唯一在執行層同構（in-process guard）之狀態機框架，模型只能在合法轉移中選擇。 |
| 33 | **Claude Code Spec Workflow** | 流程規範文件 | 第三部分 §3.6 R13 | L1791, L1793 | 依賴使用者不輸入指令達成暫停；為純自然語言協議之反例。 |
| 34 | **Ralph (wiggumdev)** | 迴圈實作衍生版 | 第三部分 §3.6 R13 | L1791 | 社群對 Huntley 原始 bash 迴圈進行 tool-calling 與狀態重構的獨立專案。 |
| 35 | **Vibe Engineering** | 開發實務模式庫 | 第三部分 §3.6 R13 | L1791 | 匯整 vibe coding 與工程紀律之折衷模式；佐證流程外掛保護的重要性。 |
| 36 | **LangGraph** (LangChain) | 圖結構編排框架 | 第四部分之二, §W5 | L2029, L2126 | 狀態圖（StateGraph）定義節點與轉移；外部佐證其 `RetryPolicy.retry_on` 區分連線與業務錯誤。 |
| 37 | **CrewAI** | 角色扮演編排框架 | 第四部分之二 | L2029 | 角色團隊協作；調研 6 框架之一，結論無機制可搬，28 項明確排除。 |
| 38 | **AutoGen-AG2** (AG2) | 對話網絡演進框架 | 第四部分之二 | L2029 | 演進版對話編排；多 Client 介面與模型 Fallback 清單；結論無機制可搬。 |
| 39 | **OpenHands** (All-Hands-AI) | 開源軟體開發 Agent | 第四部分之二, §W5 | L2029, L2127 | 通用沙盒 Agent 平台；外部佐證其將格式錯誤與成本上限分流之重試策略。 |
| 40 | **Claude-Flow 系 Worktree Orchestrator** | 工作區編排工具族 | 第四部分之二 | L2030 | worktree 多進程編排工具；調研確認本專案既有設計足夠。 |
| 41 | **Temporal** | 分散式耐久執行引擎 | 第四部分之二, §W5 | L2030, L2125 | 外部佐證其 `NonRetryableErrorTypes`，強調機械錯誤與任務失敗分流。 |
| 42 | **DBOS** | 輕量資料庫耐久引擎 | 第四部分之二 | L2030 | MIT/Stanford 研發之資料庫驅動耐久執行，與 Temporal 架構哲學互為對照。 |
| 43 | **Inngest** | 事件驅動耐久引擎 | 第四部分之二 §W5 | L2126 | 外部佐證其 `NonRetriableError` 與 `RetryAfterError` 錯誤語意分類。 |
| 44 | **Restate** | 輕量分散式狀態引擎 | 第四部分之二 §W5 | L2128 | 外部佐證其 `terminal error` 機制（參數錯誤不可重試）。 |
| 45 | **addyosmani/agent-skills** | 通用 Web Skill 體系 | 第五部分 §1–§8 | L2149–2574 | 25 skills / 9 commands / 跨 10 平台；`/build auto` 一鍵自動；`interview-me` 自適應；無 Hook/Worktree 強制。 |
| 46 | **mattpocock/skills** | 需求對齊 Skill 體系 | 第六部分 §1–§6 | L2575–2749 | 25 promoted skills；聚焦需求對齊（`grilling`）；雙預算模型；零狀態持久化；無 Model 分級。 |
| 47 | **Nanako0129/pilotfish** | 微觀派發策略體系 | 第七部分 §1–§6 | L2750–2838 | 8 角色極精細 Model 分級（Haiku scout 到 Opus verifier）；`plan-verifier` (Opus) 初審；`Dispatch Brake`；三值契約。 |
| 48 | **@miyago9267/pilotfish-codex** | 派發策略先驅實作 | 第七部分 §1 | L2769 | pilotfish 的直接上游調度策略先驅，具備獨立歷史版本與理念。 |

---

## 第二部分：R2 Model 與 Effort 調度機制分析暨上游證據檢驗

### 1. 各對照組機制矩陣與可點擊上游證據

| 對照組 | 調節 Model? (層級 / 條件 / 粒度) | 調節 Effort / Budget? (層級 / 條件 / 粒度) | 可點擊上游證據 (Repo 代碼或官方文檔) |
|:---|:---|:---|:---|
| **MetaGPT** | **Yes**（配置檔或宣告式；依 Role/Action 分工；Per-Role / Per-Action） | **No**（無動態 effort 概念） | [geekan/MetaGPT: role.py:53](https://github.com/geekan/MetaGPT/blob/main/metagpt/roles/role.py#L53), [config2.yaml](https://github.com/geekan/MetaGPT/blob/main/config/config2.yaml) |
| **AutoGen / AG2** | **Yes**（`llm_config["config_list"]`；錯誤 fallback；Per-Agent） | **No**（靜態 Client 參數，無動態調整） | [ag2ai/ag2: conversable_agent.py](https://github.com/ag2ai/ag2/blob/main/autogen/agentchat/conversable_agent.py), [client.py](https://github.com/ag2ai/ag2/blob/main/autogen/oai/client.py) |
| **SWE-agent** | **No**（啟動參數全域鎖定單一模型） | **No** | [princeton-nlp/SWE-agent: models.py:45](https://github.com/princeton-nlp/SWE-agent/blob/main/sweagent/agent/models.py#L45) |
| **ChatDev** | **Yes (靜態)**（`ChatChainConfig.json` 各 Phase 角色靜態配置） | **No** | [OpenBMB/ChatDev: chat_env.py](https://github.com/OpenBMB/ChatDev/blob/main/chatdev/chat_env.py) |
| **teamwork-preview** | **Yes**（派發參數；Explorer 用 `flash`、Worker 依複雜度選 `flash/inherit/pro`） | **No**（僅動態選 Model 家族，不調整數值化 effort） | 本專案 `docs/architecture/2026-07-31-antigravity-teamwork-architecture.md:46-57` |
| **Ralph (Huntley)** | **No**（單一模型 CLI 迴圈） | **No** | [ghuntley.com/ralph](https://ghuntley.com/ralph/) |
| **ACE-FCA** | **No**（方法論以 Context 40-60% 巡航為主） | **No** | [humanlayer/advanced-context-engineering](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents) |
| **Harper Reed** | **Yes (手動)**（對話模型產 spec，推理模型拆 plan） | **No** | [harper.blog/2025/02/16/my-llm-codegen-workflow-atm](https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/) |
| **Hashimoto** | **Yes (手動)**（Oracle 產 spec，常規模型實作） | **No** | [mitchellh.com/writing/non-trivial-vibing](https://mitchellh.com/writing/non-trivial-vibing) |
| **Kent Beck** | **No**（TDD 提示詞紀律） | **No** | [Kent Beck Substack](https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes) |
| **Böckeler** | **No**（架構理論 Guides vs Sensors） | **No** | [martinfowler.com/articles/harness-engineering.html](https://martinfowler.com/articles/harness-engineering.html) |
| **Superpowers** | **Yes (SDD 流程)**（1-2檔 haiku，跨檔 sonnet，架構/判斷 opus；重試失敗強制升級 Model） | **No**（僅調動模型階層，未調控 API effort 參數） | [obra/superpowers](https://github.com/obra/superpowers), 本地 `.agents/skills/subagent-driven-development/SKILL.md:201-220` |
| **Steinberger** | **No**（極簡反方，單一視窗對話） | **No** | [steipete.me/posts/just-talk-to-it](https://steipete.me/posts/just-talk-to-it) |
| **Wataoka et al.** | —（論文研究 LLM 偏好熟悉度） | — | [arXiv:2410.21819](https://arxiv.org/abs/2410.21819) |
| **Daniel Vaughan** | **Yes (原則)**（Claude 審 Codex 跨模型對抗） | **No** | [codex.danielvaughan.com](https://codex.danielvaughan.com/2026/03/28/cross-model-adversarial-review/) |
| **Claude Code** | **Yes**（Subagent frontmatter 指定 `model:`） | **Yes**（Subagent frontmatter 指定 `effort:`；覆蓋 Session 預設） | [Claude Code Subagents](https://code.claude.com/docs/en/subagents), [Anthropic Effort Docs](https://platform.claude.com/docs/en/build-with-claude/effort) |
| **BMAD-METHOD** | **No**（Markdown 流程圖） | **No** | [docs.bmad-method.org](https://docs.bmad-method.org/reference/workflow-map/) |
| **Container Use** | **No**（容器指令側錄） | **No** | [dagger/container-use](https://github.com/dagger/container-use) |
| **ASDLC** | **No**（Phase 2 Context Swap 開新 session） | **No** | [asdlc.io/patterns/adversarial-code-review](https://asdlc.io/patterns/adversarial-code-review/) |
| **LangGraph** | **Yes**（Node 繫結不同 ChatModel；Per-Node） | **Yes (靜態)**（Node 呼叫 `model.bind(reasoning_effort=...)`） | [langchain-ai/langgraph](https://github.com/langchain-ai/langgraph) |
| **CrewAI** | **Yes**（`Agent(llm=...)`、`manager_llm`） | **Yes (靜態)**（`LLM(reasoning_effort=...)` 靜態傳遞） | [crewAI: llm.py](https://github.com/crewAIInc/crewAI/blob/main/src/crewai/llm.py), [agent.py](https://github.com/crewAIInc/crewAI/blob/main/src/crewai/agent.py) |
| **OpenHands** | **Yes**（`DelegateAgent` 配置不同 `LLMConfig`） | **No** | [All-Hands-AI/OpenHands: llm_config.py](https://github.com/All-Hands-AI/OpenHands/blob/main/openhands/core/config/llm_config.py) |
| **Temporal/DBOS** | **Yes**（Activity 級別自行決定調用模型） | **No**（耐久引擎，無 LLM 參數） | [temporal.io/docs](https://temporal.io/docs), [dbos-inc/dbos-transact](https://github.com/dbos-inc/dbos-transact) |
| **Inngest/Restate** | — | — | [inngest.com](https://www.inngest.com/docs), [restate.dev](https://docs.restate.dev) |
| **addyosmani** | **No**（強制 Model-Neutrality） | **No** | [addyosmani/agent-skills: authoring-guide.md](https://github.com/addyosmani/agent-skills/blob/main/docs/authoring-guide.md) |
| **mattpocock** | **No** | **No** | [mattpocock/skills](https://github.com/mattpocock/skills) |
| **pilotfish** | **Yes**（8 角色精細 frontmatter 綁定） | **No**（純靠 Model 置換，無 effort 宣告） | [Nanako0129/pilotfish: plugin/agents/](https://github.com/Nanako0129/pilotfish) |
| **本專案 (gdw)** | **Yes**（frontmatter 綁定別名；二維分層） | **Yes**（派發參數強制帶 `effort: xhigh/max/high`） | 本專案 `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md:14-20` |

---

### 2. 重大不一致性對照表（「文件說 X / 上游實為 Y」）

| # | 項目標的 | 文件記載說法 (X) | 上游客觀實況 (Y) | 偏離根因與衝擊剖析 |
|:---:|:---|:---|:---|:---|
| **1** | **Claude Code Subagent Frontmatter 的 `effort` 支援** | 文件（`delegation-and-parallel.md:10`, §8.2 B5）稱：commit `a6fcd29` 移除 subagent frontmatter 的 `effort:`，因其不被支援且會觸發 400，改為繼承主對話 session effort。 | **Claude Code 官方文件明確支援 `effort:` frontmatter 鍵值**（可設定 `low`, `medium`, `high`, `xhigh`, `max`）。更關鍵的是：**Claude Code CLI 的 `Agent` tool schema 根本沒有 `effort` 參數**！ | **重大誤殺 (Misattribution)**：400 錯誤根因是 API 組合約束（Opus 5+ 關閉 thinking 卻送 `xhigh`），並非 frontmatter 不支援。移除 frontmatter 的 `effort` 導致宣告式契約破裂；而呼叫端傳入的 `effort` 實為無效的幽靈參數，導致整張推論等級表形同虛設。 |
| **2** | **CrewAI 之動態 Effort 調度** | §第四部分之二列為 6 大 Orchestration 框架之一，暗示其具備隨階段調整之動態推理能力。 | CrewAI 僅支援在初始化時透過 LiteLLM 傳入靜態參數，**完全無狀態機驅動的動態 Effort 升降機制**。 | 框架定位誤判：CrewAI 是以 Prompt Role-play 為主的靜態拓撲，不具備本專案依階段調整 effort 的能力。 |
| **3** | **AutoGen / AG2 之動態 Model Fallback** | §第二部分, §第四部分之二 強調 AutoGen 對話網絡可隨機應變切換模型與暫停粒度。 | AutoGen 的 Model Fallback 是在底層 `config_list` 遇 API 錯誤（如 429）時被動輪詢下一個 key/model，**並非由 Orchestrator 根據任務語意動態決策**。 | 將「網路連線層的重試輪詢」誤當作「編排層的語意分級」。 |
| **4** | **ASDLC 作者歸屬與性質** | §3.6 R10 初稿記載作者為 Claudio Lassala，且視為經過驗證之對抗審查論文。 | 上游實為 **Ville Takanen**（`asdlc.io`），且性質為**軟體架構模式庫 (Pattern documentation)**，並非實證學術論文。 | 引用來源偏差，已在 brainstorm §3.6 及時校正為 PLAUSIBLE。 |
| **5** | **confirmed_by 研究之機構歸屬** | §3.6 R11(c) 初稿記載為 Stanford 團隊研究（`Cheng et al.`）。 | 上游論文實為 **Edward Cheng 與 Jeshua Cheng 兩人**（InquiryOn），無 Stanford 隸屬。 | 搜尋摘要幻覺，已在 brainstorm §3.6 標註修正。 |

---

## 第三部分：R3 Thinking Disabled → HTTP 400 風險深度評估

### 1. HTTP 400 根因之跨平台官方規範
1. **Anthropic Claude Messages API**（[Thinking Troubleshooting](https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting)）：
   - 參數位置：`output_config.effort`（有效值：`low`, `medium`, `high`, `xhigh`, `max`）。
   - **世代性組合約束**：在 **Claude Opus 5 及更晚世代**，當 `output_config.effort` 設為 `xhigh` 或 `max` 時，**必須啟用 thinking**。
   - 若同時傳送 `thinking: {type: "disabled"}`，API 必然回傳：  
     `HTTP 400: output_config.effort 'xhigh' is not supported when thinking is disabled on this model`。
   - **Opus 4.8 vs Opus 5+ 差異實查**：Opus 4.8 撞 400 是因其根本不支援 `xhigh` 這個枚舉值；Opus 5+ 撞 400 則是支援 `xhigh` 但嚴格禁止 thinking disabled。兩者皆無法在關閉思考時執行 `xhigh`。
2. **OpenAI API**（[OpenAI API Reference](https://platform.openai.com/docs/api-reference)）：
   - `reasoning_effort` 僅支援推理專用模型（`o1`, `o3`）。若傳給 `gpt-4o`，API 回傳：`400: Unsupported parameter: 'reasoning_effort' is not supported with this model`。
3. **Google Gemini API**（[Gemini API Reference](https://ai.google.dev)）：
   - 透過 `generationConfig.thinkingConfig` 控制。世代間混用參數結構（Gemini 2.5 `thinkingBudget` vs Gemini 3 `thinkingLevel`）將回傳 `400 INVALID_ARGUMENT`。

### 2. 上游 Claude Code 追蹤 Issue 狀態
- **Issue #79798**（[anthropics/claude-code/issues/79798](https://github.com/anthropics/claude-code/issues/79798)）：**CLOSED / FIXED in v2.1.221**。修復了 WebSearch 內部請求因 hardcoded thinking disabled 碰撞外層 session effort 致 400 的 Bug。
- **Issue #76689**（[anthropics/claude-code/issues/76689](https://github.com/anthropics/claude-code/issues/76689)）：**OPEN**。使用者手動關閉 thinking 或組織策略停用 extended thinking 時，派發帶有 `effort: xhigh` 的子請求依然 100% 觸發 400。

### 3. 本專案 `gen-dev-workflow` 8 處本地程式碼行號實查

經實查本地代碼，確認以下引用 100% 精確存在：
1. `.claude/skills/gen-dev-workflow/SKILL.md:67`：STAGE 0b 流程圖硬編碼：`→ 呼叫 plan-verifier agent（獨立 Opus，effort: "xhigh"）`。
2. `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md:10`：記錄 `a6fcd29` 移除 agent frontmatter `effort:`，改為預設繼承 session effort。
3. `delegation-and-parallel.md:14–20`：「推論等級表」，唯一定義最強推論 (`model: opus`, `effort: xhigh`)、標準 (`model: sonnet`, `effort: max`)、輕量 (`model: sonnet`, `effort: high`)。
4. `delegation-and-parallel.md:27–39`：詳細分析 400 失敗模式、Opus 5+ 組合約束與反應 SOP。
5. `delegation-and-parallel.md:67, 71`：STAGE 2 驗收強制使用 `Task("verifier", ..., effort: "xhigh")` 或 Workflow `effort: 'xhigh'`。
6. `delegation-and-parallel.md:134–138, 154`：Retry ladder 將 400 分類為基礎設施錯誤，不計入模型能力重試。
7. `references/command-cheatsheet.md:7, 11, 14, 16, 28, 30, 48, 49, 72`：所有派發範例全數強制帶入 `effort: "xhigh"` 與 `effort: "max"`。
8. `references/execution-modes.md:25`：Quick 模式審查強制帶入 `Task("reviewer", ..., effort: "xhigh")`。

#### 本地守衛檢驗（Zero Sensor Guards）
清查 `.claude/hooks/`（`wf-guard-stage-check.sh`、`wf-guard-delegate-cwd.sh`）與 `scripts/wf-state.sh`（421 行）：
- **結果**：**對 400 錯誤與 thinking 狀態的 Sensor 守衛數量為 0**。
- **結論**：**會 (Will Encounter)**。在停用 thinking 的環境下執行任何跳入或完整流程必定觸發 400 崩潰。

### 4. 48 個對照組 400 風險結論總表

- **`gen-dev-workflow`（本專案）**：**會 (Will Encounter)**（理由：指令硬編 `xhigh` 且零代碼守衛）。
- **外部對照組（47 項）**：
  - **不會**：46 項（MetaGPT, AutoGen, SWE-agent, ChatDev, teamwork-preview, Ralph, ACE-FCA, Harper Reed, Hashimoto, Beck, Böckeler, Superpowers, Steinberger, Wataoka, Vaughan, Claude Code Best Practices, Hooks, Worktrees, BMAD, Container Use, ASDLC, Patrick Hughes, Rel(AI)Build, Cheng & Cheng, alecnielsen, Uzi, Spec Kit, Kiro, Agent OS, Vibe Kanban, Claude Squad, Stately Agent, Claude Spec Workflow, Ralph wiggumdev, Vibe Engineering, LangGraph, CrewAI, AutoGen-AG2, OpenHands, Temporal, DBOS, Inngest, Restate, addyosmani, mattpocock, pilotfish, @miyago9267/pilotfish-codex）。**理由**：預設編排拓撲未主動注入 Anthropic `xhigh` + disabled 組合。
  - **無法判定**：1 項（Claude-Flow 系 Worktree Orchestrator，視第三方外掛腳本是否硬編碼 `effort: xhigh` 而定）。

---

## 第四部分：R4 Minimal-Diff 回寫補丁（Brainstorm 文件更新內容）

針對 `docs/brainstorm/2026-09-17-workflow-brainstorm.md` 的回寫嚴格遵循 Minimal Diff 原則（未更動任何既有決策理由或表格排序）：

### 補記點 1：§W5 小節末（約 L2137 處追加）

```markdown
> 📌 **事實在案補記（2026-10-03 · 詳見 [`docs/orchestration-model-effort-analysis.md`](../orchestration-model-effort-analysis.md)）**：
> 1. **API 400 根因已由官方規範證實**：Anthropic Messages API 對 **Claude Opus 5 及更晚世代** 施加世代性組合約束（Combination Constraint），當 `output_config.effort` 為 `xhigh` 或 `max` 時嚴格要求 thinking 必須啟用；若在該模型上傳送 `thinking: {type: "disabled"}`，API 必然回傳 `400 output_config.effort 'xhigh' is not supported when thinking is disabled on this model`。
> 2. **上游 Claude Code 追蹤狀態**：Issue [#79798](https://github.com/anthropics/claude-code/issues/79798)（WebSearch 內部請求因 hardcoded thinking disabled 碰撞 session effort 致 400）已於 **v2.1.221 修復 (Fixed)**；而 Issue [#76689](https://github.com/anthropics/claude-code/issues/76689)（使用者手動關閉 thinking 或組織策略停用 extended thinking 時帶 effort xhigh 致 400）**目前仍為 OPEN 狀態**。
> 3. **Subagent Frontmatter 支援度澄清**：上游 Claude Code 官方文件明確支援在 subagent frontmatter 中宣告 `effort:`（`low`/`medium`/`high`/`xhigh`/`max`）。此前 commit `a6fcd29` 移除 subagent frontmatter 的 `effort:` 實為對 400 錯誤根因的**誤診與誤殺 (misattribution)**，誤將 API 組合約束當成 frontmatter 語法缺陷；且因 Claude Code CLI `Agent` tool 並無 `effort` 參數，frontmatter 實為目前唯一可行的宣告式分級途徑。
```

### 補記點 2：§8.2 B5 小節末（約 L2503 處追加）

```markdown
> 📌 **事實在案補記（2026-10-03 · 詳見 [`docs/orchestration-model-effort-analysis.md`](../orchestration-model-effort-analysis.md)）**：
> 1. **上游實況查證**：經查證 Claude Code 官方文檔，Subagent YAML Frontmatter 支援 `effort`（可覆蓋主對話 session 值）；當前 CLI 工具派發介面未支援執行期 `effort` 參數傳遞。
> 2. **重構建議**：應修復 `a6fcd29` 的誤殺，重新將 `effort: xhigh` 與 `effort: max` 宣告回 `.claude/agents/*.md` frontmatter；同時於 PreToolUse Hook（`wf-guard-stage-check.sh`）建立計算式 Sensor，當偵測環境停用 thinking 時主動降級，根治 400 風險。
```

---

## 第五部分：Linus Torvalds 式好品味架構建議

1. **消滅特殊情況：回歸宣告式資料結構 (Good Taste)**：
   修復 commit `a6fcd29` 的誤殺，將 `effort: xhigh` 放回 `planner.md`、`reviewer.md`、`verifier.md`、`plan-verifier.md` 的 frontmatter，將 `effort: max` 放回 `implementer.md`。派發端回歸純粹的 `Task("reviewer")`，消滅所有散落的 hardcode 參數。
2. **實用主義防線：從道德勸說 Guide 升級為計算式 Sensor**：
   在 `.claude/hooks/wf-guard-stage-check.sh` 建立前置攔截，若環境處於 thinking disabled，由 Hook 自動清洗參數或安全降級，終結「靠 LLM 自行閱讀 Markdown 避錯」的不可靠設計。
3. **絕不破壞用戶空間 (Never Break Userspace)**：
   確保流程在無 thinking 環境（如受限 API key 或關閉思考偏好）下優雅降級，而非直接拋出未處理的 HTTP 400 崩潰。

---


