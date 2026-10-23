---
name: retro
description: |
  環境與流程回顧（Retrospective）。以「Mechanical vs Judgement」嚴格二分法分析最近 session/PR 的摩擦與違規，將機械性違規轉化為自動化檢查腳本（Hook/Linter/Bash 斷言），嚴禁寫入 prompt/rules；判斷型問題才提煉為指引修訂建議。
  觸發條件：/retro, retro, 環境回顧, 開發回顧, 檢討環境
disable-model-invocation: true
---

# 環境與流程回顧 (retro)

你在執行一場專注於**「改善環境 (Environment)，而非指責 Agent」**的回顧。

> **核心信條**：
> 1. **預設是建檢查，不是寫規則**。
> 2. **機械性違規一律做成自動化檢查，嚴禁塞進 prompt 或 rules**。
> 3. **規則是最後手段，只給真正的判斷力（Judgement）問題**。

---

## 為什麼需要二分法？

當開發者或 AI Agent 犯錯時（例如：檔案放錯目錄、import 順序錯誤、誤用過時 API、遺漏特定欄位），人類最本能的直覺是：「在 prompt、CLAUDE.md 或 `.claude/rules/` 裡加上一行『請記得 X』或『禁止 Y』」。

這是極度有害的壞味道：
- **Context Load 爆炸**：每一條散文規則都在常駐燃燒 context token，每輪對話成本上升，並稀釋 LLM 對業務邏輯的專注力。
- **否定句失效模式**：LLM 存在 *don't think of an elephant* 效應，頻繁出現「禁止做 X」往往提高犯錯率。
- **無約束力**：散文式規範沒有編譯期或執行期的硬性保證，下次依然會漏。

---

## 判斷矩陣：Mechanical vs Judgement

| 維度 | Mechanical（機械性） | Judgement（判斷力） |
|:---|:---|:---|
| **定義** | 任何可藉由代碼特徵、AST、正則、檔案路徑、退出碼、Git diff 判定的規則 | 涉及主觀權衡、架構邊界、周邊程式碼風格契合度、過度工程簡化 |
| **典型場景** | • 檔案位置放置錯誤<br>• import 形狀或黑名單套件<br>• 固定語法/命名格式<br>• 缺少 required 宣告<br>• 退出碼與指令前綴校驗 | • 業務領域抽象是否過度<br>• 狀態管理層級劃分<br>• YAGNI 與可擴展性取捨<br>• 程式碼品味與直觀度 |
| **處理方式** | **一律產出自動化檢查**（Hook / Linter / Bash 斷言 / CI） | **提煉為規則指引**（`.claude/rules/`、guidelines） |
| **禁止行為** | **嚴禁**寫入 `.claude/rules/` 或 prompt！ | 避免教條化，規則須附帶動機與情境說明 |
| **落地載體** | • `analysis_options.yaml` (Dart linter)<br>• `.claude/hooks/` (PreToolUse / PostToolUse)<br>• Git hooks (pre-commit / commit-msg)<br>• Bash test 斷言 (如 `test_*.sh`) | • `.claude/rules/`<br>• `docs/architecture/`<br>• PR Reviewer 審查清單 |

---

## 執行流程（四步驟）

```text
  1. 收集摩擦點 ───► 2. 二分標籤化 ───► 3. 產出檢查/規範草稿 ───► 4. 條列 Action Items
```

### Step 1：收集事實與摩擦點
從三個管道收集本次開發發生的摩擦：
1. **Git 軌跡**：
   - 執行 `git log -n 5 --oneline` 查看最近提交。
   - 執行 `git diff --stat origin/main...HEAD` 檢視檔案異動範疇。
2. **失敗與重試紀錄**：
   - 當前 session 曾出現的測試失敗（Red）、編譯報錯或 linter 警告。
   - Reviewer / Verifier 曾打回要求修正的意見。
