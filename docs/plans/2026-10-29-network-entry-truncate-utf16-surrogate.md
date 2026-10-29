# 實作計畫：`truncateBody` 截斷防護 UTF-16 Surrogate Pair（§Z1-4）

- **日期**：2026-10-29
- **規格**：[`docs/features/2026-10-29-network-entry-truncate-utf16-surrogate.md`](../features/2026-10-29-network-entry-truncate-utf16-surrogate.md)
- **來源**：`docs/brainstorm/2026-10-22-features-brainstorm.md` §Z1-4
- **Effort**：trivial

---

## 1. 資料結構與設計方向 Trade-off

**不新增任何資料結構、公開屬性或外部套件依賴。**

### 方案比較

1. **方案 A（採用）：O(1) 檢查末位 Code Unit 是否為 High Surrogate**
   - 實作方式：
     ```dart
     static String? truncateBody(String? body) {
       if (body == null) return null;
       if (body.length <= kNetworkBodyMaxLength) return body;
       var end = kNetworkBodyMaxLength;
       final unit = body.codeUnitAt(end - 1);
       if (unit >= 0xD800 && unit <= 0xDBFF) {
         end--;
       }
       return body.substring(0, end) + kTruncatedMarker;
     }
     ```
   - **優點**：
     - **Good Taste**：直指 UTF-16 編碼本質。在 UTF-16 中，僅有 High Surrogate（`0xD800` ~ `0xDBFF`）位於截斷邊界前一位時才會造成 Surrogate Pair 被腰斬；Low Surrogate（`0xDC00` ~ `0xDFFF`）在末位代表該字元完整被包含。
     - **效能極致（O(1)）**：`codeUnitAt` 為常數時間原生陣列存取，零多餘字串配置與走訪。
     - **消滅邊界例外**：徹底杜絕殘留半個 Emoji 導致的 `FormatException` 或 `\uFFFD` 亂碼。
2. **方案 B（不採用）：使用 `package:characters` 或 `runes` 走訪字元**
   - **缺點**：
     - 若字串超過 10,240 個 UTF-16 code unit，將整段本文轉換為 `characters` 或 `runes` 需完整遍歷並在記憶體中配置大量 Grapheme Cluster / Rune 物件，帶來嚴重的觀察者效應與效能損耗。
3. **方案 C（不採用）：截斷後使用 `utf8.decode(utf8.encode(..., allowMalformed: true))` 修復**
   - **缺點**：引入兩次完整的 UTF-8 編碼與解碼配置，代價高昂且會把畸形字元轉為 `\uFFFD`，不如直接在截斷時完整丟棄該破損字元。

---

## 2. 檔案異動清單

| 檔案 | 動作 | 說明 |
|:---|:---:|:---|
| `lib/src/models/network_entry.dart` | 修改 | `truncateBody` 增加末位 High Surrogate 檢查與 `end--` 避讓防護 |
| `test/models/network_entry_test.dart` | 修改 | 於 `truncateBody` 測試群組增加切在 Surrogate Pair 邊界時的單元測試與安全序列化斷言 |

---

## 3. 任務拆分

**總任務數：1（單一任務 `[快/便宜]`）**

### Task 1 `[快/便宜]`：為 `NetworkEntry.truncateBody` 加入 UTF-16 High Surrogate 防護與單元測試

**寫入路徑**：
- `lib/src/models/network_entry.dart`
- `test/models/network_entry_test.dart`

**實作步驟**：
1. 修改 `lib/src/models/network_entry.dart:134-138`：
   - 讀取 `body.codeUnitAt(kNetworkBodyMaxLength - 1)`。
   - 若落在 `0xD800..0xDBFF` 範圍，則 `end = kNetworkBodyMaxLength - 1`。
   - 回傳 `body.substring(0, end) + kTruncatedMarker`。
2. 在 `test/models/network_entry_test.dart` 的 `truncateBody` group 增加測試：
   - **切在 High Surrogate**：前 10239 個字元為普通 ASCII，第 10240 為 emoji（如 `😀` = `\uD83D\uDE00`），斷言截斷後的本文長度為 10239，不包含殘留的 `\uD83D`，且 `utf8.encode(result)` 與 `jsonEncode(result)` 不報錯。
   - **剛好完整包含 Emoji**：前 10238 個字元為普通 ASCII，接 emoji（長度剛好為 10240），斷言 emoji 被完整保留。
   - **超長且邊界為完整 Emoji**：前 10238 個字元為普通 ASCII，接 emoji，再接其他字元（總長 > 10240），斷言 emoji 被完整保留。
3. 執行 `flutter test test/models/network_entry_test.dart` 及全套測試。

---

## 4. 驗收契約

- **測試指令**：`flutter test`
- **靜態檢查**：`flutter analyze lib/ test/`（維持既有基線，零新增警告）
