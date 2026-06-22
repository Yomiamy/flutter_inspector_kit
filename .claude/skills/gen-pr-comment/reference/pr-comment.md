**\[修正問題\]**

`UpdateCartUC` 原本僅依賴 `cartExceptionType`（`limit_by` 欄位）判斷庫存狀態，但 v2 在庫存狀態判別上並不是用 `limit_by`，而是透過App計算 `response_quantity <= 0` 或 `response_quantity < request_quantity` 來表達庫存狀態的彈窗提示。

**\[修正方式\]**

在原有UpdateCartUC的 `cartExceptionType` 判斷前後，新增三道數量驗證：

1. **主商品無庫存**：`response_quantity <= 0` → 回傳 `CartExceptionType.outOfStock`
2. **主商品庫存不足（仍有部分）**：`request_quantity > response_quantity` → 回傳 `CartExceptionType.orderLimit`
3. **加購品數量不符**：原本用 `cartExceptionType != null` 篩選，改為比較 `requestQuantity != responseQuantity` → 回傳 `CartExceptionType.crossSellItemLimit`

判斷順序：`outOfStock` → `cartExceptionType` → `orderLimit` → `crossSellItemLimit`