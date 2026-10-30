# 功能規格：匯出診斷報告時 DatabaseEntry JSON 序列化型別容錯（§Z1-2）

- **日期**：2026-10-29
- **來源**：`docs/brainstorm/2026-10-31-features-brainstorm.md` §Z1 第 2 項（既有缺陷 · 匯出報告時 DatabaseEntry.data 以 JsonEncoder.withIndent 編碼且無 toEncodable 導致崩潰）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在宿主 App 中使用診斷報告（Diagnostic Report）功能排查問題的開發者或 QA，
> 當 App 記錄了含有 `DateTime` 或其他非 JSON 原生型別物件的資料庫操作日誌（`DatabaseEntry.data`）時，
> 我希望**匯出報告（`buildDiagnosticReport`）能安全地將非原生型別物件轉化為字串呈現，而不是拋出 `JsonUnsupportedObjectError` 未捕獲例外崩潰**，
> 這樣在任何資料庫日誌內容下，診斷報告與匯出 Sheet（`ExportReportSheet`）都能穩定產生並完整呈現資料庫軌跡。

### 為什麼需要這項改進

目前在 `lib/src/utils/diagnostic_report.dart:152` 中，Database 區塊的序列化程式碼為：
```dart
final data = e.data;
if (data != null) {
  final payload = redact ? redactHeaders(data) : data;
  row +=
      '\n${_fenced(const JsonEncoder.withIndent('  ').convert(payload))}';
}
```
`JsonEncoder.convert()` 在遇到非 `num`、`String`、`bool`、`Null`、`List` 或 `Map`（且 key 必須為 `String`）的物件時，預設會拋出 `JsonUnsupportedObjectError`。
在真實應用場景中，宿主 App 傳入 `DatabaseEntry.data` 的 Map 經常包含 `DateTime`（例如 `createdAt: DateTime.now()`）、`Uri`、列舉或自訂模型。一旦觸發匯出報告，未帶 `toEncodable` 的 `JsonEncoder` 會直接拋出例外中斷整個報告產生程序。

對比專案內既有的 JSON 檢視器 `lib/src/ui/widgets/json_tree_viewer.dart:80`：
```dart
return JsonEncoder.withIndent('  ', (o) => o.toString()).convert(value);
```
此寫法透過提供 `(o) => o.toString()` 作為 `toEncodable` 回退，優雅地解決了非標準型別的序列化問題，並在既有程式碼中已經驗證。

---

## 2. 範圍邊界

### ✅ 做

- 修改 `lib/src/utils/diagnostic_report.dart` 中的 Database 區塊序列化：
  - 將 `const JsonEncoder.withIndent('  ').convert(payload)` 改為 `JsonEncoder.withIndent('  ', (o) => o.toString()).convert(payload)`。
  - 確保當 `DatabaseEntry.data` 內含有 `DateTime`、自訂物件或其他非 JSON 原生型別時，能平順呼叫其 `toString()` 轉化為字串輸出，消滅崩潰路徑。
- 於 `test/utils/diagnostic_report_test.dart` 增加單元測試：
  - 驗證當 `DatabaseEntry.data` 含有 `DateTime`、自訂物件、巢狀自訂型別時，`buildDiagnosticReport` 正常回傳含有其字串表示的 Markdown 區塊，且不拋出任何例外。
  - 驗證敏感資料遮蔽（redact）開啟與關閉時皆能正常運作。

### ❌ 不做

- 不改動 `DatabaseEntry` 的模型定義與欄位型別（維持 `Map<String, dynamic>? data`）。
- 不引入第三方序列化函式庫（維持標準 `dart:convert` 原生實作）。
- 不改動其他區段（Network / Navigation / Logs）的既有格式與邏輯。

---

## 3. 驗收條件

1. **型別容錯**：當 `DatabaseEntry` 的 `data` 包含 `DateTime` 時，呼叫 `buildDiagnosticReport(databaseEntries: [...])` 不會拋出 `JsonUnsupportedObjectError`，且輸出的 Database 區塊正確包含該日誌與縮排 JSON。
2. **測試覆蓋**：`test/utils/diagnostic_report_test.dart` 包含明確測試案例，斷言包含 `DateTime` 與自訂物件的 `DatabaseEntry` 成功被格式化。
3. **既有測試全綠**：既有 700+ 個單元測試全數通過，`flutter analyze` 零警告。