3. **使用者回饋**：
   - 詢問或解析使用者描述的阻礙（例如：「剛剛在處理 worktree 切換時卡住」、「Agent 每次都漏掉更新 brainstorm 表格」）。

### Step 2：進行二分分類
針對收集到的每個摩擦點，逐一進行問診：
- **問**：「這能用正則、腳本、AST 或退出碼抓出來嗎？」
  - **YES** → 標記為 **[Mechanical]**。
  - **NO** → 標記為 **[Judgement]**。

### Step 3：產出落地方案草稿
- **針對 Mechanical 項目**：
  - 設計最小、最笨但最有效的檢查腳本（Bash 斷言、Hook 或 Lint 規則）。
  - 明確附上驗證該檢查的測試方式。
- **針對 Judgement 項目**：
  - 遵循正面敘述原則（以「優先採用 X」取代「禁止 Y」）。
  - 將其歸納至對應的指引文件（如 `.claude/rules/`）。

### Step 4：輸出結構化回顧報告
依標準格式輸出診斷報告與行動待辦。**注意：不自動靜默覆寫任何檔案，保留工程師審核決定權。**

---

## 輸出報告範本

每次執行 `/retro` 時，以繁體中文輸出下列結構：

```markdown
# 🛠 開發環境回顧報告 (Retrospective)

- **目標分支 / PR**：`<branch-name> / <PR-link>`
- **回顧日期**：`YYYY-MM-DD`

---

## 1. 摩擦與事件診斷 (Incidents & Friction)
1. **事件 A**：<描述發生的問題，例如：測試因為某檔案路徑放錯而報錯>
2. **事件 B**：<描述審查被退回的原因，例如：新增了不必要的資料結構包裹>

---

## 2. 嚴格二分分析 (Mechanical vs Judgement)

### 🤖 機械性違規（一律自動化檢查，嚴禁寫入 Prompt/Rules）
| # | 問題描述 | 檢測特徵 | 落地方式 |
|:-:|:---|:---|:---|
| M1 | <問題> | <如：路徑不符合 docs/features/*.md> | <如：PreToolUse Hook 或 Bash 測試> |

#### 檢查腳本/配置草稿：
```bash
# 範例檢查腳本草稿
if [[ ... ]]; then
  echo "錯誤：..." >&2
  exit 1
fi
```

### 🧠 判斷型問題（提煉為規則指引）
| # | 問題描述 | 權衡盲點 | 改善指引歸宿 |
|:-:|:---|:---|:---|
| J1 | <問題> | <如：過早提取 Interface，違反 YAGNI> | `.claude/rules/expert-rules.md` |

#### 指引條款建議草稿：
> **[正面指引建議]**：...

---

## 3. 行動待辦清單 (Action Items)
- [ ] **[Mechanical]** 建立/更新檢查腳本 `<path>`
- [ ] **[Mechanical]** 在 `.claude/settings.json` 掛載 Hook 或加入 CI
- [ ] **[Judgement]** 修訂 `<rules-path>` 指引條款
```

---

## 範例示範

### 情境：
開發者在開發某 feature 時，實作 agent 將規格檔放在 `docs/spec.md` 而非 `docs/features/YYYY-MM-DD-<name>.md`；且在重構時宣告了一個只被使用一次的抽象基類 `BaseInspectorEngine`。

### Retro 處理：
1. **檔案路徑放置錯誤** ➔ **[Mechanical]**：
   - ❌ 錯誤作法：在 `.claude/rules/` 加上「*每次寫規格都必須放在 docs/features/*」。
   - ✅ 正確作法：撰寫一支 Bash 斷言或 PreToolUse hook，檢查若建立新規格檔路徑非 `docs/features/YYYY-MM-DD-*.md` 即報錯退出。
2. **過早建立單次使用的抽象基類** ➔ **[Judgement]**：
   - ✅ 正確作法：在 `expert-rules.md` (Linus 模式) 強調「YAGNI 原則：單一實作不需要 Interface / BaseClass，具體類別優先」。
