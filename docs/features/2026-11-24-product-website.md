# 產品介紹網站（flutter_inspector_kit）

> 狀態：設計待確認　｜　日期：2026-11-24

## 1. 目的

替 `flutter_inspector_kit` 建一個對外的產品介紹頁。風格參照 <https://syrtis.nyanako.com/>：單頁、敘事式、每段一個主題，最後是安裝。目前對外只有 pub.dev 頁面和 84 KB 的 README，Flutter 開發者沒辦法在一分鐘內看懂這個套件跟別的 debug overlay 差在哪裡。

**本套件的主軸**：排查靠「鏈推斷」（看事件怎麼演變），不是「點查詢」。log / network / navigator / database 攤平成一條時間軸。網站的敘事順著這條主軸走。

## 2. 目標、非目標、反目標

**目標**
- 單頁中英雙語（`/` 英文、`/zh-tw/` 繁中），內容取自 README / README.zh-TW 並重新精簡。
- 用 `doc/screenshots/` 現有的 12 張截圖呈現功能。
- 部署到 Firebase 專案 `flutterinspectorkit` 的 Hosting，網址 `https://flutterinspectorkit.web.app`。
- 有 GitHub Actions CI：PR 時 build 與驗證，push 到 `main` 時部署。

**非目標（第一版不做）**
- 現場試玩（Flutter Web 版 example）：留到第二版。要先確認 example 能 `flutter build web`，因為 ObjectBox 等 native plugin 可能不支援 Web。
- 自訂網域、Analytics、部落格或多頁文件站。
- 把完整 API 文件搬上網站：API 細節仍以 README 和 pub.dev 為準，網站只連過去。

**反目標（做出來也算失敗）**
- 網站原始碼被 `flutter pub publish` 打包進套件。
- 新增第 5 處需要手動同步的版本號（CLAUDE.md §4 已有 4 處）。
- 為了網站開 Blaze 方案或產生任何帳單。

## 3. 已確認的限制（2026-11-24 實查）

| 項目 | 現況 | 影響 |
|---|---|---|
| Firebase 方案 | `flutterinspectorkit` 為 Spark（`billingEnabled: false`） | App Hosting 不可用（CLI 回報必須 Blaze）；Firebase Hosting 可用 |
| Hosting 網站 | 預設站 `flutterinspectorkit` 已存在，`https://flutterinspectorkit.web.app` | 不需另建站 |
| Firebase Apps | 無 | 靜態站不需要註冊 Web App |
| 本機 CLI active project | `flutterpractice-32f76`（不是本專案） | 本機手動部署一律帶 `--project flutterinspectorkit`，或靠 `website/.firebaserc` |
| `.pubignore` | 已存在，排除 `docs/`、`.claude/`、`scripts/` 等 | 須加 `website/` 和 `.github/` |
| CI | repo 無 `.github/` | 本次新增第一支 workflow |
| 截圖 | `doc/screenshots/` 12 張 PNG | 足夠第一版使用 |

## 4. 做法比較

| 做法 | 優點 | 缺點 | 結論 |
|---|---|---|---|
| **A. Astro 靜態站（照搬 `Finding-Restaurant-Flutter/website`）** | 兩個 repo 同一套工具和 CI；雙語只要兩個入口頁共用一個元件；輸出純靜態 | 多一個 Node 工具鏈 | ✅ 採用 |
| B. 純 HTML/CSS | 無 build | 雙語內容要維護兩份；無法沿用 CI 與驗證測試 | ❌ |
| C. 整站用 Flutter Web | 同一語言 | 首次載入重，SEO 幾乎讀不到內容 | ❌ |
| （部署）App Hosting | — | 必須 Blaze；官方定位是 SSR 動態站，靜態站建議用 Hosting | ❌ 改用 Firebase Hosting |

使用者已確認：採 A + Firebase Hosting，第一版只用截圖。

## 5. 設計

### 5.1 目錄結構（照搬參考 repo）

```
website/
  astro.config.mjs        # site: https://flutterinspectorkit.web.app, output: 'static'
  package.json            # astro；devDependency sharp
  package-lock.json
  firebase.json           # public: dist；安全 header + 快取規則（同參考 repo）
  .firebaserc             # default: flutterinspectorkit
  .gitignore              # node_modules/ dist/ .astro/ .firebase/
  scripts/prepare-assets.mjs   # doc/screenshots/*.png → public/screenshots/*.webp（手機外框、大小上限）
  public/                 # favicon、og-card、screenshots/（產物 commit 進 repo）
  src/
    data/site.ts          # 雙語文案、截圖清單、連結
    components/LandingPage.astro
    layouts/BaseLayout.astro
    styles/global.css
    pages/index.astro     # en
    pages/zh-tw/index.astro
  test/                   # node --test：site-data 與 dist 驗證
.github/workflows/website.yml
```

