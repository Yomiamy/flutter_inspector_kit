# A3 · STAGE 3 審查 Lens 規模特徵裁決規範（Feature-Driven Review Lenses）

> **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §8.2 A3
> **狀態**：功能規格（What & Why）· 2026-09-25

---

## 1. 🔴 痛點與原提案批判（Linus-Style Critique）

### 1.1 現況痛點

在 `gen-dev-workflow` 中，STAGE 3 為審查與驗收階段。目前的平行審查機制（`workflow-parallel.md` 適用點 3）**固定派發 5 個最高推論（`effort: xhigh`）的獨立 Lens（Verifier 子 Agent）**：
1. `correctness`（邏輯正確性）
2. `security`（安全性）
3. `回歸風險`（既有功能與生命週期破壞）
4. `測試覆蓋`（測試完整性）
5. `過度工程`（YAGNI 與不必要抽象）

在較大的改動（如 > 200 行、跨多模組）時，這種分工能有效防範 Attention 稀釋與盲區。
但在**小型或特徵單純的改動**上，一律開滿 5 個 Lens 會帶來兩個結構性危害：
1. **資訊冗餘與同義反覆**：多個 Agent 把同一件事換 4 種術語各自回報一遍，主 Reviewer 需耗費大量 Token 去重。
2. **Context 爆炸**：5 份長篇報告同時注入主對話，極易在審查階段撞上 150K Token 警戒線。

### 1.2 原 A3 提案的致命缺陷：以行數一刀切是湊合的偷懶設計

原 A3 提案嘗試以 `diff < 200 行` 作為閘門，規定小於 200 行就只開 2 個 Lens（去掉 Security 與回歸風險）。

**這是嚴重的壞品味與偽安全：**
* **改動行數（LOC）是語意極度低下的指標**：
  * 改 500 行的 UI 排版重構，可能 0 安全與回歸風險；
  * 只改 3 行的身份鑑權、Token 儲存或全域狀態更新，可能引入致命漏洞或 Crash。
* 若純以行數小為由省略 Security 或回歸風險，只要有人在小 PR 裡改壞 auth 或全域單例，該機制就會直接漏放。

---

## 2. 核心設計原則：風險特徵驅動（Feature-driven Guard Clause）

**省略專門 Lens 的正當理由，不是「行數少」，而是「該改動在物理上不具備產生該類缺陷的條件」。**

如同程式碼中的衛語句（Guard Clause）：
```dart
// 只有在具備攻擊面或共享狀態的物理條件下，才派發昂貴的專案審查進程
if (!hasAttackSurface) skipSecurityLens();
```

### 2.1 雙層裁決模型

STAGE 3 的 Lens 派發依據以下兩層規則決定：

#### 第一層：核心基線（必開）
* **`correctness`**：永遠不可省略，所有改動都必須確認業務邏輯與邊界處理。
* **`過度工程`（Ponytail Lens）**：永遠不可省略，專門找出「不該存在的東西」（計畫外的抽象、過度防禦分支），與找缺陷的維度天然互斥，性價比最高。

#### 第二層：特徵驅動派發（條件成立才開獨立子 Agent）

| 專門 Lens | 派發條件（滿足任一即開） | 略過條件（滿足時免除獨立 Lens） |
|:---|:---|:---|
| **`security`** | • 涉及網路傳輸、Dio/HTTP 攔截<br>• 涉及金鑰、Token、認證、敏感資料遮罩<br>• 涉及反序列化、外部資料解析、條件匯出 | • 純內部 UI 樣式、字串排版<br>• 純離線工具腳本或文件更動<br>• 改動範圍物理上無外部輸入與權限邊界 |
| **`回歸風險`** | • 涉及核心緩衝區（`RingBuffer`、`mergedTimeline`）<br>• 涉及生命週期（`WidgetsBindingObserver`、dispose、listener 註銷）<br>• 涉及全域狀態、公共 API 簽章更動 | • 獨立新檔案且無現有呼叫端<br>• 純局部無狀態 Helper/Extension<br>• 純樣式常數或純 UI 元件微調 |
| **`測試覆蓋`** | • 新增業務邏輯、分支條件、演算法<br>• 重構核心路徑或修復特定 Bug | • 純文字/註解更新、純樣式微調<br>• 僅修改 workflow 規範文件或輔助腳本 |

#### 特殊收斂（Context 防衛閘門）
* 若主對話已逼近 100K Token 警戒線，為防止對話中斷，一律收斂為「僅派發 `correctness` + `過度工程`」，其餘維度改由主 Reviewer 內化速審。

---

## 3. 主審（Reviewer）責任底線與兜底契約

**未派發專門 Lens，絕不等於放棄該維度的審核。**

為防止「沒開 Lens 就假裝沒事」的認知漂移，建立明確的主審兜底契約：
1. **主審全權負責**：主 Reviewer（Opus）自身具備最高推論能力，未派發專門 Lens 的維度由主 Reviewer 在審查時親自覆核。
2. **審查報告明載免除判定（Guard Clause Record）**：
   在 STAGE 3 產出的最終審查報告中，若有專門 Lens 被略過，主 Reviewer 必須明載「前置判定理由」，例如：
   > `[Security Lens]`: 本次改動僅涉及 workflow 規範文件與 markdown，無網路傳輸與敏感資料攻擊面，依特徵規則免除獨立派發，主審覆核確認安全。

---

## 4. 影響範圍

1. `.claude/skills/gen-dev-workflow/references/workflow-parallel.md`
   - 更新適用點 3 的審查 Lens 派發規格與範例代碼，落實特徵驅動裁決矩陣。
2. `.claude/agents/reviewer.md`
   - 明訂 Reviewer 在收斂多 Lens 報告時的責任底線，要求明載免除派發的判定依據。
3. `docs/brainstorm/2026-09-17-workflow-brainstorm.md`
   - 更新 §8.2 A3 提案內容，將原「diff < 200 行一刀切」修正為「特徵驅動裁決」，保持文件與實施一致。

---

## 5. 驗收條件（Acceptance Criteria）

* [x] `workflow-parallel.md` 清楚定義特徵驅動的 Lens 派發判準，刪除純 LOC 一刀切敘述。
* [x] `workflow-parallel.md` 提供完整示例，展示如何依據改動檔案特徵過濾 `LENSES` 陣列。
* [x] `reviewer.md` 增補「未派發專門 Lens 時之兜底與免除記錄」職責段落。
* [x] `docs/brainstorm/2026-09-17-workflow-brainstorm.md` 的 A3 段落同步修訂，狀態保持連貫。
