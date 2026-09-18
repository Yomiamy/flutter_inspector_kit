# C4 · STAGE 0a 前插 grilling 關卡 — 實作計畫

> **規格**：[`docs/features/2026-09-18-grilling-gate.md`](../features/2026-09-18-grilling-gate.md)
> **日期**：2026-09-18 ｜ **方案**：A（獨立 skill + workflow 接線）

---

## 1. 核心判斷（動工前的形狀確認）

**本項是純文件改動，零 Dart 程式碼。** 產出 1 個新 skill + 修 1 份既有 SKILL.md。

**最關鍵的設計決定**：`gen-grill` **不自帶問法**。它只做三件事——判定收斂、驅動 `brainstorming`、產出 brief。問法本體留在 `brainstorming`（上游 skill，不持有、不修改）。

這一點決定了整份計畫的規模：如果自帶問法，就要寫一份完整的訪談手冊（100+ 行，且與 brainstorming 重複）；只做閘門，SKILL.md 控制在 60 行內就夠。

---

## 2. 資料結構：收斂判準是唯一的核心資料

整個 skill 的本質是**一張檢查表 + 一條短路規則**。把這張表定義好，其餘都是它的包裝。

```text
收斂判準（5 項，逐項可指認）
├─ Q1 問題定義 — 要解決的具體問題是什麼？（不是「想要什麼功能」）
├─ Q2 觸發場景 — 誰、在什麼情況下會遇到？
├─ Q3 成功標準 — 做完後怎樣算對？可驗證的形狀
├─ Q4 範圍邊界 — 明確不做什麼？
└─ Q5 既有覆蓋 — 現有功能/文件是否已覆蓋？（本 repo 特有，見 §3）

判定：5 項齊備 → 放行 planner
      任一項缺 → 呼叫 brainstorming 盤問該項 → 重新判定
```

**Q5 是本 repo 專屬的一項，不在上游設計裡。** 加它的理由是實證的——本次 C4 自己就中招：文件宣稱「brainstorming 缺一問一答」，實查證偽（該機制早已存在）。§D4 更慘，照文件做完 610 tests 全綠才發現落點錯了一層。**本 repo 的最大 misalignment 來源不是「需求沒講清楚」，是「文件與實況漂移」**，所以收斂判準必須包含一次實查。

---

## 3. 檔案異動清單

| # | 檔案 | 動作 | 行數估計 |
|:-:|:---|:---|:---|
| 1 | `.claude/skills/gen-grill/SKILL.md` | 新增 | ~60 行 |
| 2 | `.claude/skills/gen-dev-workflow/SKILL.md` | 修改 2 處（流程圖 + 暫停點表前註記） | +8 行 |

**不動的檔案（AC-7/AC-9 要求）**：`scripts/wf-state.sh`、`.claude/skills/brainstorming/SKILL.md`、`.claude/agents/planner.md`。

> **📝 PR review 後修正（2026-09-18）**：原本也列了「所有 `references/*.md`」，但 review 指出三處漏接——`command-cheatsheet.md` 的 STAGE 0a 派發模板繞過閘門、`execution-modes.md` 的 quick 流程與 quick 溢出 commit 未納入新規則、`branch-worktree-rules.md` 的 issue-id 路徑跳過 0a/0b 故不經過閘門。**閘門只寫在主流程圖而不接進實際派發路徑等於沒有閘門**，故三檔皆需修改。`wf-state.sh`、`brainstorming`、`planner.md` 三項保護不變。

---

## 4. 任務拆分

> 兩個任務**寫入路徑不重疊**（不同檔案），技術上可並行。但任務 2 的內文需引用任務 1 的 skill 名稱與行為，**建議序列**執行，成本差異可忽略。

---

### Task 1 · 建立 `gen-grill` skill

**寫入**：`.claude/skills/gen-grill/SKILL.md`（新檔）

**內容結構**：

```markdown
---
name: gen-grill
description: 在 planner 產出規格之前盤問需求，直到問題定義、觸發場景、成功標準、
             範圍邊界、既有覆蓋五項齊備。需求已充分時直接放行。觸發條件：
             gen-dev-workflow STAGE 0a 啟動時、或使用者說「盤問我」「grill」。
---

# 需求盤問閘門 (gen-grill)

## 用途
在最強推論（planner/opus/xhigh）花成本寫整份規格**之前**，先確認需求本身沒歪。

## 🔴 本 skill 不自帶問法
盤問由既有 `brainstorming` skill 執行（它已具備一次一問、偏好選擇題的完整機制）。
本 skill 只負責：判定收斂 → 驅動 brainstorming → 產出 brief。

## 收斂判準（五項）
[Q1~Q5 表格，每項含「算齊備的形狀」與「不算的反例」]

## 短路條件（直接放行，不盤問）
符合任一項即放行：
- 需求已有規格或計畫文件背書（docs/features/ 或 docs/plans/ 已有對應檔）
- 需求來自已 triage 的 GitHub issue（帶 #編號且 issue body 含驗收條件）
- 需求是明確的機械性改動（改版號、修 typo、照既有表格逐項執行）
- quick 模式（見下）

## quick 模式行為
quick 是「小修正」通道，強制盤問會重演人在迴路過高的老問題。
quick 模式下本閘門**只跑 Q5（既有覆蓋實查）**，其餘四項略過。

## 產出：brief 交接格式
[結構化 brief 的欄位定義，交給 planner]

## 完成條件
五項齊備（或短路），且 brief 已產出。
```

