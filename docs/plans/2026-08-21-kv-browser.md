# 實作計畫：鍵值儲存檢視器（Key-Value Browser）

> 對應規格：`docs/features/2026-08-21-kv-browser.md`（**38 條 AC**，rev.2）
> 本文件只描述 How。What & Why 已在規格定案，不重複。
> 撰寫日期：2026-08-21 ｜ 最後修訂：2026-08-21（rev.2）

---

## 修訂紀錄

### 2026-08-21（rev.2）歸屬翻案：KV 改掛獨立 Storage Tab

**上游變更**：使用者推翻「KV 併入 Database Tab」，改為獨立的 Storage Tab。
理由見規格修訂紀錄（「區分儲存引擎本身就是排查資訊，RD 需要這個訊號」）。

**本計畫的連鎖變更**

| 章節 | 變更 |
|------|------|
| §2（R-4/U-5 設計難題） | **整節改寫**。原本的核心設計難題「兩種型別如何共存於一個 dropdown」**因歸屬改變而消失，不是被解決**。原方案 A/B/C 比較降格為歷史紀錄 |
| §2.4 U-1 定案 | 從「不更名 Database Tab」改為「Database Tab 不動、KV 另開 Storage tab」 |
| §3 檔案異動 | `database_tab.dart` 從「修改」移到「明確不改」；`dashboard_modal.dart` 新增為「修改」 |
| **T13** | **整個改寫**：「Database Tab 分流接線」→「Dashboard 新增 Storage Tab 接線」 |
| T7 | 新增「Storage tab 根 widget」職責（原本 KV 視圖是 Database Tab 的子樹，現在是 tab 本身） |
| §5 相依圖 | T13 的相依從 T5/T7 改為 T5/T7/T12，位置不變（仍是最後接線） |
| §6 測試策略 | 對應 38 條 AC 重排；新增 `dashboard_modal_test.dart` 一列 |
| §7 風險 | **最大風險換人**：從「T13 破壞 database_tab 既有測試」改為「T13 破壞 dashboard 既有 5 處 tab 數／index 斷言」 |

**任務數：15 → 15（不變）**。T13 換了目標檔案但仍是一個任務，其餘任務不受影響。

**🔴 rev.2 的關鍵實查修正（推翻了交辦時的假設）**

交辦說明稱「既有測試沒有寫死 tab 數或 tab 順序，這降低了新增 tab 的破壞風險」，
並要求自行實查確認。**實查結果：這個說法是錯的。** 實際有 5 處寫死：

| 位置 | 斷言 |
|------|------|
| `test/ui/dashboard_modal_test.dart:17` | `expect(find.byType(Tab), findsNWidgets(4));` |
| `test/ui/dashboard_modal_test.dart:56` | `expect(controller.index, 3);`（clamp 到最後一個 tab） |
| `test/ui/dashboard_modal_test.dart:70` | `expect(find.byType(Tab), findsNWidgets(5));`（有 custom tab 時） |
| `test/ui/dashboard_error_badge_test.dart:40` | `expect(find.byType(Tab), findsNWidgets(4));` |
| `test/ui/dashboard_error_badge_test.dart:97` | `expect(find.byType(Tab), findsNWidgets(4));` |

**但這 5 處全部不注入 `keyValueSources`**，所以在「條件性顯示 Storage tab」的設計下
（規格 AC-30），它們看到的仍是 4／5 個 tab，斷言不需修改即通過。

這把「條件性顯示」從一個 UX 偏好升級為**硬性設計約束**：
若無條件新增 Storage tab，這 5 條測試立刻全紅，違反 AC-36。

---

## 0. 使用者已拍板、不再討論的前提

以下三項為輸入條件，本計畫直接採用，不再提供替代方案：

1. **範圍＝完整讀寫**：列表 + 搜尋 + inline 編輯 + 刪除 + 清空，寫入須二次確認 + 自動記 Console log。
2. **R-2 選 A**：KV 自己新寫搜尋欄。`console_tab.dart:289` 與 `network_tab.dart:129` 的既有
   `_SearchBar` **一行都不動**，也不抽共用元件（連 follow-up 建議都不列）。
3. **R-1 選 B**：新寫獨立 widget，不擴充 `KeyValueTable`。
   `lib/src/ui/widgets/key_value_table.dart` 的 4 個既有唯讀呼叫端零改動。
4. **歸屬＝獨立 Storage Tab**（rev.2 新增）：KV 不併入 Database Tab。
   `database_tab.dart` 一個字不改。Storage tab **條件性顯示**——
   未注入 `keyValueSources` 時不出現（比照 `customTab` 慣例）。

---

## 1. 資料結構設計

> 「爛程式員擔心程式碼。好程式員擔心資料結構。」——這節決定了後面所有任務的難度。

### 1.1 核心介面（新檔 `lib/src/models/key_value_browser_source.dart`）

形狀直接鏡射既有 `DatabaseBrowserSource`（abstract class + `String get name` + `Future` 方法），
不發明新模式。

```dart
abstract class KeyValueBrowserSource {
  String get name;
  Future<List<KeyValueEntry>> listAll();
  Future<void> setValue(String key, Object? value);
  Future<void> remove(String key);
  Future<void> clear();
}
```

`setValue` 的 `value` 型別採 `Object?`：AC-18 要求「輸入字串無法轉為原型別時不呼叫 setValue」，
代表**型別轉換發生在 UI 層、轉換成功後才呼叫介面**。介面收 `Object?` 而非 `String`，
消費端實作可直接 `switch` 分派到 `prefs.setInt` / `setBool` / `setString`，不必再解析一次字串。

> ⚠️ 需實查驗證的假設：`setValue(String key, Object? value)` 用 positional 兩參數，
> 符合 flutter-styles §2.8「1~2 個語意極度明確的參數用 positional」。若 review 認為
> 語意不明確，改 named 亦可，不影響其他設計。

### 1.2 資料類 `KeyValueEntry`（同檔）

```dart
@immutable
class KeyValueEntry {
  const KeyValueEntry({
    required this.key,
    required this.value,
    required this.type,
  });

  final String key;
  final Object? value;
  final KeyValueType type;

  // operator == / hashCode / toString  —— 鏡射 DatabaseTableInfo 的既有慣例
}
```

### 1.3 型別列舉 `KeyValueType`（同檔）

```dart
enum KeyValueType { string, int, double, bool, stringList }
```

**為什麼用 enum 而不是 `Type` 或字串**：AC-18 的驗證邏輯需要「依原型別決定如何 parse 使用者輸入」。
用 enum 可以寫成一個窮盡式 `switch` expression（flutter-styles §5.4），編譯器強制覆蓋所有分支；
用 `Type` 物件則需要 `if (type == int) ... else if (type == String)` 的鏈式判斷，
新增型別時不會有編譯期保護。這是「消滅特殊情況」的直接應用。

