# 實作計畫：匯出診斷報告時 DatabaseEntry JSON 序列化型別容錯（§Z1-2）

- **日期**：2026-10-29
- **規格**：[`docs/features/2026-10-29-diagnostic-report-db-json-encodable.md`](../features/2026-10-29-diagnostic-report-db-json-encodable.md)
- **來源**：`docs/brainstorm/2026-10-31-features-brainstorm.md` §Z1-2
- **Effort**：trivial

---

## 1. 資料結構與設計方向 Trade-off

**不新增任何資料結構、欄位或公開 API。**

### 方案比較

1. **方案 A（採用）：在 `diagnostic_report.dart` 傳入 `(o) => o.toString()` 作為 `JsonEncoder.withIndent` 的 `toEncodable` 回退**
   - 實作方式：
     ```dart
     row += '\n${_fenced(JsonEncoder.withIndent('  ', (o) => o.toString()).convert(payload))}';
     ```
   - **優點**：
     - 精確對齊 `lib/src/ui/widgets/json_tree_viewer.dart:80` 既有成熟寫法。
     - 當 payload 中僅部分欄位為非 JSON 原生物件（如 `createdAt: DateTime`）時，其餘原生物件仍保持標準 JSON 結構與排版，僅非原生欄位安全轉為字串表示。
     - 零多餘物件配置，零外部依賴，消除 `JsonUnsupportedObjectError` 崩潰路徑。
2. **方案 B（不採用）：在外部以 try-catch 包裹 `convert()` 拋錯時改用 `payload.toString()`**
   - **缺點**：若 payload 僅包含一個 `DateTime` 屬性，整個 JSON 結構都會丟失並退化為純文字，破壞 Markdown 報告的可讀性與一致性。
3. **方案 C（不採用）：手動遞迴走訪 Map 檢查並轉化 `DateTime` 為 ISO-8601**
   - **缺點**：增加深層走訪與物件複製負擔，且無法覆蓋 `Uri` 或其他自訂領域模型型別。

---

## 2. 檔案異動清單

| 檔案 | 動作 | 說明 |
|:---|:---:|:---|
| `lib/src/utils/diagnostic_report.dart` | 修改 | 將 `Database` section 序列化改為 `JsonEncoder.withIndent('  ', (o) => o.toString()).convert(payload)` |
| `test/utils/diagnostic_report_test.dart` | 修改 | 新增含有 `DateTime`、自訂非 JSON 物件之 `DatabaseEntry` 匯出報告測試 |

---

## 3. 任務拆分

**總任務數：1（單一任務 `[快/便宜]`）**

### Task 1 `[快/便宜]`：為 `buildDiagnosticReport` 的 Database 區塊加入 `toEncodable` 回退與單元測試

**寫入路徑**：
- `lib/src/utils/diagnostic_report.dart`
- `test/utils/diagnostic_report_test.dart`

**實作步驟**：
1. 修改 `lib/src/utils/diagnostic_report.dart:152`，移除 `const` 並傳入 `(o) => o.toString()`。
2. 在 `test/utils/diagnostic_report_test.dart` 加入測試案例：
   - 建立含 `DateTime` 與自訂 Class 物件的 `DatabaseEntry`。
   - 呼叫 `buildDiagnosticReport` 並確認無拋錯，且輸出字串中包含該欄位的字串表示。
   - 驗證 `redact: true` 下依然安全運作。
3. 執行 `flutter test test/utils/diagnostic_report_test.dart` 與全套單元測試確保全綠。

---

## 4. 驗收契約

- **測試指令**：`flutter test`
- **靜態檢查**：`flutter analyze lib/ test/`（維持既有 7 個 info 基線，零新增警告）
