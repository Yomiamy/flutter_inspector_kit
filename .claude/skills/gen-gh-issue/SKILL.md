---
name: gen-gh-issue
description: 根據程式碼痛點與分析，以中文生成一個結構化、直指核心的 GitHub Issue 描述，符合 Problem/Root Cause/Fix/Out of Scope/Verification 風格。
---

# gen-gh-issue

此技能用於將偵測到的 Bug、需求或分析結果，轉換為一份結構嚴謹、直指核心的 GitHub Issue 中文描述。

## 核心原則

1. **實用主義與好品味**：描述必須直切要害，不說廢話。程式碼層級的 Root cause 必須經過驗證才寫入。
2. **中英混用**：使用中文（zh-tw）撰寫，但必須保留所有必要的 `en-us` 技術術語（例如類別名、方法名、API、平台 delegate 等）。
3. **明確的邊界**：必須劃分出 Fix 與 Out of Scope 的界線，避免解決不存在的問題（Over-engineering）。

## GitHub Issue 範本結構

生成的 GitHub Issue Markdown 必須嚴格遵循以下五個區段：

```markdown
## 問題描述 (Problem)
<描述在什麼操作或配置下發生了什麼錯誤。例如：在 showNetworkNotification 為 true 時，iOS 前景無法跳出通知。>

## 根本原因（已驗證）(Root cause - verified)
<條列或說明造成該問題的底層原因、平台限制或 Race condition。必須精確到類別、方法或設定項目。>

## 修復方案 (Fix)
- **A** <檔案路徑/類別>：<具體修改內容>
- **B** <檔案路徑/類別>：<具體修改內容>
- **C** <檔案路徑/類別>：<具體修改內容>

## 排除範圍 (Out of scope)
<說明哪些是本次修復「不」處理的項目，例如相關但非根本原因的模組、或不需更動的既有機制。>

## 驗證方式 (Verification)
<說明如何驗證修復。例如：flutter analyze 確保無警告、flutter test 確保全綠、以及實機上的測試要求。>
```

## 執行流程

1. **收集資訊**：讀取當前 branch 的 `git diff`、相關 issue doc 或是使用者提供的 Brief 資訊。
2. **分析與結構化**：
   - 提取 **Problem**：使用者感知到的錯誤現象。
   - 提取 **Root Cause**：底層程式碼或配置上的漏洞。
   - 提取 **Fix**：需要更動的檔案與具體邏輯。
   - 提取 **Out of Scope**：確認這次改動的邊界。
   - 提取 **Verification**：定義測試與驗證通過的標準。
3. **產生 Markdown**：依據上述範本，使用繁體中文（zh-tw）與專業的英文術語（如 `UNUserNotificationCenterDelegate`）組裝出最終的 Issue 描述，並以 fenced `md` code block 呈現給使用者。