`stringList` 納入是因為 `SharedPreferences` 原生就有 `getStringList`，
消費端寫 source 時繞不開。**不是**預留擴充點。

### 1.4 型別驗證的資料流（AC-18 的落點）

驗證是純函式，與 UI 無關，因此**放在 model 層、獨立可測**：

```dart
/// 依 [type] 嘗試把使用者輸入的字串轉為對應型別。
/// 回傳 null 代表轉換失敗（UI 據此顯示驗證錯誤且不呼叫 setValue）。
Object? parseKeyValueInput(String raw, KeyValueType type);
```

> 用「回傳 null 代表失敗」而非拋例外：呼叫端只有一處（編輯 dialog），
> 且失敗是預期路徑不是異常路徑。拋例外會逼呼叫端寫 try-catch，是為單一場景增加噪音。
>
> ⚠️ 邊界情況需在測試中釘死：`KeyValueType.string` 恆成功（任何字串都合法，
> 含空字串）；`bool` 只接受 `'true'` / `'false'`（不分大小寫）；
> `stringList` 的輸入格式為**換行分隔**（逗號會與 value 本身衝突，換行在多行 TextField 中最自然）。

### 1.5 掛載位置：獨立 Storage Tab（rev.2 定案，見 §2）

---

## 2. 歸屬決策：獨立 Storage Tab（rev.2 改寫）

### 2.1 原本的核心設計難題**已消失**

rev.1 的 §2 花了整節處理一個問題：

> 「`KeyValueBrowserSource` 與 `DatabaseBrowserSource` 不共享任何方法，
> 要放進同一個 `DropdownButton` 必須解決型別問題。」

**這個問題現在不存在了。** 不是被解決，是被**取消**——因為前提消失了。

獨立 Storage tab 後：

- Storage tab 有自己的 `DropdownButton<KeyValueBrowserSource>`，泛型明確
- Database tab 保留自己的 `DropdownButton<DatabaseBrowserSource>`，一個字不改
- 兩者從不出現在同一棵子樹，**沒有任何地方需要 `is` 判斷型別**
- rev.1 方案 B 設計的 `kvSources.isEmpty` early-return 分流與 `_StorageTabScaffold`
  分段切換器，**全部不需要了**

> **Linus 判準**：rev.1 方案 B 的價值主張是「重新問問題，讓特殊情況消失」。
> rev.2 更進一步——**連問題本身都不用問**。當一個設計難題可以靠改變功能歸屬而蒸發，
> 那說明原本的歸屬決策才是難題的來源。這是「特殊情況是爛設計的補丁」的教科書案例：
> 我們差點為了一個不必要的合併，去發明一個上層抽象。

**連帶收益**：`database_tab.dart` 的改動量從「build 方法重構」降為**零**。
rev.1 中被列為「破壞性風險最高」的 T13 因此換了完全不同的形狀（見下方風險重評）。

### 2.2 歷史決策紀錄：為何日後不該又想把兩者合併

以下是 rev.1 的實查證據。**它仍然有效**——如果未來有人提議「把 Storage 併回
Database，共用一個 source 選擇器」，這段就是現成的否決依據，不需要重新調查。

**實查 `test/ui/tabs/database_tab_test.dart`：L114、L121、L151 把 dropdown 的
泛型參數寫死在斷言裡：**

```dart
expect(find.byType(DropdownButton<DatabaseBrowserSource>), findsOneWidget);
await tester.tap(find.byType(DropdownButton<DatabaseBrowserSource>));
expect(find.byType(DropdownButton<DatabaseBrowserSource>), findsNothing);
```

**任何會改變該 dropdown 泛型參數的方案都會弄紅這三條測試。** 只要把
`DropdownButton<DatabaseBrowserSource>` 改成 `DropdownButton<某個上層抽象>`，
`find.byType` 就找不到。

也就是說，「引入共同 marker interface 讓兩類 source 共用一個 dropdown」這條路
（rev.1 的方案 A）**在既有測試層面就是死路**，而且它付出破壞公開 API 形狀的代價，
卻換不到「消滅型別判斷」——選出來之後 body 仍得知道這是 DB 還是 KV。

<details>
<summary>rev.1 §2 原文（方案 A / B / C 完整比較，已失效，僅供追溯）</summary>

##### rev.1 §2.1 問題重述

實查事實（已逐行驗證）：

| 位置 | 內容 |
|------|------|
| `database_tab.dart:22` | `late DatabaseBrowserSource _selectedSource;` |
| `database_tab.dart:31` | `_selectedSource = widget.inspector.databaseSources.first;` |
| `database_tab.dart:71` | `final isOpLog = _selectedSource is OperationLogSource;` |
| `database_tab.dart:79` | `if (sources.length > 1)` 才顯示 dropdown |
| `database_tab.dart:80` | `DropdownButton<DatabaseBrowserSource>(` |

`KeyValueBrowserSource` 與 `DatabaseBrowserSource` **不共享任何方法**（一個 `listTables`/`fetchRows`，
一個 `listAll`/`setValue`/`remove`/`clear`）。要放進同一個 dropdown，必須解決型別問題。

##### rev.1 §2.2 決定性的新發現（實查 `test/ui/tabs/database_tab_test.dart`）

既有測試 L114 與 L121、L151 **把 dropdown 的泛型參數寫死在斷言裡**：

```dart
expect(find.byType(DropdownButton<DatabaseBrowserSource>), findsOneWidget);
await tester.tap(find.byType(DropdownButton<DatabaseBrowserSource>));
expect(find.byType(DropdownButton<DatabaseBrowserSource>), findsNothing);
```

**這直接槍斃了任何會改變 dropdown 泛型參數的方案。** AC-31 要求「既有 Database Tab 全部測試
在未修改測試碼的前提下通過」——只要把 `DropdownButton<DatabaseBrowserSource>` 改成
`DropdownButton<StorageSource>`（或任何上層抽象），`find.byType` 就找不到，三處斷言全紅。

這不是實作細節，是**硬性約束**。以下方案比較必須在此前提下進行。

##### rev.1 §2.3 方案比較

###### 方案 A：引入共同上層抽象（marker interface）

```dart
abstract class InspectorStorageSource { String get name; }
abstract class DatabaseBrowserSource implements InspectorStorageSource { ... }
abstract class KeyValueBrowserSource implements InspectorStorageSource { ... }
```

dropdown 改為 `DropdownButton<InspectorStorageSource>`，body 依型別分派。

