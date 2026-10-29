# 功能規格：`truncateBody` 截斷防護 UTF-16 Surrogate Pair（§Z1-4）

- **日期**：2026-10-29
- **來源**：`docs/brainstorm/2026-10-22-features-brainstorm.md` §Z1 第 4 項（既有缺陷 · `truncateBody` 以 `substring(0, kNetworkBodyMaxLength)` 截斷可能切斷 surrogate pair）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在宿主 App 中使用 Flutter Inspector Kit 排查網路請求的開發者，
> 當 App 傳輸的請求或回應 Body 超過 10 KB（`kNetworkBodyMaxLength`），且截斷邊界恰好落在 UTF-16 Surrogate Pair（例如 Emoji 或四字節 Unicode 字元）中間時，
> 我希望**套件在截斷時能自動退回前一個完整字元邊界，避免產生孤立的 High Surrogate（半個 Emoji）**，
> 這樣截斷後的字串在進行 JSON 序列化、UTF-8 轉換、UI 渲染與複製時，不會產生亂碼（`\uFFFD`）或拋出非預期的字串處理例外。

### 為什麼需要這項改進

目前在 `lib/src/models/network_entry.dart:134-138`：
```dart
static String? truncateBody(String? body) {
  if (body == null) return null;
  if (body.length <= kNetworkBodyMaxLength) return body;
  return body.substring(0, kNetworkBodyMaxLength) + kTruncatedMarker;
}
```
Dart 的 `String` 底層是由 UTF-16 code units 組成。超出 Basic Multilingual Plane（BMP）的字元（如常見 Emoji `😀`、特殊符號等）佔用兩個 16-bit code units：
- **High Surrogate（前導代碼）**：`0xD800` ~ `0xDBFF`
- **Low Surrogate（後隨代碼）**：`0xDC00` ~ `0xDFFF`

若字串在剛好第 10240 位元（`kNetworkBodyMaxLength`）處被生硬切斷，而第 10240 位元正好是 High Surrogate，該 Surrogate Pair 的 Low Surrogate 就會被切掉，使截斷字串末端殘留一個「孤立的 High Surrogate」。
這類畸形字串一旦經過 `utf8.encode()` 或傳入不容錯的解析器，會拋出 `FormatException` 或被強制置換為 ``（REPLACEMENT CHARACTER）。

---

## 2. 範圍邊界

### ✅ 做

- 修改 `lib/src/models/network_entry.dart` 的 `truncateBody` 方法：
  - 檢查截斷終點前一位 `body.codeUnitAt(kNetworkBodyMaxLength - 1)` 是否落在 High Surrogate 範圍（`0xD800` ~ `0xDBFF`）。
  - 若命中 High Surrogate，截斷長度退 1（即截斷至 `kNetworkBodyMaxLength - 1`），完整丟棄該破損字元。
  - 照常在末端附加 `kTruncatedMarker`。
- 在 `test/models/network_entry_test.dart` 增加單元測試：
  - 測試在截斷邊界恰好落於 Emoji（如 `😀`）High Surrogate 時，截斷結果不會包含孤立 High Surrogate。
  - 測試截斷邊界剛好完整包含 Emoji（Low Surrogate 落於最後一位）時正常保留該 Emoji。
  - 測試截斷字串可安全被 `utf8.encode()` 與 `jsonEncode()`。

### ❌ 不做

- 不更動 `kNetworkBodyMaxLength` 上限數值（維持 10 KB）。
- 不引入外部 Unicode 庫（如 `characters` 套件），以最輕量、O(1) 的單一代碼檢查消除問題，避免對大字串產生額外配置與遍歷負擔。
- 不更動 `truncateBody` 以外的任何邏輯。

---

## 3. 驗收條件

1. **Surrogate Pair 完整性**：當字串在 `kNetworkBodyMaxLength` 處正好切在 Surrogate Pair 中間時，`truncateBody` 回傳的有效本文不含孤立 High Surrogate，長度為 `kNetworkBodyMaxLength - 1 + kTruncatedMarker.length`。
2. **邊界測試覆蓋**：新增單元測試覆蓋 High Surrogate 邊界、Low Surrogate 邊界以及普通 ASCII / BMP 字元邊界。
3. **靜態分析與回歸**：`flutter analyze` 零新增警告，既有全部單元測試全數 PASS。