`prepare-assets` 在本機手動跑，產出的 WebP commit 進 repo，所以 CI 不需要跑 sharp。這點和參考 repo 相同。

### 5.2 頁面段落（由上而下）

每段一個主題標題，加一句說明和 1～3 張截圖。文案中英各一份，放在 `site.ts`。

| # | 段落 | 內容 | 截圖 |
|---|---|---|---|
| 0 | Hero | 一句主軸標語（例：「Debug by following the chain, not by poking points.」）、一段副標、CTA：pub.dev、GitHub；一行 `flutter pub add flutter_inspector_kit` | home |
| 1 | 一條時間軸 | Merged Timeline：四種來源依時間交錯、來源篩選、書籤、錯誤列淡紅底 | console |
| 2 | 請求的演變 | Network：pending → completed 即時更新、Replay、慢請求標記、錯誤分類彙總、cURL 分享 | network、network_detail |
| 3 | 頁面與資料 | Navigator 堆疊、Database 操作與表格瀏覽、Key-value Storage | navigator、database_browse、shared_preference |
| 4 | 看得見的版面 | Tap-to-Inspect、放大鏡、間距尺 | layout_inspect_loupe、layout_inspect_ruler |
| 5 | 交給別人接手 | 診斷報告匯出、Agent Handoff Prompt、未捕獲錯誤 | diagnotic_report、info_sharing、uncaught_error |
| 6 | 輕量的承諾 | 不依賴任何狀態管理套件、opt-in 功能預設關閉、敏感資料預設遮罩（仿 Syrtis「Contained on your machine」段） | — |
| 7 | 安裝 | `pubspec.yaml` 一行加上最小初始化程式碼；連 README 完整用法 | — |
| — | Footer | MIT、GitHub、pub.dev、Issue tracker、語言切換 | — |

右上角 nav：GitHub 連結和 EN / 中文切換，同 Syrtis。

### 5.3 版本號

網站不寫死版本號。要顯示的話，build 時從 repo 根的 `pubspec.yaml` 讀 `version:`，或直接改用 pub.dev 的 badge。不增加 CLAUDE.md §4 版本同步清單的項目。

### 5.4 CI（`.github/workflows/website.yml`，照搬參考 repo）

- 觸發：`pull_request` 與 `push` 到 `main`，`paths` 限定 `website/**`、`.github/workflows/website.yml`。
- job：checkout → setup-node（版本與 cache 同參考 repo）→ `npm ci` → `npm run build` → `npm test`。
- 部署：只在 `push` 到 `main` 時執行，用 secret `FIREBASE_SERVICE_ACCOUNT_JSON`，跑 `npx --yes firebase-tools@15.28.2 deploy --only hosting --project flutterinspectorkit --non-interactive`。
- secret 未設定時跳過部署，並在 `GITHUB_STEP_SUMMARY` 寫出設定步驟，CI 不失敗。
- `permissions: contents: read`；`concurrency` 在 PR 上取消舊的 run。

### 5.5 `.pubignore`

新增 `website/` 與 `.github/`，以 `dart pub publish --dry-run` 確認兩者都不在打包清單。

### 5.6 驗證（`npm test`）

沿用參考 repo 的兩支測試，改成本專案內容：
- `site-data.test.mjs`：雙語文案的 key 一致、截圖清單裡每一張都存在於 `public/screenshots/`、外部連結都是 https。
- `verify-dist.test.mjs`：`dist/index.html` 與 `dist/zh-tw/index.html` 存在；每頁 `lang` 屬性正確；引用的截圖都有輸出；單張 WebP ≤ 150 KB、總計 ≤ 600 KB（沿用參考 repo 的上限）。

## 6. 使用者要做的事

1. 在 GCP 為 `flutterinspectorkit` 建立 service account，授予 **Firebase Hosting Admin**（`roles/firebasehosting.admin`）。參考 repo 另外授予了 **API Keys Viewer**（`roles/serviceusage.apiKeysViewer`），建議照做。
2. 把 JSON 金鑰存成 GitHub repo secret `FIREBASE_SERVICE_ACCOUNT_JSON`。
3. 在此之前 CI 只會 build 和驗證，不會部署；本機可手動 `cd website && npx firebase-tools deploy --only hosting --project flutterinspectorkit`。

## 7. 交給實作者決定

- 視覺風格：配色、字型、深淺色。原則是做一份給 Flutter 開發者看的、乾淨的技術產品頁，不照抄 Syrtis 的配色或字型。
- 各段的最終文案措辭，以及英文標語的最終版本。
- og-card 與 favicon：可由 `example/web/favicon.png` 或新製作。
- 截圖外框樣式與尺寸。