| 面向 | 評估 |
|------|------|
| 消滅 `is` 判斷？ | **沒有**。dropdown 選出來之後，body 仍必須知道「這是 DB 還是 KV」才能決定渲染 `_DatabaseTabBody` 還是 KV 視圖。marker interface 只共享 `name`，不共享行為，`is` 判斷從 dropdown 移到 body，總量不變 |
| 破壞既有測試？ | **會**。`find.byType(DropdownButton<DatabaseBrowserSource>)` 三處失效，違反 AC-31 |
| 破壞既有 API？ | 會。`DatabaseBrowserSource` 多一個 supertype，屬公開 API 形狀變更 |
| YAGNI？ | 為兩個不共享行為的介面發明共同父型別，只為了共享一個 `String get name`——這是規格 U-5 自己警告的「為單一使用場景發明抽象」 |

**否決。** 它付出了破壞既有測試與公開 API 的代價，卻沒有換到「消滅型別判斷」這個唯一的好處。

###### 方案 B：兩個獨立的 selector，KV 走自己的區塊（選定）

**核心洞察：dropdown 的泛型型別問題之所以難解，是因為問題被問錯了。**
真正的需求不是「一個 dropdown 列出兩類 source」，而是「使用者能在 Database Tab 內
切換檢視 DB 與 KV」。後者不要求兩者共用同一個 `DropdownButton` 實例。

作法：`DatabaseTab` 的 `build` 最外層做**一次**分流，把畫面切成兩個互斥的子樹：

```dart
// database_tab.dart（示意，非最終程式碼）
@override
Widget build(BuildContext context) {
  final kvSources = widget.inspector.keyValueSources;
  if (kvSources.isEmpty) {
    return _buildExistingDatabaseView();   // 既有程式碼，逐字不動
  }
  return _StorageTabScaffold(
    inspector: widget.inspector,
    databaseView: _buildExistingDatabaseView(),
    kvSources: kvSources,
  );
}
```

`_StorageTabScaffold` 內以一個**分段切換器**（`SegmentedButton` 或簡單的兩段 `ToggleButtons`）
選擇「Database / Key-Value」，選 Database 就原封不動渲染既有子樹（含既有的
`DropdownButton<DatabaseBrowserSource>`），選 Key-Value 就渲染新的 KV 視圖
（含它自己的 `DropdownButton<KeyValueBrowserSource>`）。

| 面向 | 評估 |
|------|------|
| 消滅 `is` 判斷？ | **是**。兩個 dropdown 各自泛型明確，各自的 body 型別確定。全程零 `is KeyValueBrowserSource`。既有的 `is OperationLogSource`（L71）是**正當業務邏輯**（op-log 才有清空鈕），保留不動 |
| 破壞既有測試？ | **否**。未注入 KV source 時 `kvSources.isEmpty` 為真，走的是與現在**逐字相同**的子樹，`DropdownButton<DatabaseBrowserSource>` 仍在原位 → AC-30 / AC-31 自動滿足 |
| 破壞既有 API？ | 否。`DatabaseBrowserSource` 一個字不改 |
| 代價 | 多一層 widget 巢狀；注入 KV 時使用者多一次點擊才到 KV。**這是可接受的**——KV 與 DB 本來就是不同的操作模式（一個唯讀瀏覽、一個可寫入），視覺上分開反而更誠實 |

**選定方案 B。**

> **Linus 判準對照**：方案 A 是「增加一層抽象去容納特殊情況」，方案 B 是
> 「重新問問題，讓特殊情況消失」。分流點上移到最外層之後，
> 「兩種型別如何共存」這個問題**在下游根本不存在**——每個子樹只認識一種型別。
> 而且 `kvSources.isEmpty` 這個 early-return 同時就是 AC-30 的實作與證明。

###### 方案 C（記錄備查，未選）：KV 完全獨立成第五個 Tab

規格 §「為什麼歸入 Database Tab」已否決（bottom nav tab 數在臨界值）。此處不重開。


</details>

### 2.3 rev.2 的設計：條件性掛載

```dart
// dashboard_modal.dart（示意，非最終程式碼）
final hasCustomTab = inspector.customTab != null;
final hasStorageTab = inspector.keyValueSources.isNotEmpty;
final tabCount = 4 + (hasStorageTab ? 1 : 0) + (hasCustomTab ? 1 : 0);
```

`tabs:` 與 `TabBarView children:` 兩處各插入一個條件性項目，**位置在 Database 之後、
custom 之前**（規格 AC-32）。

**為什麼是條件性而非無條件**（三個理由，由弱到強）：

1. 與 `customTab` 的既有慣例一致（`dashboard_modal.dart:44` 就是 `hasCustomTab ? 5 : 4`）
2. 永遠空白的 tab 是噪音——沒注入 source 就沒東西可看
3. **硬性約束**：既有 5 處測試寫死 tab 數／index（見修訂紀錄的表）。
   這些測試都不注入 KV source，條件性顯示讓它們自動維持 4／5 個 tab。
   無條件新增會讓 5 條測試全紅，違反 AC-36。

**為什麼插在 Database 之後而非最前面**：既有四個 tab 的 index 0~3 是**公開契約**——
`flutter_inspector.dart:363-365` 的 doc comment 白紙黑字寫著
「Console (0), Network (1), Navigator (2), Database (3)」，
且 `_openNetworkFromNotification()` 硬編碼 `initialIndex: 1`。
插在前面會把所有既有 index 往後推一位，直接違反 AC-33，
也違反「Never break userspace」。**只能往尾端追加。**

> ⚠️ 實作注意：`tabs` 與 `children` 是兩份需手動保持同步的清單，這是該檔案既有的
> 結構性弱點（custom tab 已有同樣問題）。**不重構它**（YAGNI），但兩處必須一起改
> ——漏一處會讓 tab 標題與內容錯位，而且**不會有編譯錯誤**，只會在執行時錯位。
> T13 的測試必須驗證「切到 Storage tab 看到的是 KV 視圖」，而非只驗證標題存在。

### 2.4 U-1 定案（rev.2 改寫）：Database Tab **不更名**，KV 另開 Storage tab

rev.1 曾問「Database Tab 是否更名為 Storage Tab」。rev.2 的答案讓這題自然消解：
**兩者都不動名字**。既有 Database tab 保留 `'Database'` 標題（`dashboard_modal.dart:167`），
新 tab 標題為 `'Storage'`。零更名風險。

> 附帶好處：`export_report_sheet_test.dart:65` 與 `:316` 有比對 `'Database'`
> 字面文字的斷言（已實查）。不更名 → 這兩處不受影響。
> 這也**結案了 rev.1 §7 誠實標註的第 3 條未實查項**。

### 2.5 其餘未決事項定案