**驗收**：
- `head -4` 顯示合法 frontmatter，`name: gen-grill` 與目錄名相符 → AC-1
- 五項判準各自可指認，非「大致清楚」這類不可證偽敘述 → AC-2
- 短路條件段落存在 → AC-3
- `grep -c brainstorming SKILL.md` ≥ 1 → AC-4
- brief 格式段落存在 → AC-6
- quick 模式行為明文 → AC-11

**🪶 Ponytail 約束**：
- 不寫 Rationalizations / Red Flags 三件套（Linus 模式 + Ponytail 已佔住該位置，§8.2 明載不抄）
- 不寫訪談問句範本（那是 brainstorming 的職責）
- 以**正面目標**撰寫（「盤問到五項齊備」），避免 negation——本 repo §6 C7 已指出 gen-dev-workflow negation 達 56 處/9 檔，新檔不加劇
- 目標 ≤ 60 行。超過表示混進了 brainstorming 的職責，砍掉重來

---

### Task 2 · 接進 STAGE 0a

**寫入**：`.claude/skills/gen-dev-workflow/SKILL.md`（修改 2 處）

**2a. 流程圖**（現行 `:36-46` 的 STAGE 0a 區塊）

在 `使用者：「幫我做 X 功能」`（`:33`）與 STAGE 0a 方框（`:36`）之間插入 grill 關卡，並在 0a 方框首行加一句前置條件：

```text
    使用者：「幫我做 X 功能」
           │
           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 0·grill：需求盤問（planner 之前的必經步驟）│
    │  → 呼叫 gen-grill skill                          │
    │  → 五項判準齊備 → 放行；任一項缺 → 驅動          │
    │    brainstorming 盤問該項後重新判定               │
    │  → 短路條件符合（已有規格/issue 背書/機械性改動   │
    │    /quick 模式）→ 直接放行，不盤問                │
    │  → 產出結構化 brief，交給 planner                 │
    │  （不動狀態機：轉移表維持 0a→0b→1→2→3→4）        │
    └──────────────────────┬──────────────────────────┘
                           │ 需求已收斂
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 0a：功能規格                             │
    │  → 呼叫 planner agent（依據 grill 產出的 brief） │
    │  ...（其餘不變）
```

**2b. 暫停點表格前的註記**（現行 `:158` 表格之前）

加一段說明，明確 grill **不新增暫停點**：

```markdown
> **STAGE 0·grill 不是暫停點。** 盤問本身就是對話往返，不需要 `stage-done` 棘輪，
> 也不改變下表的 7 個暫停點。它發生在 `wf-state.sh init` 之後、planner 派發之前，
> 狀態機完全無感（轉移表維持 `0a→0b→1→2→3→4`）。
```

**驗收**：
- `grep -c "grill" .claude/skills/gen-dev-workflow/SKILL.md` ≥ 2 → AC-5
- 暫停點表格仍為 7 列 → AC-10
- `git diff --stat` 不含 `wf-state.sh`、不含 `brainstorming/SKILL.md` → AC-7 / AC-9

---

## 5. 最終驗證（AC-12）

本項為純文件改動，**測試數與 analyze info 數應完全不變**：

```bash
flutter test                    # 預期：606 tests 全綠，數字與基線一致
flutter analyze lib/ test/      # 預期：7 個既有 info，一個不多
wf-state.sh get <現存 state 檔>  # AC-8：既有 state 檔仍可正常讀取
```

⚠️ **引述完整輸出**，不只回報判斷。若 info 數 ≠ 7，逐一指認第 8 個以後的歸屬；若 = 7，說明是哪 7 個（總數對但內容換掉仍會漏，此要求對齊 §8.2 A2）。

---

## 6. 執行方式建議

**序列，單一 session。** 理由：兩個任務合計 ~68 行文件改動，並行的協調成本高於收益；且 Task 2 需引用 Task 1 的實際內容。

---

## 7. 風險與退路

| 風險 | 徵兆 | 退路 |
|:---|:---|:---|
| SKILL.md 寫超過 60 行 | 混進了 brainstorming 的問法職責 | 砍掉問句範本，只留判準表 |
| 五項判準寫成不可證偽的形容詞 | 出現「需求夠清楚」「大致完整」 | 每項改寫成「能指著說第 N 項沒答」的形狀 |
| 流程圖插入後排版跑掉 | ASCII 方框對不齊 | 純視覺問題，對齊即可，不影響語意 |
| grill 實際被跳過 | 日後觀察到 planner 直接產規格 | 規格 §6 已載明此取捨（Guide 非 Sensor）。再議是否升級為 PreToolUse hook——**本次不做**，使用者已裁決不接狀態機 |

---

## 8. 落地後的回寫義務

依規格 §7，本項完成後需回寫 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`：

1. §6.5 表格的 C4 列 → 標為已完成
2. §5.7 表格的 A3 列 → 標為已併入 C4 完成
3. §6.3.1 與 §5(A)A3 → 補記規格 §1 的實查更正（brainstorming 一問一答機制早已存在，真正缺口是 workflow 零引用）

> 此步驟屬 STAGE 6 的文件同步範圍，由 `gen-sync-docs-by-branchs` 處理，不在本計畫的任務清單內。
