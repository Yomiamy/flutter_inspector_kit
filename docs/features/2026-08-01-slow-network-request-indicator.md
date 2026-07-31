# 網路請求耗時慢查詢標記 (Slow Network Request Indicator)

## What & Why
在開發與測試階段，開發者需要快速識別出效能瓶頸。當前的 Inspector 提供了完整的網路請求日誌，但若要找出耗時過長的請求（例如超過 2 秒），開發者需要手動逐一檢查每個請求的耗時（duration），缺乏直覺的視覺提示。
本功能旨在提供一個「慢查詢視覺標記」，針對耗時達到或超過特定閾值的網路請求，在列表與摘要中加入醒目的圖示與文字（如 `🐢 SLOW`），以協助開發者一眼定位出潛在的效能問題。

## 使用者故事 (User Stories)
- 身為一位前端開發者，我希望在查看網路請求列表 (Network Tab) 時，能直覺看到耗時超過 2 秒的請求標有明顯的 `🐢 SLOW` 標籤，這樣我就不需要手動比較每個請求的耗時。
- 身為一位前端開發者，我希望在 Console Tab 的整合日誌中，也能看到相同的慢查詢標記，讓我能在追蹤事件流程時，同時掌握 API 的效能狀況。
- 身為一位測試工程師，我希望在 Network Tab 的摘要橫幅 (Error Summary Banner) 中，能夠一併看到當前列表中有「多少個」慢查詢，以便快速評估當前畫面的整體網路效能。

## 驗收條件 (Acceptance Criteria)
1. **閾值定義**: 在 utils 中定義慢查詢閾值 `kSlowRequestThreshold`，預設為 2 秒 (`Duration(seconds: 2)`)。
2. **Network Tab 列表標記**: 在 Network Tab (`network_tab.dart`) 的請求列表中，若請求 `duration != null` 且 `>= kSlowRequestThreshold`，其列表項目的右側 (trailing) 需顯示醒目的橘色標籤 (`🐢 SLOW`)。
3. **Console Tab 列表標記**: 在 Console Tab (`console_tab.dart`) 包含網路請求的列表項目中，同樣的慢查詢需在右側 (trailing) 顯示相同的橘色標籤。
4. **錯誤與效能摘要**: 在 Network Tab 的 Error Summary Banner 中，若目前篩選的列表中存在慢查詢，需在錯誤摘要後方附加慢查詢的總數統計（例如 `| 🐢 X slow`）。

## 範圍邊界 (Scope & Boundaries)
- **Included (包含)**:
  - 針對已完成 (completed) 的網路請求顯示視覺標籤。
  - 在 Network 與 Console 兩個 Tab 的列表項增加 UI 標記。
  - 增添 Summary Banner 上的計數統計。
- **Excluded (排除)**:
  - 提供 UI 讓開發者動態調整 `kSlowRequestThreshold` 的設定介面（目前固定寫在程式碼中為 2 秒）。
  - 將慢查詢獨立成為新的過濾 Chip（目前僅作為視覺提示與計數，除非未來有強烈需求，暫時不增加過濾負擔）。