| 編號 | 定案 | 理由 |
|------|------|------|
| **U-2** | 寫入失敗**不**額外記 error log | 保持 AC-28 原文語意（「不產生成功語意的 log」）即可。失敗時 UI 已顯示錯誤（AC-17），再記一筆 log 是重複資訊。**YAGNI**，且改動會讓 AC-25~27 的「恰好一筆」測試斷言複雜化 |
| **U-3** | `redactSensitiveData` **不**波及 KV 顯示 | 已實查：該旗標僅出現在 `network_detail_view.dart`、`network_tab.dart`、`console_tab.dart:532`、`export_report_sheet.dart:86`、`diagnostic_report.dart` — **全部是 network / 匯出路徑**。KV 視圖不讀取此旗標，即符合規格「敏感值遮蔽 out of scope」。**無需任何程式碼變更**，僅需在 KV 視圖不引用該旗標 |
| **U-4** | 稽核 log **包含**舊值 | 規格已傾向包含。放在 `data` map 而非訊息字串，訊息長度不受影響 |

> U-2 / U-3 / U-4 的定案**不受 rev.2 歸屬翻案影響**——它們與 tab 掛在哪裡無關。

---

## 3. 檔案異動清單

### 3.1 新增

| 檔案 | 內容 |
|------|------|
| `lib/src/models/key_value_browser_source.dart` | `KeyValueBrowserSource` 介面、`KeyValueEntry`、`KeyValueType`、`parseKeyValueInput()` |
| `lib/src/ui/dashboard/tabs/storage_tab.dart` | KV 主視圖：source dropdown、搜尋欄、列表、三態、重新整理、清空鈕 |
| `lib/src/ui/dashboard/tabs/storage/key_value_edit_dialog.dart` | 編輯用 dialog（含 AC-18 驗證與二次確認） |
| `lib/src/ui/widgets/confirm_dialog.dart` | 全新的二次確認元件（F-1：專案內零 `showDialog` 前例） |
| `test/models/key_value_browser_source_test.dart` | AC-1、AC-2、`parseKeyValueInput` 邊界 |
| `test/ui/tabs/storage_tab_test.dart` | AC-7~AC-29 的 widget test |

> **檔案數控管**：`storage_tab.dart` 內的搜尋欄、列表項 widget 以私有 class 放同檔，
> 不再拆檔。理由：它們只有一個呼叫端，拆檔只增加 import 噪音。

### 3.2 修改

| 檔案 | 改什麼 | 不改什麼 |
|------|--------|---------|
| `lib/src/core/flutter_inspector.dart` | 加 `final List<KeyValueBrowserSource> _keyValueSources = []`（`:138` 鄰近）、`keyValueSources` getter 回傳 `List.unmodifiable`（`:191` 鄰近）、建構參數 `List<KeyValueBrowserSource>? keyValueSources`（`:214` 鄰近）、建構式內注入（`:234` 鄰近）、`registerKeyValueSource()`（`:264` 鄰近） | `databaseSources` getter 與 `registerDatabaseSource` 一字不動 |
| `lib/src/ui/dashboard/dashboard_modal.dart` | **（rev.2 取代原本的 `database_tab.dart` 條目）** 四處：`:44` tabCount 加入 `hasStorageTab`、`:158-168` tabs 清單插入條件性 `Tab(text: 'Storage')`、`:72-79` children 插入對應 `StorageTab`、頂部加 `import 'tabs/storage_tab.dart';` | `:47` `length:`、`:48` clamp、`:156` `isScrollable`（**已是 true**）、`_DashboardTabBar` 的 badge 邏輯、既有四個 Tab 的順序與標題文字全部不動 |
| `lib/src/core/flutter_inspector.dart`（doc comment） | `:363-365` `openDashboard` 的 doc comment 補上 Storage tab 說明 | `initialIndex` 的既有語意（0~3 對應 Console/Network/Navigator/Database）不動 |
| `lib/flutter_inspector_kit.dart` | 加一行 `export 'src/models/key_value_browser_source.dart';` | 既有 11 行 export 不動 |
| `README.md` | 加 `SharedPreferences` 與 `FlutterSecureStorage` 兩套接線範例 | — |

### 3.3 明確不改

- **`lib/src/ui/dashboard/tabs/database_tab.dart`（rev.2 新增此條，AC-35）**
  ——獨立 tab 後零接觸。`DropdownButton<DatabaseBrowserSource>`、
  `is OperationLogSource` 分岔、`_loadTables`、`_clearDatabase`、`_DatabaseTabBody`
  以及 `:63` `_clearDatabase()` 的無確認行為全數原封
- `lib/src/ui/widgets/key_value_table.dart`（R-1 方案 B）
- `lib/src/ui/dashboard/tabs/console_tab.dart`（R-2 方案 A）
- `lib/src/ui/dashboard/tabs/network_tab.dart`（R-2 方案 A）
- `lib/src/models/database_browser_source.dart`
- `pubspec.yaml` 的 `dependencies`（AC-3，逐字相同）
- 任何既有測試檔

---

## 4. 任務拆分

複雜度等級：**機械性** = 照既有模式抄／純資料類；**整合** = 接線既有元件；**需設計判斷** = 有取捨要當場決定。

每個任務都從測試開始（TDD-first）。

---

### T1 — `KeyValueEntry` / `KeyValueType` 資料類

- **複雜度**：機械性
- **寫入 scope**：`test/models/key_value_browser_source_test.dart`、`lib/src/models/key_value_browser_source.dart`
- **對應 AC**：AC-2
- **步驟**：
  1. 寫測試：`KeyValueEntry` 相同欄位時 `==` 為 true、`hashCode` 相等、不同欄位時不等、`toString()` 含 key 與 type
  2. 跑 `rtk flutter test test/models/key_value_browser_source_test.dart` 確認紅燈
  3. 實作 `KeyValueType` enum（5 個值）與 `@immutable class KeyValueEntry`，鏡射 `DatabaseTableInfo`（`database_browser_source.dart:20-43`）的 `==`/`hashCode`/`toString` 寫法
  4. 綠燈

---

### T2 — `parseKeyValueInput()` 型別驗證純函式

- **複雜度**：需設計判斷（邊界情況多）
- **寫入 scope**：`test/models/key_value_browser_source_test.dart`、`lib/src/models/key_value_browser_source.dart`
- **對應 AC**：AC-18（的邏輯核心）
- **相依**：T1（需要 `KeyValueType`）
- **步驟**：
  1. 寫測試表：
     - `string`：`''` → `''`（成功）、`'abc'` → `'abc'`
     - `int`：`'42'` → `42`、`'abc'` → `null`、`'4.2'` → `null`、`' 42 '` → 決定是否 trim（**建議 trim**，QA 手輸入常帶空白）
     - `double`：`'4.2'` → `4.2`、`'42'` → `42.0`、`'abc'` → `null`
     - `bool`：`'true'`/`'TRUE'` → `true`、`'false'` → `false`、`'1'` → `null`（不接受，避免歧義）
     - `stringList`：`'a\nb'` → `['a','b']`、`''` → `[]`
  2. 紅燈確認
  3. 以窮盡式 `switch` expression 實作（flutter-styles §5.4）
  4. 綠燈

---

### T3 — `KeyValueBrowserSource` 介面

- **複雜度**：機械性
- **寫入 scope**：`lib/src/models/key_value_browser_source.dart`、`test/models/key_value_browser_source_test.dart`
- **對應 AC**：AC-1、AC-3
- **相依**：T1
- **步驟**：
  1. 寫測試：定義一個測試用 fake 實作五個成員，斷言可被賦值給 `KeyValueBrowserSource` 型別（等同於編譯期契約檢查）
  2. 實作 abstract class，五個成員，鏡射 `DatabaseBrowserSource` 的 doc comment 風格
  3. 執行 `rtk proxy git diff --stat pubspec.yaml` 確認 `pubspec.yaml` 零變更（AC-3）

---

### T4 — 套件 export

- **複雜度**：機械性
- **寫入 scope**：`lib/flutter_inspector_kit.dart`
- **對應 AC**：AC-1（對外可見）
- **相依**：T3
- **步驟**：在既有 export 清單依字母序插入一行；跑 `rtk flutter analyze` 確認無錯

---

### T5 — `FlutterInspector` 註冊機制

- **複雜度**：機械性（四點全部鏡射既有 `databaseSources`）
- **寫入 scope**：`test/core/flutter_inspector_test.dart`、`lib/src/core/flutter_inspector.dart`
- **對應 AC**：AC-4、AC-5、AC-6
- **相依**：T3
- **步驟**：
  1. 在既有 `flutter_inspector_test.dart` **新增**（不改既有 test）三個 test：
     - 未傳入 → `keyValueSources` 為空清單（AC-4）
     - `registerKeyValueSource()` 後 getter 反映新增（AC-5）
     - `expect(() => inspector.keyValueSources.add(fake), throwsUnsupportedError)`（AC-6）
  2. 紅燈
  3. 實作四點（欄位、getter、建構參數、註冊方法），鏡射 `:138`/`:191`/`:214`/`:234`/`:264`
     - ⚠️ 注意：`databaseSources` getter 有 `_operationLogSource` 前置，
       `keyValueSources` **沒有**內建 source，直接 `List.unmodifiable(_keyValueSources)`
  4. 綠燈；跑全套 `test/core/` 確認既有測試未受影響

---

### T6 — `ConfirmDialog` 二次確認元件

- **複雜度**：需設計判斷（F-1：專案零前例，API 形狀要自己定）
- **寫入 scope**：`lib/src/ui/widgets/confirm_dialog.dart`、`test/ui/widgets/confirm_dialog_test.dart`（新目錄）
- **對應 AC**：AC-13/15/19/20/22/23 的共同基礎
- **相依**：無（可與 T1~T5 並行）
- **設計決定**：
  ```dart
  /// 回傳 true 代表使用者確認，false 或 null 代表取消。
  Future<bool> showInspectorConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool destructive = false,
  });
  ```
  - 回傳 `Future<bool>`（把 `showDialog` 的 `bool?` 在函式內收斂成 `bool`），
    呼叫端不必每處寫 `?? false` — **這就是消滅特殊情況**
  - `destructive` 只控制確認鈕顏色，不長出第二條邏輯路徑
  - **不做**：不加 `icon`、`customContent`、`onConfirm` callback 等未被要求的參數（YAGNI）
- **步驟**：
  1. 寫 widget test：點確認 → future 完成為 true；點取消 → false；點 barrier／返回 → false
  2. 紅燈
  3. 以 `showDialog<bool>` + `AlertDialog` 實作，`Navigator.pop(context, true/false)`
  4. 綠燈

---

### T7 — `StorageTab` 列表視圖（唯讀部分：dropdown + 三態 + 重新整理）

> **rev.2 變更**：此 widget 現在是 **tab 根 widget**（`class StorageTab extends StatefulWidget`，
> 建構式 `{required FlutterInspector inspector}`，與 `DatabaseTab` 同形），
> 而非 Database Tab 的子樹。**公開（非私有）** ——`dashboard_modal.dart` 要 import 它。
> 本任務只做 widget 本身，掛上 Dashboard 是 T13。

- **複雜度**：整合
- **寫入 scope**：`lib/src/ui/dashboard/tabs/storage_tab.dart`、`test/ui/tabs/storage_tab_test.dart`
- **對應 AC**：AC-7、AC-8、AC-9、AC-10
- **相依**：T3、T5
- **步驟**：
  1. 在測試檔建立 `FakeKeyValueSource`（可記錄呼叫、可設定拋例外），形狀鏡射
     `test/ui/tabs/database_tab_test.dart:9` 的 `FakeCustomSource`（R-6 已解決：既有 fake 可鏡射，不引入 mock 套件）
  2. 寫測試：列出三筆 entry 顯示 key/value/type；空清單顯示空狀態文案；`listAll()` 拋例外顯示
     `ErrorCard` 且點重試會再呼叫一次 `listAll()`（斷言 fake 的呼叫計數為 2）；點 refresh 呼叫計數 +1
  3. 紅燈
  4. 實作 `StatefulWidget`，狀態機**直接鏡射** `database_tab.dart:22-61` 的
     `_loading` / `_isFetching` / `_errorMessage` 三欄位模式與 `mounted` 檢查（AC-9 規格明示沿用既有形態）
  5. 綠燈

---

### T8 — KV 搜尋欄與過濾

- **複雜度**：機械性
- **寫入 scope**：`lib/src/ui/dashboard/tabs/storage_tab.dart`、`test/ui/tabs/storage_tab_test.dart`
- **對應 AC**：AC-11、AC-12
- **相依**：T7（同檔，必須序列）
- **步驟**：
  1. 寫測試：輸入 `token` 只留 key 或 value 含 token 的 entry；輸入 `TOKEN` 結果相同（AC-12）；清空還原
  2. 紅燈
  3. 在同檔新增私有 `_KvSearchBar`（StatefulWidget + `TextEditingController`，`dispose` 要 cancel）
     - 過濾為純函式：`entries.where((e) => e.key.toLowerCase().contains(q) || '${e.value}'.toLowerCase().contains(q))`
     - 加註記：`// ponytail: 專案內第三份搜尋欄實作，已知技術債，使用者拍板不抽共用元件`
  4. 綠燈

---

### T9 — 寫入：inline 編輯

- **複雜度**：需設計判斷
- **寫入 scope**：`lib/src/ui/dashboard/tabs/storage/key_value_edit_dialog.dart`、
  `lib/src/ui/dashboard/tabs/storage_tab.dart`、`test/ui/tabs/storage_tab_test.dart`
- **對應 AC**：AC-13、AC-14、AC-15、AC-16、AC-17、AC-18
- **相依**：T2、T6、T7
- **關鍵設計**：AC-13 要求「輸入新值後**先**顯示二次確認」→ 兩階段流程：
  1. 編輯 dialog（TextField 預填舊值）→ 使用者按「Next」
  2. `parseKeyValueInput()` 驗證，失敗則**留在編輯 dialog 顯示驗證錯誤，不進第二階段**（AC-18）
  3. 驗證成功 → `showInspectorConfirm()` 顯示 key、舊值 → 新值
  4. 確認才呼叫 `setValue()`
  - ⚠️ 跨 `await` 用 `BuildContext`：兩個 dialog 串接必經 await gap，
    **每個 await 後必須 `if (!mounted) return;`**（flutter-styles §7.5，這是既有 crash 來源）
- **步驟**：
  1. 寫測試：確認前 fake 的 `setValueCalls` 為空（AC-13）；確認後參數正確（AC-14）；
     取消時 `setValueCalls` 為空且列表原值仍在（AC-15）；成功後列表顯示新值（AC-16）；
     `setValue` 拋例外時錯誤可見且無 `CircularProgressIndicator`（AC-17）；
     對 int entry 輸入 `abc` 顯示驗證錯誤且 `setValueCalls` 為空（AC-18）
  2. 紅燈 → 實作 → 綠燈

---

### T10 — 寫入：刪除

- **複雜度**：整合
- **寫入 scope**：`lib/src/ui/dashboard/tabs/storage_tab.dart`、`test/ui/tabs/storage_tab_test.dart`
- **對應 AC**：AC-19、AC-20、AC-21
- **相依**：T6、T7
- **步驟**：
  1. 寫測試：確認前 `removeCalls` 空；確認後以正確 key 呼叫；取消時不呼叫且 entry 仍在；成功後 entry 消失
  2. 紅燈 → 實作（`showInspectorConfirm` + `destructive: true`，訊息含 key 與將被刪除的值）→ 綠燈

---

### T11 — 寫入：清空

- **複雜度**：整合
- **寫入 scope**：`lib/src/ui/dashboard/tabs/storage_tab.dart`、`test/ui/tabs/storage_tab_test.dart`
- **對應 AC**：AC-22、AC-23、AC-24
- **相依**：T6、T7
- **步驟**：
  1. 寫測試：確認 dialog 內文**同時含 source 名稱與筆數字串**（AC-22 的強化確認，需精確比對文字）；
     取消不呼叫 `clear()`；確認後呼叫且列表變空狀態
  2. 紅燈 → 實作 → 綠燈

> T10 與 T11 寫入同一檔案，**必須序列**（或由同一個 agent 連續完成）。

---

### T12 — 稽核 log 接線

- **複雜度**：整合
- **寫入 scope**：`lib/src/ui/dashboard/tabs/storage_tab.dart`、`test/ui/tabs/storage_tab_test.dart`
- **對應 AC**：AC-25、AC-26、AC-27、AC-28、AC-29
- **相依**：T9、T10、T11
- **設計**：三處成功路徑各加一次 `inspector.log(...)`，用已驗證簽名（`flutter_inspector.dart:281`）：
  - 訊息示意：`'[KV] set "auth_token" on SharedPreferences'`
  - `data:` `{'source': ..., 'key': ..., 'newValue': ..., 'oldValue': ...}`（U-4 定案：含舊值，放 data 不放訊息）
  - **log 呼叫必須在 `await source.setValue()` 之後、且不在 try 的 catch 路徑**——
    這是 AC-28（失敗不留假痕跡）的實作保證
- **步驟**：
  1. 寫測試：每種操作成功後 `inspector.logEntries.where(...)` 恰好一筆且 `level == LogLevel.info`；
     操作拋例外後**零筆**成功語意 log（AC-28）；取消後 `logEntries` 完全不變（AC-29）
  2. 紅燈 → 實作 → 綠燈

---

### T13 — Dashboard 新增 Storage Tab 接線（rev.2 全面改寫）

> **rev.2 前身**：此任務原為「Database Tab 分流接線」，動 `database_tab.dart`。
> 歸屬翻案後改為動 `dashboard_modal.dart`，`database_tab.dart` 一個字不碰。

- **複雜度**：整合（**破壞性風險仍是全計畫最高，但性質換了**——見下方）
- **寫入 scope**：`lib/src/ui/dashboard/dashboard_modal.dart`、
  `lib/src/core/flutter_inspector.dart`（僅 doc comment）、
  `test/ui/dashboard_modal_test.dart`（**只新增 test，不改既有 4 個**）
- **對應 AC**：AC-30、AC-31、AC-32、AC-33、AC-34、AC-36
- **相依**：T5（需 `keyValueSources` getter）、T7（需 `StorageTab` widget）。
  實務上建議放在 T12 之後，讓 Storage tab 內容已完整再掛上去
- **步驟**：
  1. **先跑既有測試存基準**：
     `rtk flutter test test/ui/dashboard_modal_test.dart test/ui/dashboard_error_badge_test.dart`
     ——記下全綠（這是 5 處寫死斷言的所在，見修訂紀錄）
  2. 在 `dashboard_modal_test.dart` **新增**（不動既有 4 個 test）：
     - 未注入 `keyValueSources` → `find.byType(Tab)` 仍 `findsNWidgets(4)`
       且 `find.text('Storage')` 為 `findsNothing`（AC-30）
     - 注入一個 fake KV source → `findsNWidgets(5)`、`find.text('Storage')`
       `findsOneWidget`（AC-31）
     - 注入 KV source + customTab → `findsNWidgets(6)`，且 tab 標題順序為
       Console/Network/Navigator/Database/Storage/Custom（AC-32）
     - 注入 KV source 時 `initialIndex: 1` 仍落在 Network（AC-33）
     - 注入 KV source 時 `initialIndex: 99` clamp 到 `4`（AC-34；
       **這條會抓到「只改了 tabs 卻漏改 tabCount」的錯誤**）
     - 🔴 **內容錯位守門測試**：切到 Storage tab 後
       `expect(find.byType(StorageTab), findsOneWidget)`
       ——只驗標題文字**不夠**，`tabs` 與 `children` 兩份清單順序不同步時
       標題會正確而內容錯位，且**沒有編譯錯誤**（見 §2.3 的警告）
  3. 紅燈確認
  4. 改 `dashboard_modal.dart` 四處（§3.2 表），加 `import 'tabs/storage_tab.dart';`
     - `hasStorageTab = inspector.keyValueSources.isNotEmpty`
     - `tabCount = 4 + (hasStorageTab ? 1 : 0) + (hasCustomTab ? 1 : 0)`
     - `tabs:` 與 `children:` **同時**插入條件性項目，位置一致
     - **不趁機重構** `_DashboardTabBar` 或 badge 邏輯
  5. 更新 `flutter_inspector.dart:363-365` 的 doc comment
  6. 跑 `rtk flutter test test/ui/` — **既有 5 處斷言必須零修改全綠**（AC-36）。
     任一條紅代表條件性判斷寫錯，**回退重做，不得修改既有測試**

---
### T14 — README 接線範例

- **複雜度**：機械性
- **寫入 scope**：`README.md`
- **對應 AC**：US-9（無直接 AC，屬 in-scope 交付項）
- **相依**：T3、T5
- **步驟**：仿既有 `DatabaseBrowserSource` 範例段落格式，寫 `SharedPreferences` 與
  `FlutterSecureStorage` 兩套實作範例
  - ⚠️ 需實查驗證：`flutter_secure_storage` 的 `readAll()` 平台支援矩陣（規格 R-5 誠實標註未查）。
    撰寫時應查官方文件；若某平台不支援，範例中以 try-catch 拋出、由 AC-9 錯誤處理承接

---

### T15 — 全套回歸

- **複雜度**：機械性
- **寫入 scope**：無（唯讀驗證）
- **對應 AC**：AC-3、AC-35、AC-36、AC-37、AC-38
- **相依**：全部
- **步驟**：
  1. `rtk flutter analyze`
  2. `rtk flutter test`（⚠️ MEMORY 提醒：`magical_tap_test` 有 10 分鐘既有 timeout，需預留時間）
  3. `rtk proxy git diff --stat` 確認零變更：`pubspec.yaml`、
     **`database_tab.dart`（rev.2 新增此項，AC-35）**、`key_value_table.dart`、
     `console_tab.dart`、`network_tab.dart`、所有既有 test 檔
  4. **（rev.2 新增）** 確認 `dashboard_modal.dart` 的 diff 只含四處預期改動
     （tabCount / tabs / children / import），未夾帶 badge 邏輯或 `isScrollable` 的變更

---

## 5. 相依順序與並行機會

```
T1 (資料類)
 ├─→ T2 (parse 函式) ──┐
 └─→ T3 (介面) ─┬→ T4 (export)
                └→ T5 (註冊) ─┐
                              │
T6 (ConfirmDialog) ───────────┤   ← 可從一開始就與 T1~T5 並行（零相依）
                              │
                    T7 (StorageTab 唯讀) ─→ T8 (搜尋)
                              │
                              ├─→ T9  (編輯)
                              ├─→ T10 (刪除)
                              └─→ T11 (清空)
                                    └─→ T12 (log 接線)
                                          └─→ T13 (Dashboard 掛 Storage tab)
                                                └─→ T14 (README) ─→ T15 (回歸)
```

> **rev.2**：相依圖形狀不變，只有 T13 換了目標檔案
> （`database_tab.dart` → `dashboard_modal.dart`）。任務數仍為 15。

### 可並行

| 並行組 | 任務 | 理由 |
|--------|------|------|
| P1 | **T6** ∥ **T1→T2→T3→T4→T5** | 寫入 scope 完全不重疊（`confirm_dialog.dart` vs `models/` + `core/`） |
| P2 | **T14 (README)** ∥ **T9~T13** | README 只需 T3/T5 的介面定案，與 UI 實作無檔案交集 |

### 必須序列

- **T7 → T8 → T9 → T10 → T11 → T12**：全部寫入 `storage_tab.dart` 同一檔，並行必衝突
- **T13 最後接線**：它動既有檔案（`dashboard_modal.dart`），前面全綠才動，出問題時歸因單純。
  且 T13 需要 T7 產出的 `StorageTab` 型別才能寫 import 與內容錯位守門測試
- **T2 → T9**：AC-18 依賴 parse 函式
- **T6 → T9/T10/T11**：三個寫入操作都用 ConfirmDialog

---

## 6. 測試策略：38 條 AC 的對應（rev.2 重排）

| 測試檔 | 涵蓋 AC | 型態 |
|--------|---------|------|
| `test/models/key_value_browser_source_test.dart` | AC-1、AC-2、AC-18（parse 邏輯） | unit |
| `test/core/flutter_inspector_test.dart`（**新增 test，不改既有**） | AC-4、AC-5、AC-6 | unit |
| `test/ui/widgets/confirm_dialog_test.dart` | 二次確認元件本身 | widget |
| `test/ui/tabs/storage_tab_test.dart` | AC-7~AC-17、AC-19~AC-29 | widget |
| `test/ui/dashboard_modal_test.dart`（**新增 test，既有 4 個零修改**） | AC-30、AC-31、AC-32、AC-33、AC-34 | widget |
| `test/ui/dashboard_error_badge_test.dart`（**零修改，只驗證仍全綠**） | AC-36（`:40`、`:97` 兩處 tab 數斷言） | widget |
| `test/ui/tabs/database_tab_test.dart`（**零修改，只驗證仍全綠**） | AC-35、AC-38 | widget |
| `test/ui/tabs/network_detail_view_test.dart` / `log_detail_view_test.dart`（**零修改**） | AC-37 | widget |
| `rtk proxy git diff --stat` | AC-3、AC-35 | 檢查 |

> **rev.2 的 AC 重新分派**：原本 AC-30/AC-33 由 `key_value_view_test.dart` 涵蓋
> （因為 KV 視圖是 Database Tab 子樹）。獨立 tab 後，掛載相關的 AC-30~34 全部移到
> `dashboard_modal_test.dart`，`storage_tab_test.dart` 只管 Storage tab 內部行為。
> **職責邊界比 rev.1 更乾淨**——這是歸屬改變的附帶收益。

### 測試用 fake（R-6 定案）

`FakeKeyValueSource` 手寫，放在 `storage_tab_test.dart` 檔內。需具備：

- 可預設 `entries` 回傳值
- 記錄 `setValueCalls: List<(String, Object?)>`、`removeCalls: List<String>`、`clearCallCount: int`
- 可設定「下次呼叫拋例外」以測 AC-9 / AC-17

**不引入 mockito / mocktail**（介面只有五個成員，手寫成本低於加相依）。

> ⚠️ **rev.2 注意**：T13 的 `dashboard_modal_test.dart` 也需要一個 KV source 實例
> 來觸發 Storage tab 顯示。**不要把 `FakeKeyValueSource` 抽到 `test/mock/`**——
> T13 只需要「一個能被注入的最小實作」，在 `dashboard_modal_test.dart` 內
> 就地寫一個 5 行的 stub（`listAll()` 回空清單即可）比共用一個功能完整的 fake 更省。
> 兩個檔案各自持有自己的假實作，這在測試碼中是**正確的重複**。

### 測試資料

依 flutter-styles §8.2，共用測資放測試檔內的 `_Data` 私有類。

---

## 7. 風險與回退

### 7.0 rev.2 的最大風險重評

**原本的最高風險（T13 破壞 `database_tab.dart` 既有測試）已經消失**
——因為 `database_tab.dart` 現在一個字都不用改。

**但風險沒有整體下降，只是換了位置，而且新位置的接觸面更廣：**

| | rev.1（併入 Database Tab） | rev.2（獨立 Storage Tab） |
|---|---|---|
| 動的檔案 | `database_tab.dart`（1 個 tab 的內部） | `dashboard_modal.dart`（**所有 tab 的容器**） |
| 改法 | build 方法加 early-return | 三處清單需**手動保持同步**（tabCount / tabs / children） |
| 受威脅的既有斷言 | `database_tab_test.dart` 3 處（dropdown 泛型） | **`dashboard_modal_test.dart` 3 處 + `dashboard_error_badge_test.dart` 2 處 = 5 處** |
| 失敗模式 | 編譯錯誤或測試紅——**吵鬧、好抓** | 三處清單漏改一處 → **可能編譯通過、測試部分綠、UI 靜默錯位** |

**新的最大風險是「靜默錯位」**：`tabs:` 與 `TabBarView children:` 是兩份獨立清單，
順序靠人工對齊。若只在 `tabs` 插入 Storage 而漏了 `children`（或反之），
Dart **不會報錯**——`TabController` 的 length 由 `tabCount` 決定，
標題與內容的對應純靠位置。結果是使用者點 Storage 看到 Custom 的內容。

這就是為什麼 T13 步驟 2 明列了**內容錯位守門測試**
（`expect(find.byType(StorageTab), findsOneWidget)` 而非只驗標題文字）。
只驗標題的測試會漏掉這整類錯誤。

| 風險 | 嚴重度 | 徵兆 | 回退方案 |
|------|--------|------|---------|
| **T13 的 tabs／children 清單不同步導致靜默錯位** | **高（rev.2 新列為第一）** | 切到 Storage tab 顯示別的內容；或 `initialIndex` clamp 上界不對 | 內容錯位守門測試 + clamp 測試是主要防線。回退＝`git checkout lib/src/ui/dashboard/dashboard_modal.dart`，`StorageTab` 本身仍完整可測 |
| **T13 弄紅既有 5 處 tab 數／index 斷言** | 中（rev.2 由高降級） | `dashboard_modal_test.dart` `:17`/`:56`/`:70` 或 `dashboard_error_badge_test.dart` `:40`/`:97` 轉紅 | 徵兆極明確：代表 `hasStorageTab` 條件判斷寫錯（很可能寫成無條件新增）。回退同上。**絕不修改既有測試來讓它變綠** |
| ~~T13 分流改動破壞 `database_tab_test.dart`~~ | ~~高~~ → **已消除** | — | rev.2：`database_tab.dart` 零改動，此風險不存在 |
| 兩段 dialog 串接的 `BuildContext` async gap crash | 中 | widget test 出現 `Looking up a deactivated widget's ancestor` | 每個 `await` 後強制 `if (!mounted) return;`；或 await 前先取出 `Navigator`/`ScaffoldMessenger` |
| ~~`SegmentedButton` 的 Material 3 相容性~~ | ~~低~~ → **已消除** | — | rev.2：獨立 tab 後不需要 Database／Key-Value 分段切換器，`SegmentedButton` 完全不使用 |
| `stringList` 編輯的多行輸入 UX 不佳 | 低 | — | 換行分隔已是最簡方案。若不可用，退回「該型別暫不支援編輯，顯示唯讀」——但這會違反 AC-18 精神，需回頭與使用者確認 |
| README 的 SecureStorage 範例平台差異寫錯 | 低 | — | T14 撰寫時實查官方文件；不確定就在範例註明「依平台而異」 |

### 7.2 誠實標註：本計畫未實查、需實作時驗證的假設

1. ~~`SegmentedButton` 的可用性~~ — **rev.2 已無關**（不再使用該 widget）
2. `flutter_secure_storage` 各平台 `readAll()` 支援矩陣（規格 R-5 已標註，**仍未查**，T14 需處理）
3. ~~`dashboard_modal_test.dart` 是否比對 "Database" 字面文字~~ — **rev.2 已實查結案**：
   `dashboard_modal_test.dart` 只比對 `'Console'`(`:18`) 與 `'MyTab'`(`:71`)，未比對 `'Database'`；
   比對 `'Database'` 的是 `export_report_sheet_test.dart:65` 與 `:316`，
   且那指的是**匯出報告的資料來源名稱**，與 tab 標題無關。不更名 → 全部不受影響
4. `test/ui/widgets/` 目錄目前不存在，T6 會新建（已由 `ls test/ui` 確認）
5. **（rev.2 新增，未實查）** `Tab(text: 'Storage')` 加入後，
   `isScrollable: true` + `tabAlignment: TabAlignment.start` 的 TabBar 在最窄的
   測試視窗（`tester` 預設 800x600）下是否會觸發 overflow warning。
   既有 5 tab（custom）情境未見此問題，6 tab 應仍安全，但 T13 執行時需留意 test 輸出

### 7.3 rev.2 未重新評估的部分

T1~T12、T14、T15 的風險與 rev.1 相同——它們都不觸碰 tab 掛載，
歸屬翻案對其零影響。唯一的形式變更是 T7 產出的 widget 從私有子樹變成公開 tab 根 widget，
這不改變其內部實作難度。

---

## 8. 執行方式選項

| 方式 | 適用 | 說明 |
|------|------|------|
| **A. Subagent-driven（建議）** | 預設 | 依 §5 相依圖逐任務委派。P1（T6 ∥ T1~T5）開兩條並行；其餘序列。**T13 必須由單一 agent 完整執行並自行驗證既有測試全綠**，不可拆給多個 agent |
| **B. Parallel session** | 趕時間 | Session 1：T1~T5 + T14（models / core / README）；Session 2：T6（confirm dialog）。兩 session 寫入 scope 零重疊。**T7 之後全部合回單一 session**，因為 `storage_tab.dart` 是單一檔案熱點 |
| **C. 單 session 順序執行** | 最保守 | 依 T1→T15 全序列。總時數最長但歸因最單純，若 T13 風險令人不安可選此 |

**建議 A。** T7~T12 六個任務全部寫同一檔，並行收益本來就有限；真正能並行的只有
T6 與 T14 兩處，用 subagent 委派即可，不值得開多 session 承擔合併衝突風險。

---

## 9. 完成定義（Definition of Done）

- [ ] **38 條** AC 全部有對應的自動化測試且通過
- [ ] `rtk flutter analyze` 零 issue
- [ ] `rtk flutter test` 全綠（⚠️ `magical_tap_test` 有 10 分鐘既有 timeout）
- [ ] `git diff` 證明 `pubspec.yaml`、**`database_tab.dart`**、`key_value_table.dart`、
      `console_tab.dart`、`network_tab.dart`、所有既有測試檔**逐字未變更**
- [ ] 手動確認：未注入 KV source 時 Dashboard 仍是 4 個 tab；注入後 Storage tab
      出現在 Database 之後，且點進去看到的是 KV 視圖（非其他 tab 的內容）
- [ ] README 有兩套可複製的接線範例
