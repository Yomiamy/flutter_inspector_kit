# 產品介紹網站（flutter_inspector_kit）— 實作計畫

> **規格**：[`docs/features/2026-11-24-product-website.md`](../features/2026-11-24-product-website.md)
> **日期**：2026-11-24 ｜ **模式**：Sequence ｜ **預估 Effort**：中（主體是雙語文案 + 一支素材腳本 + 兩支 `node --test`；其餘為照搬設定）
> **參考實作（唯讀）**：`/Users/yomiry/StudioWorkspace/Finding-Restaurant-Flutter`（`website/`、`.github/workflows/website.yml`）
> **不涉及 Dart 程式碼**：`lib/`、`test/`、`pubspec.yaml` 零改動。Flutter 側只需在最後確認 `flutter analyze lib/ test/` 維持 7 個既有 info。
> **修訂 1（0b 初審 REVISE）**：安裝段補上 Android core library desugaring 的必要設定，並修正與 README 衝突的文案（B1、M1）；照搬的設定檔改為全文寫進計畫，implementer 不必讀取 worktree 以外的檔案（B2）；原 T5 併入 T2，T1 由主進程先 commit，整個流程改為序列執行，`total_tasks=4`（M2）；目視檢查移到 §7 由主對話執行（M3）；範圍驗收改用 `$BASE` 比對（M4）；刪除重複的預算檢查與防禦分支（L1、L2）；CLAUDE.md §3 的 CI 敘述同步修正（L4）；部署後檢查（L5）。逐條修改紀錄見文末 §11。

---

## 1. 核心判斷

【核心判斷】✅ 值得做：規格已確認方向（Astro 靜態站 + Firebase Hosting + 只用截圖）。參考 repo 已有一套能 build、能測、能部署的實作，照搬工具鏈與 CI，只換內容。

【關鍵洞察】
- **資料結構**：整站只有一份資料來源 `website/src/data/site.ts`。`SCREENSHOTS`（shot id → 原始 PNG 檔名）同時餵給素材腳本、頁面和兩支測試，截圖清單只存在這一處。雙語文案是兩份形狀相同的 `SiteLocaleData`，由測試比對兩者形狀是否一致，不靠人工對照。
- **可消滅的複雜度**：參考 repo 有 451 行 `showcase.ts`（WAI-ARIA tabs、OS 偵測、canvas）、`OsSwitcherBox`、JSON-LD。本站是敘事式單頁，五個功能段落共用同一種 `Section` 形狀、由同一個迴圈渲染，**不送出任何 client JS**。版本號直接不上站（§4 A1），「版本漂移」這個邊界情況因此不存在。
- **最大破壞風險**：網站原始碼被打包進 pub 套件（反目標）。用 `.pubignore` 擋，並以 `dart pub publish --dry-run` 的檔案樹驗證。`lib/`、`test/` 完全不碰，Flutter 測試不受影響。

---

## 2. 實作方向與 Trade-off

| 方向 | 作法 | 優點 | 缺點 | 結論 |
|:---|:---|:---|:---|:---|
| A. 全套照搬 | 連 `showcase.ts` 互動鏡頭、OS switcher、JSON-LD、theme-color inline script 一起搬 | 改字串就能動 | 一大塊 JS 與測試在處理這裡不存在的需求（OS 切換、鏡頭分頁）；規格 §5.1 的目錄也沒列這些檔 | ❌ |
| **B. 照搬工具鏈、精簡頁面（採用）** | 照搬 package.json、astro.config、firebase.json、CI、`node --test` 驗證模式；頁面改寫成「Hero → 5 段 `Section` 迴圈 → 承諾 → 安裝 → Footer」，零 client JS | 兩個 repo 的工具與 CI 相同；頁面元件約 120 行；測試只驗證這一站真正有的東西 | 文案與 CSS 要重寫（文案本來就要重寫） | ✅ |
| C. 不要 `site.ts`，文案直接寫在兩個 `.astro` 頁面 | 少一層資料檔 | 少一個檔 | 雙語內容維護兩份 markup，「key 一致」「截圖都用到」這類檢查無法自動化（規格 §5.6 要求） | ❌ |

子決策（實測或查證過）：

| 項目 | 選擇 | 依據 |
|:---|:---|:---|
| 截圖輸出尺寸 | 540×1200、WebP q78 | 用 libwebp（Pillow）實測 12 張：**540×1200 q78 總計約 370 KB、單張最大約 66 KB**；720×1600 q82 總計約 564 KB，距 600 KB 上限只剩 6%，不採用。頁面上每張最寬顯示 240 CSS px，540 px 足夠 2x 螢幕 |
| 手機外框 | 頁面截圖用 CSS 外框（`border` + `border-radius`）；只有 og-card 把外框畫進圖裡 | 和參考 repo 相同（參考 repo 的 `renderPhoneFrame` 只用在 og-card）。CSS 外框不增加檔案大小 |
| 版本號 | 不上站（§4 A1） | 規格 §5.3 允許「要顯示的話…」，沒有要求一定顯示 |
| client JS | 無 | 沒有任何互動需求 |
| JSON-LD / theme-color | 不做 | 規格沒要求（YAGNI） |

---

## 3. 資料結構與資料流

### 3.1 `website/src/data/site.ts` 的形狀

```ts
export const LOCALES = ['en', 'zh-tw'] as const;
export type Locale = (typeof LOCALES)[number];

// 截圖的唯一清單：shot id → doc/screenshots 原始檔名。輸出固定為 public/screenshots/<id>.webp
export const SCREENSHOTS = { home: 'Screenshot_home.png', /* …共 12 筆… */ } as const;
export type ShotId = keyof typeof SCREENSHOTS;
export const SHOT_SIZE = { width: 540, height: 1200 } as const;
export const shotSrc = (id: ShotId): string => `/screenshots/${id}.webp`;

export const SITE_META = { baseUrl, pubUrl, repoUrl, issuesUrl, licenseUrl, androidSetupUrl, ogImagePath, faviconPath } as const;
export const INSTALL = { addCommand, initSnippet } as const;   // 程式碼兩語系共用

export interface Shot { id: ShotId; alt: string }
export interface Section { id: string; title: string; lead: string; points: readonly string[]; shots: readonly Shot[] }
export interface Pledge { title: string; detail: string }
export interface SiteLocaleData {
  htmlLang: 'en' | 'zh-Hant-TW';
  ogLocale: 'en_US' | 'zh_TW';
  path: '/' | '/zh-tw/';
  langName: string;        // 語言切換器上顯示的名稱：EN／中文
  readmeUrl: string;
  ui: { skipToContent; langSwitch; github; pub; issues; license; readme };
  seo: { title; description; ogImageAlt };
  hero: { title; lead; shot: Shot };
  sections: readonly Section[];                       // 規格 §5.2 的段落 1～5
  pledges: { title; lead; items: readonly Pledge[] }; // 段落 6
  install: { title; lead; addStep; androidNote; androidLink; initStep; note };  // 段落 7
  footer: { tagline };
}
export const SITE_DATA: Record<Locale, SiteLocaleData>;
```

設計取捨：
- **段落編號不存資料**：`01`～`05` 由迴圈 index 算出，不另設 `eyebrow` 欄位。
- **語言切換器不寫死**：對 `LOCALES` 跑迴圈，每個語系顯示自己的 `langName` 並連到自己的 `path`。之後加語系不必改元件。
- **hreflang／canonical 由 `SITE_DATA[l].path` 推出**，不另存 alternate path。
- **`site.ts` 只能用「可抹除」的 TS 語法**（`interface`、`type`、`as const`、型別標註），不能用 `enum`、`namespace` 或建構子參數屬性。原因是 `prepare-assets.mjs` 和兩支測試都直接用 Node 原生 type stripping `import` 這個檔。

### 3.2 資料流

```text
doc/screenshots/*.png ──(npm run prepare:assets，本機手動，需 sharp)──▶ website/public/screenshots/<id>.webp
                                                                     website/public/favicon.png、og-card.png
        ▲ 讀 SCREENSHOTS / SHOT_SIZE / SITE_META                         （產物 commit 進 repo）
        │
website/src/data/site.ts ──▶ LandingPage.astro ──(npm run build)──▶ website/dist/{index.html, zh-tw/index.html, screenshots/…}
        │                                                                 │
        └──▶ test/site-data.test.mjs（資料與 public/）                   └──▶ test/verify-dist.test.mjs（建置產物）
```

CI 只跑 `npm ci → npm run build → npm test`，**不跑** `prepare:assets`（和參考 repo 相同）。

---

## 4. 規格歧義裁決（planner 判斷）

| # | 歧義 | 裁決 | 理由 |
|:-:|:---|:---|:---|
| A1 | 規格 §5.2 段落 7 寫「`pubspec.yaml` 一行」，§5.3 又禁止寫死版本號 | 安裝第 1 步改顯示 `flutter pub add flutter_inspector_kit`，**全站不出現任何版本號** | `pubspec.yaml` 那一行一定要帶版本約束。如果改成 build 時從 `pubspec.yaml` 讀，CI 的 `paths` 只監看 `website/**`，發版時網站不會重新部署，版本照樣會過期。要修就得把 `pubspec.yaml` 加進 `paths`，偏離照搬的 CI，還要多一套 `define` 串接。`flutter pub add` 寫進使用者 pubspec 的就是當下最新的那一行，效果相同。另有兩道測試防止版本號被寫進文案或 HTML（T3、T4） |
| A2 | 規格 §5.1 註解寫 prepare-assets 產出「手機外框」 | 頁面截圖用 CSS 外框，只有 og-card 把外框畫進圖裡 | 參考 repo 實際上就是這樣做；畫進圖裡會讓 12 張圖都變大，壓縮預算 |
| A3 | 截圖尺寸（規格 §7 交給實作者） | 540×1200，`fit: 'cover'` 裁成同一尺寸 | 實測預算見 §2。`layout_inspect_*` 原圖是 1080×2424，cover 後上下各裁約 6 px。全部同一尺寸，`<img width height>` 只需要一組常數 |
| A4 | 原始檔名 `Screenshot_diagnotic_report.png` 拼錯 | 輸出名用 `diagnostic-report.webp`，**原始檔不改名** | README 中英兩份都用這個原始檔名連到 GitHub raw |
| A5 | favicon 來源（規格 §7） | 在 prepare-assets 裡用一段內嵌 SVG（放大鏡圖示）畫成 64×64 PNG | `example/web/favicon.png` 只有 16×16，`example/web/icons/*` 是 Flutter 預設 logo，拿來當本套件的品牌會讓人誤會 |
| A6 | 右上 nav 是否要有段落錨點 | 不要。只放 GitHub 和 EN／中文 | 規格 §5.2 原文「右上角 nav：GitHub 連結和 EN / 中文切換」 |
| A7 | 「外部連結都是 https」的檢查要做在哪一層 | 做在資料層（`SITE_META` + `SITE_DATA` 所有 `scheme://` 字串）。dist 層改為檢查站內連結和錨點都能解析 | 所有外部連結都來自 `site.ts`，資料層檢查最直接 |
| A8 | 文案 | 本計畫 T3 提供完整的中英初稿，事實都取自 README.md 的 Features 表與 Usage 段（至少 `README.md:59-115` 安裝／初始化、`README.md:480-532` Live notification 與 Android setup）。**README.zh-TW.md 缺少的段落（例如 Android desugaring），中文文案一律對照英文 README** | 規格 §7 允許實作者潤飾措辭，但**不得加入 README 沒有的功能宣稱，也不得和 README 的必要設定矛盾** |
| A9 | `website/package.json` 的 `version` 欄位 | 不寫 | 私有、不發布的 npm 套件不需要這個欄位；也避免和 CLAUDE.md §4 的 4 處版本號混淆 |
| A10 | Android 必要設定（修訂 1，B1） | 安裝段在 `flutter pub add` 之後加一段 Android 提示：必須啟用 core library desugaring（依 `flutter_local_notifications`，**不論是否開啟通知**）。連到 `SITE_META.androidSetupUrl`，也就是英文 README 的 `#live-notification-opt-in` 段（Android setup 在這段的 `<details>` 裡）。**中英兩語都連英文 README**，中文文案註明說明只有英文版。標題從「兩步開始」改為「開始使用」。文案**不寫** `desugar_jdk_libs` 的版本 | 依據 `README.md:510-513`：沒開 desugaring，App 無法 build。`README.zh-TW.md` 沒有這段，連 `readmeUrl` 會讓中文讀者找不到。版本字串會被版本號測試擋下，而且會變成第 5 處需要同步的版本號。shortcut：錨點跟著 README 的標題走，標題改名後連結只會落到 README 頂端、不會 404。到時把 `androidSetupUrl` 改成新錨點即可 |

---

## 5. 檔案異動清單

| # | 檔案 | 動作 | 任務 |
|:-:|:---|:---|:-:|
| 1 | `.pubignore` | 修改：末尾加 `website/`、`.github/` | T1 |
| 2 | `website/package.json` | 新增：astro `^7.4.13`、devDep sharp `^0.35.4`、5 個 scripts | T2 |
| 3 | `website/package-lock.json` | 新增：`npm install` 產生 | T2 |
| 4 | `website/astro.config.mjs` | 新增：`site`、`output: 'static'`、`trailingSlash: 'ignore'` | T2 |
| 5 | `website/tsconfig.json` | 新增：照搬 | T2 |
| 6 | `website/.gitignore` | 新增：照搬 | T2 |
| 7 | `website/.firebaserc` | 新增：`default: flutterinspectorkit` | T2 |
| 8 | `website/firebase.json` | 新增：照搬（安全 header 與快取規則） | T2 |
| 9 | `website/src/data/site.ts` | 新增：型別、`SCREENSHOTS`、`SITE_META`、`INSTALL`、雙語 `SITE_DATA` | T3 |
| 10 | `website/test/site-data.test.mjs` | 新增：雙語形狀一致、12 張截圖各用一次且存在、https、無版本號與反引號 | T3 |
| 11 | `website/scripts/prepare-assets.mjs` | 新增：PNG → WebP、favicon、og-card，含大小上限 | T3 |
| 12 | `website/public/screenshots/*.webp`（12 張） | 新增：#11 的產物 | T3 |
| 13 | `website/public/favicon.png`、`website/public/og-card.png` | 新增：#11 的產物 | T3 |
| 14 | `website/src/layouts/BaseLayout.astro` | 新增：`<head>`（SEO／hreflang／OG）+ skip link | T4 |
| 15 | `website/src/components/LandingPage.astro` | 新增：整頁 markup | T4 |
| 16 | `website/src/styles/global.css` | 新增：設計 token、版面、明暗色 | T4 |
| 17 | `website/src/pages/index.astro`、`website/src/pages/zh-tw/index.astro` | 新增：各 5 行入口 | T4 |
| 18 | `website/test/verify-dist.test.mjs` | 新增：dist 雙頁、lang／canonical／hreflang、連結與錨點、截圖集合與預算、無版本號 | T4 |
| 19 | `.github/workflows/website.yml` | 新增：照搬並換 project id（原 T5，修訂 1 併入 T2） | T2 |
| 20 | `CLAUDE.md` | 修改：§3「無 CI 機制」那一行改寫為「Flutter 側仍無 CI；唯一的 workflow 只管 `website/`」（修訂 1，L4） | T2 |

不需改：`lib/`、`test/`、`pubspec.yaml`、README 兩份、CHANGELOG（網站不屬於套件發布內容）、CLAUDE.md §4（沒有新增版本號位置；CLAUDE.md 只改 §3 那一行）。已用 `git check-ignore --no-index` 確認 #2～#19 都不會被根目錄 `.gitignore` 忽略（根目錄的 `flutter_*.png` 規則不會命中 `favicon.png`／`og-card.png`）。

---

## 6. 任務拆分

| 任務 | 內容 | 寫入路徑 | 微任務？ | 建議 model tier | 依賴 |
|:---|:---|:---|:-:|:---|:---|
| T1 | `.pubignore` 排除 website／.github | #1 | 🛑 **是**（單檔 +2 行、無公共 API）→ 主進程原地改並**先 commit** | — | 無 |
| T2 | 專案骨架、Firebase 設定、CI workflow、CLAUDE.md CI 敘述 | #2～#8、#19、#20 | 否（9 檔） | 快/便宜（照搬計畫內全文） | T1 已 commit |
| T3 | 資料、文案、素材管線（TDD） | #9～#13 | 否 | 標準（雙語文案 + sharp 腳本） | T2（需要 sharp） |
| T4 | 頁面與 dist 驗證（TDD） | #14～#18 | 否 | 標準 | T3（需要 `site.ts` 與 `public/`） |

`total_tasks=4`，**全部序列執行**：T1（主進程改完即 commit）→ T2 → T3 → T4。同一個 worktree 內同一時間只有一個寫入者，不會有並行 commit。

**範圍驗收規則**（implementer 會先 commit 才交 verifier，所以不能用 `git status` 判斷範圍。T2～T4 的驗收都引用這條）：

```bash
BASE="$(git merge-base HEAD origin/main)"
# 本任務變更集 = 已 commit + 未 commit 的追蹤檔差異 ∪ 尚未 git add 的新檔
{ git diff --name-only "$BASE" -- <本任務路徑…>; git ls-files --others --exclude-standard -- <本任務路徑…>; } | sort -u
```

- **範圍檢查**：輸出必須恰好等於本任務在 §5 的檔案（不多不少）。
- **越界檢查**：拿掉路徑參數再跑一次，全量輸出只能有 §5 清單中「本任務與先前任務」的檔案，以及本計畫和規格。

---

### Task 1：`.pubignore`（🛑 微任務，主進程原地改）

**寫入**：`.pubignore`

#### 步驟 1.1：在檔尾加兩行

```gitignore
website/
.github/
```

（`.github/` 其實已被 pub 的預設規則排除：實測目前 dry-run 不會列出 `.serena/`、`.coderabbit.yaml` 這類點開頭的檔案。照規格 §5.5 仍明確寫出來，沒有副作用。）

#### 驗收

```bash
# 在 repo 根目錄
dart pub publish --dry-run 2>&1 | grep -cE '── (website|\.github)'   # 期望輸出 0
dart pub publish --dry-run 2>&1 | tail -1                              # 期望 "Package has 0 warnings."（commit 之後跑）
```

- 目前基準（2026-11-24 實測）：dry-run 結束碼 0，`Package has 0 warnings.`，壓縮後 603 KB。
- 還沒 commit 時，pub 可能因為 `.pubignore` 是已修改的追蹤檔而多報一個 modified-file warning，所以 warnings 數要在 commit 之後才準。
- `website/` 要等 T2 之後才存在，這一步的 `grep` 現在一定是 0。**實質驗證放在 §7 整體驗收重跑一次。**
- **主進程改完立即 commit**（`chore(pub): exclude website/ and .github/ from package`），之後才派發 T2，避免同一個 worktree 裡有兩個寫入者。

---

### Task 2：專案骨架、Firebase 設定、CI workflow

**寫入**：`website/package.json`、`website/package-lock.json`、`website/astro.config.mjs`、`website/tsconfig.json`、`website/.gitignore`、`website/.firebaserc`、`website/firebase.json`、`.github/workflows/website.yml`、`CLAUDE.md`（只改 1 行）

這個任務只有設定、沒有邏輯，不寫測試，以指令驗收。下面每個檔案的完整內容都寫在本計畫裡，**不需要讀取 worktree 以外的任何檔案**。這些內容是 planner 從參考 repo 逐字抄來的；與參考 repo 的比對由 planner 事前做過，結果見 §7 的事前實測。

#### 步驟 2.1：建立 `website/tsconfig.json`

```json
{
  "extends": "astro/tsconfigs/strict",
  "include": [".astro/types.d.ts", "src/**/*"],
  "exclude": ["dist", "node_modules"]
}
```

#### 步驟 2.2：建立 `website/.gitignore`

```gitignore
node_modules/
dist/
.astro/
.firebase/
.DS_Store
```

#### 步驟 2.3：建立 `website/firebase.json`

`public: dist`；`ignore` 排除設定檔、`src/**`、`scripts/**`、`test/**`；全站加三個安全 header；`/_astro/**` 快取 1 年 immutable，`/screenshots/**` 快取 1 天加 SWR 1 天（網址不含雜湊，換圖後最多 1 天內重新取得），`/favicon.png` 與 `/og-card.png` 快取 7 天。除 `/screenshots/**` 的 `max-age` 外和參考 repo 相同，因為路徑完全一樣。

```json
{
  "hosting": {
    "public": "dist",
    "ignore": [
      "firebase.json",
      ".firebaserc",
      "**/.*",
      "**/node_modules/**",
      "src/**",
      "scripts/**",
      "test/**"
    ],
    "headers": [
      {
        "source": "**",
        "headers": [
          {
            "key": "X-Content-Type-Options",
            "value": "nosniff"
          },
          {
            "key": "Referrer-Policy",
            "value": "strict-origin-when-cross-origin"
          },
          {
            "key": "X-Frame-Options",
            "value": "DENY"
          }
        ]
      },
      {
        "source": "/_astro/**",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "public, max-age=31536000, immutable"
          }
        ]
      },
      {
        "source": "/screenshots/**",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "public, max-age=86400, stale-while-revalidate=86400"
          }
        ]
      },
      {
        "source": "/favicon.png",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "public, max-age=604800"
          }
        ]
      },
      {
        "source": "/og-card.png",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "public, max-age=604800"
          }
        ]
      }
    ]
  }
}
```

#### 步驟 2.4：建立 `website/package.json`

```json
{
  "name": "flutter-inspector-kit-website",
  "private": true,
  "type": "module",
  "description": "Bilingual static product site for flutter_inspector_kit",
  "engines": {
    "node": "^22.23.4 || >=24.0.0"
  },
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview",
    "prepare:assets": "node scripts/prepare-assets.mjs",
    "test": "node --test test/*.test.mjs"
  },
  "dependencies": {
    "astro": "^7.4.13"
  },
  "devDependencies": {
    "sharp": "^0.35.4"
  }
}
```

`engines.node ^22.23.4 || >=24.0.0`：22.23.4 是 astro 7.4.13 CLI 的硬性下限（`astro/bin/astro.mjs` 啟動時檢查，不符即 `process.exit(1)`），高於 Node 原生 type stripping 不需 flag 的最低版本 22.18.0；23.x 排除，因為 23.6.0 才預設啟用 type stripping，23.0–23.5 會在 `import` `.ts` 時失敗。測試和素材腳本都直接 `import` `.ts`，兩個條件都需要。CI 用 Node 24，本機實測是 v26.13.1。

#### 步驟 2.5：建立 `website/astro.config.mjs`

```js
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://flutterinspectorkit.web.app',
  output: 'static',
  trailingSlash: 'ignore',
});
```

#### 步驟 2.6：建立 `website/.firebaserc`

```json
{
  "projects": {
    "default": "flutterinspectorkit"
  }
}
```

#### 步驟 2.7：產生 lockfile

```bash
cd website && npm install
```

#### 步驟 2.8：建立 `.github/workflows/website.yml`

和參考 repo 的差異是 project id 與 `paths`（見下）：`findrestaurant-c80ea` 換成 `flutterinspectorkit`，在 step summary 和 deploy 指令各出現 1 次。權限、concurrency、Node 24、`firebase-tools@15.28.2`、角色說明都逐字相同；觸發條件多一條 `doc/screenshots/**`，讓來源 PNG 變動時也會跑 `assets-fresh` 測試（PR #262 review）。**本計畫只有這一個 `yaml` 區塊**，驗收時直接從計畫抽出來比對。

```yaml
name: Website CI & Hosting

on:
  pull_request:
    branches: [main]
    paths:
      - 'website/**'
      - 'doc/screenshots/**'
      - '.github/workflows/website.yml'
  push:
    branches: [main]
    paths:
      - 'website/**'
      - 'doc/screenshots/**'
      - '.github/workflows/website.yml'

permissions:
  contents: read

concurrency:
  group: website-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  build-and-verify:
    name: Build & Verify Static Site
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: website
    steps:
      - name: Checkout repository
        uses: actions/checkout@v5

      - name: Setup Node.js
        uses: actions/setup-node@v5
        with:
          node-version: '24'
          cache: 'npm'
          cache-dependency-path: website/package-lock.json

      - name: Install dependencies
        run: npm ci

      - name: Build Astro static site
        run: npm run build

      - name: Run static verification tests
        run: npm test

      - name: Deploy to Firebase Hosting (main only)
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          FIREBASE_SA_JSON: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_JSON }}
        run: |
          if [ -z "$FIREBASE_SA_JSON" ]; then
            {
              echo "### Firebase Hosting Deploy Skipped"
              echo ""
              echo "Secret \`FIREBASE_SERVICE_ACCOUNT_JSON\` is not configured."
              echo ""
              echo "To enable automated deployment on \`main\`:"
              echo "1. Create a Service Account JSON with **Firebase Hosting Admin** (\`roles/firebasehosting.admin\`) and **API Keys Viewer** (\`roles/serviceusage.apiKeysViewer\`) permissions for project \`flutterinspectorkit\`."
              echo "2. Save it in GitHub **Settings → Secrets and variables → Actions** as \`FIREBASE_SERVICE_ACCOUNT_JSON\`."
            } >> "$GITHUB_STEP_SUMMARY"
            exit 0
          fi

          CRED_FILE="$(mktemp)"
          chmod 600 "$CRED_FILE"
          trap 'rm -f "$CRED_FILE"' EXIT
          printf '%s' "$FIREBASE_SA_JSON" > "$CRED_FILE"
          export GOOGLE_APPLICATION_CREDENTIALS="$CRED_FILE"
          npx --yes firebase-tools@15.28.2 deploy --only hosting --project flutterinspectorkit --non-interactive
```

#### 步驟 2.9：修正 `CLAUDE.md` §3 的 CI 敘述

這一行原本說 repo 沒有任何 CI。加了 workflow 之後，這句話已經不正確。只替換這一行，CLAUDE.md 其他內容不動。

```diff
-- **無 CI 機制（本機嚴格驗證）**：Repo 未設置 `.github/` CI workflow，所有測試與靜態分析完全依賴開發者與 Agent 本機執行確認。
+- **Flutter 側無 CI（本機嚴格驗證）**：Flutter 套件本身沒有 CI，所有測試與靜態分析完全依賴開發者與 Agent 本機執行確認。唯一的 workflow `.github/workflows/website.yml` 只負責 `website/` 的建置、驗證與部署。
```

#### 驗收

```bash
cd website
rm -rf node_modules && npm ci                                   # exit 0（確認 lockfile 可重現）
npx astro --version                                             # 7.x
node -e "for (const f of ['firebase.json', '.firebaserc', 'package.json', 'tsconfig.json']) JSON.parse(require('fs').readFileSync(f, 'utf8'))"
grep -c flutterinspectorkit .firebaserc astro.config.mjs        # 各 1
git check-ignore node_modules/ dist/ .astro/ .firebase/         # 印出 4 行（要加結尾斜線：dist/ 等目錄還不存在，不加斜線 git 不會套用 dir/ 規則，已實測）
cd ..
# workflow 必須和本計畫的 yaml 區塊逐字相同
awk '/^```yaml$/{f=1;next} /^```$/{if(f)exit} f' docs/plans/2026-11-24-product-website.md | diff - .github/workflows/website.yml   # 期望無輸出
command -v actionlint && actionlint .github/workflows/website.yml   # 本機沒裝就跳過（2026-11-24 實查沒裝）
git diff --numstat "$(git merge-base HEAD origin/main)" -- CLAUDE.md          # 1  1  CLAUDE.md（只換一行）
```

最後再跑一次 §6 的範圍驗收規則，本任務的路徑是 `website .github CLAUDE.md`。輸出必須恰好是 #2～#8、#19、#20 這 9 個檔案。

---

### Task 3：資料、文案、素材管線（TDD）

**寫入**：`website/src/data/site.ts`、`website/test/site-data.test.mjs`、`website/scripts/prepare-assets.mjs`、`website/public/favicon.png`、`website/public/og-card.png`、`website/public/screenshots/*.webp`（12 張）

#### 步驟 3.1（紅）：建立 `website/test/site-data.test.mjs`

```js
import assert from 'node:assert/strict';
import test from 'node:test';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { INSTALL, LOCALES, SCREENSHOTS, SITE_DATA, SITE_META, shotSrc } from '../src/data/site.ts';

const PUBLIC_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'public');
const inPublic = (webPath) => existsSync(path.join(PUBLIC_DIR, webPath));

// 文案的形狀：字串一律記成 'string'，陣列保留長度，id 保留原值。兩語系的形狀必須相同
const shape = (v, key) =>
  key === 'id'
    ? v
    : typeof v === 'string'
      ? 'string'
      : Array.isArray(v)
        ? v.map((x) => shape(x))
        : Object.fromEntries(Object.keys(v).sort().map((k) => [k, shape(v[k], k)]));

const strings = (v) => (typeof v === 'string' ? [v] : Object.values(v).flatMap(strings));
const shotsOf = (d) => [d.hero.shot, ...d.sections.flatMap((s) => s.shots)];

test('兩語系齊全且結構一致', () => {
  assert.deepEqual(Object.keys(SITE_DATA).sort(), [...LOCALES].sort());
  assert.deepEqual(shape(SITE_DATA['zh-tw']), shape(SITE_DATA.en));
});

test('12 張截圖每張恰用一次、都有 alt，且已輸出到 public/', () => {
  const all = Object.keys(SCREENSHOTS).sort();
  assert.equal(all.length, 12);
  for (const locale of LOCALES) {
    const shots = shotsOf(SITE_DATA[locale]);
    assert.deepEqual(shots.map((s) => s.id).sort(), all, `${locale} 截圖清單與 SCREENSHOTS 不符`);
    for (const s of shots) assert.ok(s.alt.trim().length > 0, `${locale} ${s.id} 缺 alt`);
  }
  for (const id of all) {
    assert.ok(inPublic(shotSrc(id)), `缺 public${shotSrc(id)}：先跑 npm run prepare:assets`);
  }
  assert.ok(inPublic(SITE_META.faviconPath), '缺 favicon');
  assert.ok(inPublic(SITE_META.ogImagePath), '缺 og-card');
});

test('外部連結一律 https', () => {
  const urls = [...strings(SITE_META), ...strings(SITE_DATA)].filter((s) => /^\w+:\/\//.test(s));
  assert.ok(urls.length >= 6);
  for (const u of urls) assert.match(u, /^https:\/\//, u);
});

test('文案不含版本號與 Markdown 反引號', () => {
  for (const s of strings(SITE_DATA)) {
    assert.doesNotMatch(s, /\b\d+\.\d+\.\d+\b/, `疑似寫死版本號：${s}`);
    assert.doesNotMatch(s, /`/, `Markdown 反引號外洩到文案：${s}`);
  }
  assert.doesNotMatch(INSTALL.addCommand + INSTALL.initSnippet, /\b\d+\.\d+\.\d+\b/);
});
```

```bash
cd website && npm test   # 預期紅：Cannot find module '../src/data/site.ts'
```

#### 步驟 3.2：建立 `website/src/data/site.ts`

下面是完整檔案。文案是初稿：可以潤飾，但**不得加入 README 沒有的功能宣稱**（§4 A8）。每張截圖的 `alt` 要開原圖核對一次（`doc/screenshots/`），描述和畫面對不上就修正 alt。

```ts
export const LOCALES = ['en', 'zh-tw'] as const;
export type Locale = (typeof LOCALES)[number];

// shot id → doc/screenshots 原始檔名；輸出為 public/screenshots/<id>.webp
export const SCREENSHOTS = {
  home: 'Screenshot_home.png',
  console: 'Screenshot_console.png',
  network: 'Screenshot_network.png',
  'network-detail': 'Screenshot_network_detail.png',
  navigator: 'Screenshot_navigator.png',
  'database-browse': 'Screenshot_database_browse.png',
  'shared-preference': 'Screenshot_shared_preference.png',
  'layout-inspect-loupe': 'Screenshot_layout_inspect_loupe.png',
  'layout-inspect-ruler': 'Screenshot_layout_inspect_ruler.png',
  'diagnostic-report': 'Screenshot_diagnotic_report.png', // 原始檔名拼字照舊：README 以此檔名連結
  'info-sharing': 'Screenshot_info_sharing.png',
  'uncaught-error': 'Screenshot_uncaught_error.png',
} as const;

export type ShotId = keyof typeof SCREENSHOTS;
export const SHOT_SIZE = { width: 540, height: 1200 } as const;
export const shotSrc = (id: ShotId): string => `/screenshots/${id}.webp`;

export const SITE_META = {
  baseUrl: 'https://flutterinspectorkit.web.app',
  pubUrl: 'https://pub.dev/packages/flutter_inspector_kit',
  repoUrl: 'https://github.com/Yomiamy/flutter_inspector_kit',
  issuesUrl: 'https://github.com/Yomiamy/flutter_inspector_kit/issues',
  licenseUrl: 'https://github.com/Yomiamy/flutter_inspector_kit/blob/main/LICENSE',
  // Android setup（desugaring）只寫在英文 README 這一段的 <details> 裡，中英兩語都連這裡
  // shortcut: 錨點跟著 README 標題走，標題改名後只會落到 README 頂端；改名時同步更新這裡
  androidSetupUrl: 'https://github.com/Yomiamy/flutter_inspector_kit/blob/main/README.md#live-notification-opt-in',
  ogImagePath: '/og-card.png',
  faviconPath: '/favicon.png',
} as const;

// API 名稱與 README「Initialize」段一致：navigatorKey / navigatorObserver / FlutterInspectorMagicalTap / openDashboard
export const INSTALL = {
  addCommand: 'flutter pub add flutter_inspector_kit',
  initSnippet: `import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final inspector = FlutterInspector(navigatorKey: navigatorKey);

void main() => runApp(
      MaterialApp(
        navigatorKey: navigatorKey, // the same key the inspector holds
        navigatorObservers: [inspector.navigatorObserver],
        builder: (context, child) => FlutterInspectorMagicalTap(
          onTap: () => inspector.openDashboard(),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Placeholder(),
      ),
    );`,
} as const;

export interface Shot {
  id: ShotId;
  alt: string;
}

export interface Section {
  id: string;
  title: string;
  lead: string;
  points: readonly string[];
  shots: readonly Shot[];
}

export interface Pledge {
  title: string;
  detail: string;
}

export interface SiteLocaleData {
  htmlLang: 'en' | 'zh-Hant-TW';
  ogLocale: 'en_US' | 'zh_TW';
  path: '/' | '/zh-tw/';
  langName: string;
  readmeUrl: string;
  ui: {
    skipToContent: string;
    langSwitch: string;
    github: string;
    pub: string;
    issues: string;
    license: string;
    readme: string;
  };
  seo: { title: string; description: string; ogImageAlt: string };
  hero: { title: string; lead: string; shot: Shot };
  sections: readonly Section[];
  pledges: { title: string; lead: string; items: readonly Pledge[] };
  install: {
    title: string;
    lead: string;
    addStep: string;
    androidNote: string;
    androidLink: string;
    initStep: string;
    note: string;
  };
  footer: { tagline: string };
}

export const SITE_DATA: Record<Locale, SiteLocaleData> = {
  en: {
    htmlLang: 'en',
    ogLocale: 'en_US',
    path: '/',
    langName: 'EN',
    readmeUrl: `${SITE_META.repoUrl}/blob/main/README.md`,
    ui: {
      skipToContent: 'Skip to main content',
      langSwitch: 'Language',
      github: 'GitHub',
      pub: 'pub.dev',
      issues: 'Issues',
      license: 'MIT License',
      readme: 'Full usage in the README',
    },
    seo: {
      title: 'flutter_inspector_kit — an in-app debugging timeline for Flutter',
      description:
        'An in-app debugging overlay for Flutter: logs, network, navigation and database events merged into one timeline, with request replay, layout inspection and shareable diagnostic reports.',
      ogImageAlt: 'flutter_inspector_kit preview with the Console timeline, the Network list and a diagnostic report',
    },
    hero: {
      title: 'Debug by following the chain, not by poking points.',
      lead: 'flutter_inspector_kit is an in-app debugging overlay for Flutter. Logs, network calls, navigation and database operations land on one merged timeline, so you read how a bug unfolded instead of hunting for a single entry.',
      shot: { id: 'home', alt: "Example app with the inspector's draggable floating button" },
    },
    sections: [
      {
        id: 'timeline',
        title: 'One timeline for everything that happened',
        lead: 'The Console tab interleaves logs, network calls, navigation and database events by timestamp. Scroll back from the failure and the cause is usually a few rows above it.',
        points: [
          'Per-source filter chips narrow the timeline to the events you care about',
          'Long-press any entry to bookmark it, then show bookmarks only',
          'Errors and failed requests carry a faint red row tint',
          'Every log records the page that was on top when it was written',
        ],
        shots: [{ id: 'console', alt: 'Console tab with logs, a failed request and lifecycle events on one timeline' }],
      },
      {
        id: 'network',
        title: 'Watch a request evolve',
        lead: 'A request appears the moment it starts and completes in place when the response lands. When it fails, you see why — and you can send it again.',
        points: [
          'Replay a captured call through the original Dio instance: same headers, base URL and interceptors',
          'Requests over a configurable threshold are flagged 🐢 SLOW, even while still waiting',
          'A summary banner groups failures by status code or error type',
          'Transport failures are told apart from 4xx/5xx server errors',
          'Bodies render as a collapsible JSON tree; share any call as cURL',
        ],
        shots: [
          { id: 'network', alt: 'Network tab listing captured requests' },
          { id: 'network-detail', alt: 'Detail view of a single network request' },
        ],
      },
      {
        id: 'state',
        title: 'Where the user went, what the app stored',
        lead: 'Route changes, database operations and key-value storage sit on the same timeline as the requests around them.',
        points: [
          "Switch between navigation history and the live route stack, with each route's params and args",
          'Record insert, update, delete and query operations; browse real SQLite or ObjectBox tables',
          'Browse, edit and clear key-value stores such as SharedPreferences — every write is confirmed',
        ],
        shots: [
          { id: 'navigator', alt: 'Navigator tab with route events' },
          { id: 'database-browse', alt: 'Database browser showing rows of a local table' },
          { id: 'shared-preference', alt: 'Storage tab listing key-value entries' },
        ],
      },
      {
        id: 'layout',
        title: 'Measure the layout on the device',
        lead: 'Tap any widget to read its size, constraints, position and on-screen color, then walk up its parents to find the one imposing the limit.',
        points: [
          'Press and drag to aim at small targets with a magnifier and crosshair',
          'The ruler measures gaps to another widget in both dp and px',
          'Copy or share the whole parent chain as text; works in release builds',
        ],
        shots: [
          { id: 'layout-inspect-loupe', alt: 'Magnifier and crosshair aiming at a small widget' },
          { id: 'layout-inspect-ruler', alt: 'Ruler showing the distance between two widgets in dp and px' },
        ],
      },
      {
        id: 'handoff',
        title: 'Hand it off with the context attached',
        lead: 'When someone else fixes the bug, give them the chain — not a screenshot of one row.',
        points: [
          'Export one Markdown diagnostic report filtered by time window, source and errors only, straight to the share sheet',
          'Copy any log or request as a prompt for a coding agent, with the earlier events from the same page',
          'Opt-in uncaught error capture turns crashes into error logs and never swallows them',
        ],
        shots: [
          { id: 'diagnostic-report', alt: 'Diagnostic report export options' },
          { id: 'info-sharing', alt: 'Share menu on a log entry with copy, share and AI agent prompt options' },
          { id: 'uncaught-error', alt: 'Uncaught error recorded as an error log with its stack trace' },
        ],
      },
    ],
    pledges: {
      title: 'Light by design',
      lead: 'A debugging tool should not dictate how your app is architected.',
      items: [
        {
          title: 'No state-management dependency',
          detail: 'Built on ValueNotifier and StatefulWidget. No BLoC, Riverpod or Provider is pulled into your app.',
        },
        {
          title: 'Opt-in stays off',
          detail: 'Uncaught error capture, lifecycle markers, frozen-frame capture, HttpClient capture and live notifications do nothing until you enable them.',
        },
        {
          title: 'Redacted by default',
          detail: 'Authorization, Cookie, Set-Cookie and X-Api-Key headers, plus token, password, pin and apiKey route parameters, are masked in every share and export.',
        },
      ],
    },
    install: {
      title: 'Get started',
      lead: 'Add the package, enable core library desugaring on Android, then hand the inspector your navigator key.',
      addStep: '1. Add the dependency',
      androidNote:
        'Android apps must enable core library desugaring in android/app/build.gradle.kts (or build.gradle). flutter_local_notifications needs it even if you never turn notifications on; without it the app will not build.',
      androidLink: 'Android setup in the README',
      initStep: '2. Wire it into your app',
      note: 'Pass the same navigatorKey to MaterialApp. Without it, openDashboard() silently does nothing.',
    },
    footer: {
      tagline: 'flutter_inspector_kit — an in-app debugging timeline for Flutter.',
    },
  },
  'zh-tw': {
    htmlLang: 'zh-Hant-TW',
    ogLocale: 'zh_TW',
    path: '/zh-tw/',
    langName: '中文',
    readmeUrl: `${SITE_META.repoUrl}/blob/main/README.zh-TW.md`,
    ui: {
      skipToContent: '跳至主要內容',
      langSwitch: '語言',
      github: 'GitHub',
      pub: 'pub.dev',
      issues: '回報問題',
      license: 'MIT 授權',
      readme: '完整用法見 README',
    },
    seo: {
      title: 'flutter_inspector_kit — Flutter App 內的偵錯時間軸',
      description:
        '嵌入 App 內的 Flutter 偵錯疊層：log、network、navigation 與 database 事件合併在同一條時間軸，並提供請求重送、版面檢查與可分享的診斷報告。',
      ogImageAlt: 'flutter_inspector_kit 預覽：Console 時間軸、Network 列表與診斷報告',
    },
    hero: {
      title: '順著事件鏈排查，而不是逐點查詢。',
      lead: 'flutter_inspector_kit 是嵌入 App 內的 Flutter 偵錯疊層。log、network、navigation、database 四種事件攤平在同一條時間軸上，讓你看到 bug 是怎麼一步步發生的，不必到處翻找單一筆紀錄。',
      shot: { id: 'home', alt: '範例 App 畫面，左上角是可拖曳的 inspector 浮動按鈕' },
    },
    sections: [
      {
        id: 'timeline',
        title: '一條時間軸，看完整件事',
        lead: 'Console 分頁把 log、network、navigation 與 database 事件依時間戳交錯排列。從出錯的那一列往回捲，原因通常就在上面幾列。',
        points: [
          '各來源的 filter chip 可以把時間軸縮小到你在意的事件',
          '長按任一筆加上書籤，再切換成只看書籤',
          'error log 與失敗的請求帶淡紅底色，捲動時一眼就能認出',
          '每筆 log 都記下寫入當下最上層的頁面',
        ],
        shots: [{ id: 'console', alt: 'Console 分頁：log、失敗的請求與生命週期事件排在同一條時間軸' }],
      },
      {
        id: 'network',
        title: '看著請求一步步演變',
        lead: '請求一發出就出現在列表上，回應抵達時原地更新為完成。失敗時會告訴你原因，還能直接重送。',
        points: [
          '透過原本的 Dio 實例重送已擷取的請求，沿用相同的 headers、base URL 與 interceptors',
          '超過可設定門檻的請求會標上 🐢 SLOW，還在等待回應的請求也一樣',
          '摘要橫幅依 status code 或錯誤類型將失敗請求分組',
          '區分傳輸層失敗與 4xx/5xx 伺服器錯誤',
          'body 以可收合的 JSON 樹呈現，任一請求都能分享為 cURL',
        ],
        shots: [
          { id: 'network', alt: 'Network 分頁的請求列表' },
          { id: 'network-detail', alt: '單一網路請求的詳情頁' },
        ],
      },
      {
        id: 'state',
        title: '使用者去了哪裡，App 存了什麼',
        lead: '頁面切換、資料庫操作與 key-value 儲存，都和它們前後的請求排在同一條時間軸上。',
        points: [
          '在導航事件歷史與即時 route stack 之間切換，每個 route 的 Params 與 Args 都會保留',
          '記錄 insert、update、delete、query 操作，並可直接瀏覽 SQLite 或 ObjectBox 的真實資料表',
          '在裝置上瀏覽、編輯、清空 SharedPreferences 等 key-value 儲存，每次寫入都需要確認',
        ],
        shots: [
          { id: 'navigator', alt: 'Navigator 分頁的 route 事件' },
          { id: 'database-browse', alt: 'Database 瀏覽本機資料表的資料列' },
          { id: 'shared-preference', alt: 'Storage 分頁列出 key-value 項目' },
        ],
      },
      {
        id: 'layout',
        title: '直接在裝置上量版面',
        lead: '點任何 widget 就能讀出尺寸、constraints、位置與螢幕上的實際色碼，再沿著父層往上，找出是哪一層限制了它。',
        points: [
          '按住拖曳，用放大鏡與十字準星瞄準小目標',
          '尺規以 dp 與 px 兩種單位量出與另一個 widget 的間距',
          '整條父層鏈可複製或分享為文字；release build 也能用',
        ],
        shots: [
          { id: 'layout-inspect-loupe', alt: '放大鏡與十字準星瞄準一個小 widget' },
          { id: 'layout-inspect-ruler', alt: '尺規以 dp 與 px 顯示兩個 widget 之間的距離' },
        ],
      },
      {
        id: 'handoff',
        title: '交接時，脈絡一起交出去',
        lead: '修 bug 的人不是你時，交給他整條事件鏈，而不是某一列的截圖。',
        points: [
          '匯出單一份 Markdown 診斷報告，可依時間窗、來源與「只看錯誤」篩選，直接送進分享面板',
          '把任一筆 log 或請求複製成給 coding agent 的 prompt，並附上同一頁面稍早的事件',
          'opt-in 的未捕捉錯誤擷取會把崩潰轉成 error log，絕不吞掉錯誤',
        ],
        shots: [
          { id: 'diagnostic-report', alt: '診斷報告的匯出選項' },
          { id: 'info-sharing', alt: 'log 詳情的分享選單：複製、分享與 AI agent prompt' },
          { id: 'uncaught-error', alt: '未捕捉錯誤被記錄為帶有 stack trace 的 error log' },
        ],
      },
    ],
    pledges: {
      title: '刻意保持輕量',
      lead: '偵錯工具不該左右你的 App 架構。',
      items: [
        {
          title: '不綁狀態管理',
          detail: '以 ValueNotifier 與 StatefulWidget 實作，不會把 BLoC、Riverpod 或 Provider 帶進你的 App。',
        },
        {
          title: 'opt-in 功能預設關閉',
          detail: '未捕捉錯誤擷取、生命週期標記、凍結幀擷取、HttpClient 擷取與即時通知，沒有開啟就不會做任何事。',
        },
        {
          title: '敏感資料預設遮罩',
          detail: 'Authorization、Cookie、Set-Cookie、X-Api-Key 等 header，以及 token、password、pin、apiKey 等路由參數，在每一條分享與匯出路徑上都會被遮罩。',
        },
      ],
    },
    install: {
      title: '開始使用',
      lead: '加入套件、在 Android 啟用 core library desugaring，再把 navigator key 交給 inspector。',
      addStep: '1. 加入相依',
      androidNote:
        'Android App 必須在 android/app/build.gradle.kts（或 build.gradle）啟用 core library desugaring。flutter_local_notifications 需要這個設定，就算從來沒開通知也一樣；沒有它，App 會無法 build。',
      androidLink: 'README 的 Android setup（目前只有英文版）',
      initStep: '2. 接進你的 App',
      note: '同一把 navigatorKey 也要傳給 MaterialApp，否則 openDashboard() 會靜默無反應。',
    },
    footer: {
      tagline: 'flutter_inspector_kit — 嵌入 App 的 Flutter 偵錯時間軸。',
    },
  },
};
```

文案事實的出處（verifier 對照用）：README Features 表的 Merged Timeline、Timeline Bookmark、Log Route Context（段落 1）；Network、Network Replay、Slow Request Indicator、Error Aggregation Summary、Structured Network Errors、JSON Tree Viewer（段落 2）；Navigator、Database、Storage（段落 3）；Tap-to-Inspect Layout（段落 4）；Diagnostic Report、Agent Handoff Prompt、Uncaught Error Capture（段落 5）。承諾段：`pubspec.yaml` 的 dependencies 只有 dio、share_plus、flutter_local_notifications、web；`FlutterInspector` 建構子的 `captureUncaughtErrors`、`captureLifecycleEvents`、`capturePerformance`、`showNetworkNotification` 預設都是 `false`；Sensitive-Data Redaction 列。安裝段：`README.md:59-115`（Add to pubspec.yaml、Initialize，以及「Both halves are required」提醒）、`README.md:510-532`（Android setup：不論是否開啟通知都必須啟用 core library desugaring，否則無法 build；`example/android/app/build.gradle.kts` 有實際啟用）。**`README.zh-TW.md` 沒有 Android setup 段落，中文文案要對照英文 README 檢查**，不能只看中文 README。

```bash
cd website && npm test   # 預期：形狀、https、版本號三個測試綠；截圖測試紅（public/ 還沒有 webp）
```

#### 步驟 3.3：建立 `website/scripts/prepare-assets.mjs`

`buildRoundedMask`、`renderPhoneFrame` 和 og PNG 壓縮參數沿用參考 repo，只改配色、文案與版面。

```js
import { mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { SCREENSHOTS, SHOT_SIZE, SITE_META, shotSrc } from '../src/data/site.ts';

const WEBSITE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC_DIR = path.resolve(WEBSITE_ROOT, '..', 'doc', 'screenshots');
const PUBLIC_DIR = path.join(WEBSITE_ROOT, 'public');
const OUT_DIR = path.join(PUBLIC_DIR, path.dirname(shotSrc('home'))); // 輸出路徑一律由 shotSrc 推出

// 實測 540x1200 q78：12 張約 370 KB，單張最大約 66 KB。
// 大小預算由 test/verify-dist.test.mjs 把關（唯一權威），這裡只印數字，方便調整品質
const WEBP_QUALITY = 78;

const SANS = "'Helvetica Neue', Arial, sans-serif";
const MONO = "'SF Mono', Menlo, Consolas, monospace";

const ICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#4338CA"/>
  <circle cx="28" cy="28" r="13" fill="none" stroke="#FFFFFF" stroke-width="6"/>
  <path d="M38 38 L50 50" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round"/>
</svg>`;

const OG_SVG = `<svg width="1200" height="630" xmlns="http://www.w3.org/2000/svg">
  <rect width="1200" height="630" fill="#FAFAFA"/>
  <rect x="68" y="62" width="300" height="32" rx="16" fill="#4338CA"/>
  <text x="218" y="83" text-anchor="middle" font-family="${SANS}" font-size="14" font-weight="700" fill="#FFFFFF">OPEN SOURCE · MIT · FLUTTER</text>
  <text x="68" y="200" font-family="${MONO}" font-size="40" font-weight="700" fill="#111827">flutter_inspector_kit</text>
  <text x="68" y="280" font-family="${SANS}" font-size="30" font-weight="600" fill="#111827">Debug by following the chain,</text>
  <text x="68" y="322" font-family="${SANS}" font-size="30" font-weight="600" fill="#111827">not by poking points.</text>
  <text x="68" y="392" font-family="${SANS}" font-size="20" fill="#4B5563">Logs · Network · Navigator · Database — one timeline</text>
  <text x="68" y="540" font-family="${MONO}" font-size="18" fill="#4B5563">${SITE_META.baseUrl}</text>
</svg>`;

const shotPath = (id) => path.join(SRC_DIR, SCREENSHOTS[id]);

function buildRoundedMask(width, height, radius) {
  return Buffer.from(`<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
    <rect x="0" y="0" width="${width}" height="${height}" rx="${radius}" ry="${radius}" fill="#ffffff"/>
  </svg>`);
}

async function renderPhoneFrame(srcPath, width, height) {
  const innerW = width - 8;
  const innerH = height - 8;
  const screen = await sharp(srcPath)
    .resize(innerW, innerH, { fit: 'cover' })
    .ensureAlpha()
    .composite([{ input: buildRoundedMask(innerW, innerH, 16), blend: 'dest-in' }])
    .png()
    .toBuffer();
  const frame = `<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
    <rect x="0" y="0" width="${width}" height="${height}" rx="20" ry="20" fill="#1F2937" stroke="#4338CA" stroke-opacity="0.45" stroke-width="2"/>
  </svg>`;
  return sharp(Buffer.from(frame)).composite([{ input: screen, left: 4, top: 4 }]).png().toBuffer();
}

async function convertScreenshots() {
  await rm(OUT_DIR, { recursive: true, force: true }); // 先清空，避免改名後留下舊檔
  await mkdir(OUT_DIR, { recursive: true }); // recursive 會一併建立 public/
  let total = 0;
  for (const id of Object.keys(SCREENSHOTS)) {
    const info = await sharp(shotPath(id))
      .resize(SHOT_SIZE.width, SHOT_SIZE.height, { fit: 'cover' })
      .webp({ quality: WEBP_QUALITY, effort: 6 })
      .toFile(path.join(PUBLIC_DIR, shotSrc(id)));
    total += info.size;
    console.log(`${shotSrc(id)}: ${info.width}x${info.height}, ${info.size} B`);
  }
  console.log(`screenshots total: ${total} B`);
}

async function writeFavicon() {
  const info = await sharp(Buffer.from(ICON_SVG)).png().toFile(path.join(PUBLIC_DIR, SITE_META.faviconPath));
  console.log(`favicon.png: ${info.width}x${info.height}, ${info.size} B`);
}

async function writeOgCard() {
  const left = await renderPhoneFrame(shotPath('network'), 172, 372);
  const right = await renderPhoneFrame(shotPath('diagnostic-report'), 172, 372);
  const center = await renderPhoneFrame(shotPath('console'), 196, 426);
  const info = await sharp(Buffer.from(OG_SVG))
    .composite([
      { input: left, left: 650, top: 150 },
      { input: right, left: 974, top: 150 },
      { input: center, left: 800, top: 102 },
    ])
    .png({ compressionLevel: 9, palette: true, quality: 90, effort: 8 })
    .toFile(path.join(PUBLIC_DIR, SITE_META.ogImagePath));
  console.log(`og-card.png: ${info.width}x${info.height}, ${info.size} B`);
}

await convertScreenshots(); // 必須最先執行：它會建立 public/
await writeFavicon();
await writeOgCard();
```

ESM 的 top-level `await` 一旦 reject，Node 會以非 0 結束碼退出，不需要另外包 `main().catch`。

預算（單張 150 KB、總計 600 KB、og-card 450 KB）只在 T4 的 `verify-dist.test.mjs` 檢查一次，這支腳本不重複檢查。如果 T4 報預算超標（依 §2 實測不太可能），先把 `WEBP_QUALITY` 逐次降 5（下限 60），還是超過才把 `SHOT_SIZE` 降到 480×1067。**不要放寬上限。**

#### 步驟 3.4（綠）：產生素材並跑測試

```bash
cd website
npm run prepare:assets   # 印出 12 行 webp（每行 540x1200）、總量（預期約 370 KB，正式把關在 T4）、favicon、og-card；exit 0
npm test                 # 4 個測試全綠
```

#### 步驟 3.5：目視檢查

用圖片檢視器（或 Read 工具）開 `public/og-card.png` 和 `public/favicon.png`。確認文字沒有超出畫面、和右側手機框沒有重疊、三個手機框都有內容。如果文字和框重疊，調整 `OG_SVG` 的字級或 y 座標。

#### 驗收

```bash
cd website
npm run prepare:assets && npm test                       # 全綠
ls public/screenshots | wc -l                            # 12
cd ..
BASE="$(git merge-base HEAD origin/main)"
{ git diff --name-only "$BASE" -- website/src website/scripts website/public website/test; \
  git ls-files --others --exclude-standard -- website/src website/scripts website/public website/test; } | sort -u
# 期望恰好 17 行：src/data/site.ts、scripts/prepare-assets.mjs、test/site-data.test.mjs、
# public/favicon.png、public/og-card.png、public/screenshots/ 下 12 張 .webp
```

越界檢查依 §6：拿掉路徑參數再跑一次，只能多出 T1、T2 的檔案、本計畫和規格。

---

### Task 4：頁面與 dist 驗證（TDD）

**寫入**：`website/src/layouts/BaseLayout.astro`、`website/src/components/LandingPage.astro`、`website/src/styles/global.css`、`website/src/pages/index.astro`、`website/src/pages/zh-tw/index.astro`、`website/test/verify-dist.test.mjs`

#### 步驟 4.1（紅）：建立 `website/test/verify-dist.test.mjs`

```js
import assert from 'node:assert/strict';
import test from 'node:test';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { INSTALL, LOCALES, SCREENSHOTS, SITE_DATA, SITE_META, shotSrc } from '../src/data/site.ts';

const DIST = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'dist');
// 截圖與 og-card 的大小預算只在這裡檢查（唯一權威）；prepare-assets 只印數字
const MAX_SHOT_BYTES = 153_600; // 150 KB
const MAX_SHOTS_TOTAL_BYTES = 614_400; // 600 KB
const MAX_OG_BYTES = 460_800; // 450 KB

assert.ok(existsSync(DIST), 'website/dist/ 不存在：先跑 npm run build');

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const distPath = (webPath) => path.join(DIST, webPath.endsWith('/') ? `${webPath}index.html` : webPath);
const SHOT_PATHS = Object.keys(SCREENSHOTS).map(shotSrc);
const pages = LOCALES.map((locale) => ({
  locale,
  d: SITE_DATA[locale],
  html: readFileSync(distPath(SITE_DATA[locale].path), 'utf8'),
}));

test('每頁的 lang、canonical、hreflang、og:image 正確', () => {
  for (const { d, html } of pages) {
    assert.match(html, new RegExp(`<html[^>]+lang="${esc(d.htmlLang)}"`));
    assert.match(html, new RegExp(`<link[^>]+rel="canonical"[^>]+href="${esc(SITE_META.baseUrl + d.path)}"`));
    for (const other of LOCALES.map((l) => SITE_DATA[l])) {
      assert.match(
        html,
        new RegExp(`<link[^>]+hreflang="${esc(other.htmlLang)}"[^>]+href="${esc(SITE_META.baseUrl + other.path)}"`),
      );
    }
    assert.match(
      html,
      new RegExp(`<meta[^>]+property="og:image"[^>]+content="${esc(SITE_META.baseUrl + SITE_META.ogImagePath)}"`),
    );
  }
});

test('安裝指令在頁面上，且沒有寫死版本號', () => {
  for (const { locale, html } of pages) {
    assert.ok(html.includes(INSTALL.addCommand), `${locale} 缺安裝指令`);
    assert.doesNotMatch(html, /flutter_inspector_kit:\s*\^?\d/, `${locale} 出現寫死的版本約束`);
  }
});

test('站內連結、錨點、截圖引用與 img alt 都成立', () => {
  for (const { locale, html } of pages) {
    for (const [, ref] of html.matchAll(/(?:href|src)="(\/[^"#]*)"/g)) {
      assert.ok(existsSync(distPath(ref)), `${locale}: ${ref} 不存在於 dist/`);
    }
    const ids = new Set(Array.from(html.matchAll(/\bid="([^"]+)"/g), (m) => m[1]));
    for (const [, anchor] of html.matchAll(/href="#([^"]+)"/g)) {
      assert.ok(ids.has(anchor), `${locale}: 錨點 #${anchor} 沒有對應的 id`);
    }
    for (const shot of SHOT_PATHS) {
      assert.ok(html.includes(shot), `${locale}: 沒有引用 ${shot}`);
    }
    for (const [tag] of html.matchAll(/<img\b[^>]*>/g)) {
      assert.match(tag, /\salt="/, `${locale}: <img> 缺 alt：${tag}`);
    }
  }
});

test('dist 的截圖目錄恰好是 12 張 WebP 且在預算內；og-card 在預算內', () => {
  const dir = path.join(DIST, path.dirname(SHOT_PATHS[0]));
  const names = readdirSync(dir).sort();
  assert.deepEqual(names, SHOT_PATHS.map((p) => path.basename(p)).sort());
  let total = 0;
  for (const name of names) {
    const buf = readFileSync(path.join(dir, name));
    assert.equal(buf.subarray(0, 4).toString('ascii'), 'RIFF', name);
    assert.equal(buf.subarray(8, 12).toString('ascii'), 'WEBP', name);
    assert.ok(buf.byteLength <= MAX_SHOT_BYTES, `${name} ${buf.byteLength} B 超過 150 KB`);
    total += buf.byteLength;
  }
  assert.ok(total <= MAX_SHOTS_TOTAL_BYTES, `截圖總計 ${total} B 超過 600 KB`);
  assert.ok(statSync(distPath(SITE_META.ogImagePath)).size <= MAX_OG_BYTES, 'og-card.png 超過 450 KB');
});
```

```bash
cd website && npm test   # 預期紅：verify-dist 在載入時就失敗（dist/ 不存在）
```

#### 步驟 4.2：建立 `website/src/layouts/BaseLayout.astro`

```astro
---
import '../styles/global.css';
import { LOCALES, SITE_DATA, SITE_META, type Locale } from '../data/site';

interface Props {
  locale: Locale;
}

const { locale } = Astro.props;
const d = SITE_DATA[locale];
const abs = (p: string) => `${SITE_META.baseUrl}${p}`;
---

<!doctype html>
<html lang={d.htmlLang}>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{d.seo.title}</title>
    <meta name="description" content={d.seo.description} />
    <link rel="icon" type="image/png" href={SITE_META.faviconPath} />
    <link rel="canonical" href={abs(d.path)} />
    {LOCALES.map((l) => <link rel="alternate" hreflang={SITE_DATA[l].htmlLang} href={abs(SITE_DATA[l].path)} />)}
    <link rel="alternate" hreflang="x-default" href={abs(SITE_DATA.en.path)} />

    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="flutter_inspector_kit" />
    <meta property="og:title" content={d.seo.title} />
    <meta property="og:description" content={d.seo.description} />
    <meta property="og:url" content={abs(d.path)} />
    <meta property="og:locale" content={d.ogLocale} />
    <meta property="og:image" content={abs(SITE_META.ogImagePath)} />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:image:alt" content={d.seo.ogImageAlt} />
    <meta name="twitter:card" content="summary_large_image" />
  </head>
  <body>
    <a class="skip-link" href="#main">{d.ui.skipToContent}</a>
    <slot />
  </body>
</html>
```

#### 步驟 4.3：建立 `website/src/components/LandingPage.astro`

語言切換器在 header 與 footer 各出現一次，markup 相同。這段只有 6 行，不另外抽元件。footer 那份用 `role="group"`，避免頁面上出現兩個 `<nav>` landmark（參考 repo 的做法）。

```astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
import { INSTALL, LOCALES, SHOT_SIZE, SITE_DATA, SITE_META, shotSrc, type Locale } from '../data/site';

interface Props {
  locale: Locale;
}

const { locale } = Astro.props;
const d = SITE_DATA[locale];
---

<BaseLayout locale={locale}>
  <header class="bar">
    <div class="wrap bar-inner">
      <a class="brand" href={d.path}>
        <img src={SITE_META.faviconPath} alt="" width="28" height="28" />
        <span>flutter_inspector_kit</span>
      </a>
      <div class="bar-actions">
        <a href={SITE_META.repoUrl} target="_blank" rel="noopener noreferrer">{d.ui.github}</a>
        <nav class="lang-switch" aria-label={d.ui.langSwitch}>
          {LOCALES.map((l) => (
            <a href={SITE_DATA[l].path} lang={SITE_DATA[l].htmlLang} aria-current={l === locale ? 'page' : undefined}>
              {SITE_DATA[l].langName}
            </a>
          ))}
        </nav>
      </div>
    </div>
  </header>

  <main id="main">
    <section class="hero">
      <div class="wrap split">
        <div>
          <h1>{d.hero.title}</h1>
          <p class="lead">{d.hero.lead}</p>
          <pre class="cmd"><code>{INSTALL.addCommand}</code></pre>
          <div class="cta">
            <a class="btn primary" href={SITE_META.pubUrl} target="_blank" rel="noopener noreferrer">{d.ui.pub}</a>
            <a class="btn" href={SITE_META.repoUrl} target="_blank" rel="noopener noreferrer">{d.ui.github}</a>
          </div>
        </div>
        <div class="shots">
          <img
            class="shot"
            src={shotSrc(d.hero.shot.id)}
            alt={d.hero.shot.alt}
            width={SHOT_SIZE.width}
            height={SHOT_SIZE.height}
            fetchpriority="high"
          />
        </div>
      </div>
    </section>

    {d.sections.map((s, i) => (
      <section class="feature" id={s.id}>
        <div class="wrap split">
          <div>
            <p class="eyebrow">{String(i + 1).padStart(2, '0')}</p>
            <h2>{s.title}</h2>
            <p class="lead">{s.lead}</p>
            <ul class="points">{s.points.map((p) => <li>{p}</li>)}</ul>
          </div>
          <div class="shots">
            {s.shots.map((shot) => (
              <img
                class="shot"
                src={shotSrc(shot.id)}
                alt={shot.alt}
                width={SHOT_SIZE.width}
                height={SHOT_SIZE.height}
                loading="lazy"
                decoding="async"
              />
            ))}
          </div>
        </div>
      </section>
    ))}

    <section class="pledges" id="pledges">
      <div class="wrap">
        <h2>{d.pledges.title}</h2>
        <p class="lead">{d.pledges.lead}</p>
        <div class="cards">
          {d.pledges.items.map((p) => (
            <article class="card">
              <h3>{p.title}</h3>
              <p>{p.detail}</p>
            </article>
          ))}
        </div>
      </div>
    </section>

    <section class="install" id="install">
      <div class="wrap">
        <h2>{d.install.title}</h2>
        <p class="lead">{d.install.lead}</p>
        <h3>{d.install.addStep}</h3>
        <pre class="cmd"><code>{INSTALL.addCommand}</code></pre>
        <p class="note">
          {d.install.androidNote}{' '}
          <a href={SITE_META.androidSetupUrl} target="_blank" rel="noopener noreferrer">{d.install.androidLink}</a>
        </p>
        <h3>{d.install.initStep}</h3>
        <pre><code>{INSTALL.initSnippet}</code></pre>
        <p class="note">{d.install.note}</p>
        <a class="btn" href={d.readmeUrl} target="_blank" rel="noopener noreferrer">{d.ui.readme}</a>
      </div>
    </section>
  </main>

  <footer class="foot">
    <div class="wrap foot-inner">
      <span>{d.footer.tagline}</span>
      <div class="foot-links">
        <a href={SITE_META.licenseUrl} target="_blank" rel="noopener noreferrer">{d.ui.license}</a>
        <a href={SITE_META.repoUrl} target="_blank" rel="noopener noreferrer">{d.ui.github}</a>
        <a href={SITE_META.pubUrl} target="_blank" rel="noopener noreferrer">{d.ui.pub}</a>
        <a href={SITE_META.issuesUrl} target="_blank" rel="noopener noreferrer">{d.ui.issues}</a>
        <div class="lang-switch" role="group" aria-label={d.ui.langSwitch}>
          {LOCALES.map((l) => (
            <a href={SITE_DATA[l].path} lang={SITE_DATA[l].htmlLang} aria-current={l === locale ? 'page' : undefined}>
              {SITE_DATA[l].langName}
            </a>
          ))}
        </div>
      </div>
    </div>
  </footer>
</BaseLayout>
```

#### 步驟 4.4：建立兩個入口頁

`website/src/pages/index.astro`：

```astro
---
import LandingPage from '../components/LandingPage.astro';
---

<LandingPage locale="en" />
```

`website/src/pages/zh-tw/index.astro`：

```astro
---
import LandingPage from '../../components/LandingPage.astro';
---

<LandingPage locale="zh-tw" />
```

#### 步驟 4.5：建立 `website/src/styles/global.css`

以下是起始版本。配色、字型、間距可以依規格 §7 調整，但有兩條必須保留：grid 欄寬一律用 `minmax(0, …)`，避免長字串把版面撐破；`.shot` 必須保持 `height: auto`，搭配 `<img width height>` 才不會造成版面位移（CLS）。

```css
:root {
  color-scheme: light dark;
  --bg: #fafafa;
  --surface: #ffffff;
  --ink: #111827;
  --muted: #4b5563;
  --accent: #4338ca;
  --on-accent: #ffffff;
  --border: rgba(17, 24, 39, 0.12);
  --code-bg: #0f172a;
  --code-ink: #e2e8f0;
  --frame: #1f2937;
  --max-w: 1120px;
  --font-sans: ui-sans-serif, system-ui, -apple-system, 'Segoe UI', 'PingFang TC', 'Noto Sans TC', sans-serif;
  --font-mono: ui-monospace, 'SF Mono', Menlo, Consolas, monospace;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0b0f19;
    --surface: #111827;
    --ink: #f3f4f6;
    --muted: #9ca3af;
    --accent: #a5b4fc;
    --on-accent: #111827;
    --border: rgba(243, 244, 246, 0.14);
    --code-bg: #020617;
    --frame: #374151;
  }
}

*, *::before, *::after { box-sizing: border-box; }
html { background: var(--bg); color: var(--ink); font-family: var(--font-sans); line-height: 1.65; }
@media (prefers-reduced-motion: no-preference) { html { scroll-behavior: smooth; } }
body { margin: 0; }
a { color: var(--accent); text-underline-offset: 3px; }
a:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }

.skip-link { position: absolute; left: 1rem; top: -4rem; padding: 0.5rem 1rem; background: var(--surface); z-index: 20; }
.skip-link:focus { top: 1rem; }
.wrap { max-width: var(--max-w); margin: 0 auto; padding: 0 1.25rem; }

.bar { position: sticky; top: 0; z-index: 10; background: color-mix(in srgb, var(--bg) 88%, transparent); backdrop-filter: blur(8px); border-bottom: 1px solid var(--border); }
.bar-inner { display: flex; align-items: center; justify-content: space-between; gap: 1rem; min-height: 3.5rem; }
.brand { display: inline-flex; align-items: center; gap: 0.5rem; font-family: var(--font-mono); font-weight: 600; color: var(--ink); text-decoration: none; }
.bar-actions, .lang-switch, .cta, .foot-links { display: flex; flex-wrap: wrap; align-items: center; gap: 0.75rem; }
.lang-switch a[aria-current='page'] { color: var(--ink); font-weight: 700; text-decoration: none; }

.hero, .feature, .pledges, .install { padding: 5rem 0; border-bottom: 1px solid var(--border); }
.split { display: grid; grid-template-columns: minmax(0, 5fr) minmax(0, 7fr); gap: 3rem; align-items: center; }
h1 { font-size: clamp(2rem, 5vw, 3.25rem); line-height: 1.15; margin: 0 0 1rem; }
h2 { font-size: clamp(1.5rem, 3vw, 2.25rem); line-height: 1.2; margin: 0 0 0.75rem; }
.lead { color: var(--muted); font-size: 1.125rem; max-width: 40rem; }
.eyebrow { margin: 0 0 0.5rem; font-family: var(--font-mono); color: var(--accent); }
.points { padding-left: 1.2rem; }
.points li + li { margin-top: 0.4rem; }

.shots { display: flex; gap: 1rem; justify-content: center; }
.shot { flex: 0 1 240px; min-width: 0; width: 100%; height: auto; border: 6px solid var(--frame); border-radius: 28px; background: var(--frame); box-shadow: 0 18px 40px rgba(0, 0, 0, 0.18); }

.btn { display: inline-block; padding: 0.6rem 1.1rem; border: 1px solid var(--border); border-radius: 999px; font-weight: 600; text-decoration: none; }
.btn.primary { background: var(--accent); color: var(--on-accent); border-color: transparent; }
pre { margin: 1rem 0; padding: 1rem 1.25rem; overflow-x: auto; border-radius: 12px; background: var(--code-bg); color: var(--code-ink); font: 0.9rem/1.6 var(--font-mono); }

.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 16rem), 1fr)); gap: 1rem; margin-top: 2rem; }
.card { padding: 1.5rem; border: 1px solid var(--border); border-radius: 16px; background: var(--surface); }
.card h3 { margin-top: 0; }
.note { color: var(--muted); }

.foot { padding: 2.5rem 0; color: var(--muted); font-size: 0.95rem; }
.foot-inner { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 1rem; }

@media (max-width: 860px) {
  .split { grid-template-columns: minmax(0, 1fr); }
  .shots { justify-content: flex-start; overflow-x: auto; padding-bottom: 0.5rem; }
  .shot { flex: 0 0 180px; }
}
```

#### 步驟 4.6（綠）：建置並驗證

```bash
cd website
npm run build   # exit 0；輸出 dist/index.html 與 dist/zh-tw/index.html
npm test        # site-data 4 個 + verify-dist 4 個，全綠
```

#### 驗收

```bash
cd website
npm run build && npm test                   # 全綠
grep -c '<script' dist/index.html           # 期望 0（零 client JS）
du -sh dist                                 # 參考值：約 0.5 MB 以下
cd ..
BASE="$(git merge-base HEAD origin/main)"
{ git diff --name-only "$BASE" -- website/src/layouts website/src/components website/src/styles website/src/pages website/test/verify-dist.test.mjs; \
  git ls-files --others --exclude-standard -- website/src/layouts website/src/components website/src/styles website/src/pages website/test/verify-dist.test.mjs; } | sort -u
# 期望恰好 6 行：BaseLayout.astro、LandingPage.astro、global.css、pages/index.astro、pages/zh-tw/index.astro、verify-dist.test.mjs
```

越界檢查依 §6。目視檢查不在本任務，由主對話在 §7 執行。

---

## 7. 整體驗收（STAGE 2 收尾，非獨立任務）

| 規格條目 | 覆蓋 |
|:---|:---|
| §2 目標：雙語單頁 | verify-dist「lang／canonical／hreflang」 |
| §2 目標：12 張截圖 | site-data「每張恰用一次」+ verify-dist「恰好 12 張 WebP」 |
| §2 目標：CI | T2 驗收：workflow 與本計畫 `yaml` 區塊 `diff`，加上 actionlint |
| §2 反目標：被打包進套件 | 下方 dry-run |
| §2 反目標：第 5 處版本號 | site-data「文案不含版本號」+ verify-dist「沒有寫死版本號」 |
| §2 反目標：開 Blaze | 只用 Firebase Hosting（Spark 可用）；部署指令 `--only hosting` |
| §5.6 驗證 | `npm test` 兩支測試 |
| 文案和 README 的必要設定不矛盾 | 安裝段的 Android desugaring 提示（§4 A10），加上下方第 5 步人工對照 |

```bash
# 1. 網站（從乾淨的 node_modules 開始）
cd website && rm -rf node_modules dist && npm ci && npm run build && npm test && cd ..

# 2. 套件打包（commit 之後跑）
dart pub publish --dry-run 2>&1 | grep -cE '── (website|\.github)'   # 0
dart pub publish --dry-run 2>&1 | tail -1                              # Package has 0 warnings.

# 3. Flutter 側沒有被碰到
git diff --name-only "$(git merge-base HEAD origin/main)" -- lib test pubspec.yaml   # 無輸出
flutter analyze lib/ test/                                                          # 仍是 7 個既有 info
```

`lib/`、`test/` 沒有任何變動，所以不需要跑 `flutter test`。`flutter analyze` 只用來確認基準沒變。

**4. 目視檢查（主對話執行，修訂 1 從 T4 移過來）**：先 `cd website && npm run preview`，再用 Playwright 或 chrome-devtools MCP 對 `/` 和 `/zh-tw/` 各截以下 4 張圖：

| 視窗寬度 | 色彩模式 | 要看的重點 |
|:---|:---|:---|
| 1280 px | light | 版面、截圖外框、整頁不出現橫向捲軸 |
| 1280 px | dark（emulate `prefers-color-scheme: dark`） | 對比、文字可讀 |
| 390 px | light | 單欄排版；截圖列只在 `.shots` 內部橫向捲動 |
| 390 px | dark | 同上 |

截圖時也確認語言切換連結正確、按 Tab 會出現 skip link、og-card 與 favicon 的外觀。如果沒有可用的瀏覽器 MCP，改在 STAGE 2 完成的暫停點，請使用者開 preview 人工確認，並把結果寫進暫停摘要。

**5. 文案對照（主對話或 reviewer 執行）**：依 T3 步驟 3.2 的出處清單逐條對照。安裝段要對照 `README.md:510-532`，因為 `README.zh-TW.md` 沒有這段。

> **事前實測（planner，2026-11-24，Node v26.13.1，scratchpad 副本，未安裝任何 npm 套件；修訂 1 後重跑）**：
> - 本計畫的 `site.ts` 與 `site-data.test.mjs` 原樣抽出後跑 `node --test`。public/ 是空的時候，形狀、https、版本號 3 個測試綠，截圖測試紅（和步驟 3.2 的預期一致）。補上 14 個空檔後 4/4 綠。
> - 突變測試：刪掉一條 zh-tw point，形狀測試轉紅；在 tagline 塞入 `3.1.0`，版本號測試轉紅。
> - T2 的 `yaml` 區塊和參考 repo 的 workflow 經 `sed` 換 project id 後做 `diff`，無輸出。`tsconfig.json`、`.gitignore`、`firebase.json` 三個區塊由 planner 從參考 repo 逐字抄入，也逐一 `diff` 過，無輸出。和參考 repo 的比對只由 planner 或主對話進行，implementer 只和本計畫比對。
> - `verify-dist.test.mjs` 和 `.astro` 檔需要 Astro 建置，沒有事前實跑，由 T4 步驟 4.6 驗證。

---

## 8. 風險與已知限制

| # | 風險 | 處置 |
|:-:|:---|:---|
| R1 | WebP 超出 600 KB 總預算 | 已用 libwebp 實測：540×1200 q78 約 370 KB（餘裕 38%）。sharp 底層也是 libwebp，數字應該接近。超出時的降級順序寫在 T3 步驟 3.3；上限不能放寬 |
| R2 | Node 版本過舊，無法直接 `import` `.ts` | `engines` 設為 `^22.23.4 || >=24.0.0`（astro CLI 下限，已涵蓋 type stripping 的 22.18.0；排除 23.0–23.5）；CI 用 Node 24；`site.ts` 只用可抹除語法（§3.1） |
| R3 | 換截圖後網站沒更新 | CI 的 `paths` 監看 `doc/screenshots/**`（PR #262 review 後新增，偏離參考 repo）。`test/assets-fresh.test.mjs` 做兩件事：比對 `website/assets-source.json`（`prepare:assets` 寫入的來源 PNG SHA-256）與目前 `doc/screenshots/`，以及來源 PNG 與已提交 WebP 的像素差異。只改截圖而沒重跑 `npm run prepare:assets` 並 commit `website/assets-source.json` 與 `website/public/` 時 CI 會失敗。CI 不重新產生 WebP（不同平台編碼輸出不保證逐位元相同）。`/screenshots/**` 快取降為 1 天，換圖後最多 1 天內生效 |
| R4 | og-card 的字型在不同機器上渲染結果不同 | og-card 在本機產生一次後 commit，CI 不重新產生；T3 步驟 3.5 目視檢查 |
| R5 | 第一支 workflow 進 repo | secret 還沒設定前，部署步驟會跳過並寫 step summary，CI 不會失敗；PR 只做 build 和驗證 |
| R6 | 本機 Firebase CLI 的 active project 是別的專案 | `.firebaserc` 設 default，手動部署一律加 `--project flutterinspectorkit`（規格 §6） |
| R7 | `/zh-tw`（沒有結尾斜線）的行為 | `firebase.json` 與參考 repo 相同，也沒設 `trailingSlash`；站內連結一律用 `/zh-tw/` |
| R8 | Spark 方案每天 360 MB 頻寬 | 一次完整瀏覽約 0.4 MB（截圖 lazy load、零 JS），約可支撐每天 900 次完整瀏覽，第一版足夠 |
| R9 | `npm install` 會解析 `^` 範圍內的最新版本，lockfile 可能和參考 repo 不同 | T2 用 `npm ci` 重跑確認可重現；T4 的 `npm run build` 確認新版本能建置 |
| R10 | 文案宣稱和 README 不一致，或漏掉 README 的必要設定 | T3 附出處清單。對照範圍是 README.md 的 Features 表**和 Usage 段**，至少包含 `README.md:59-115`（安裝與初始化）和 `README.md:510-532`（Android desugaring，不論是否開啟通知都必須設定，否則無法 build）。`README.zh-TW.md` 缺的段落，中文文案一律對照英文 README。§7 第 5 步做最後一次對照 |
| R11 | Android setup 錨點（`#live-notification-opt-in`）在 README 標題改名後失效 | 只會落到 README 頂端，不會 404；`site.ts` 有 shortcut 註解，標明改名時要同步更新 |

未處理（YAGNI）：複製按鈕、client JS、JSON-LD、theme-color、sitemap、自訂網域、Analytics、從 README 連到網站、CLAUDE.md 指令段補 website 指令。

---

## 9. 使用者手動步驟（照規格 §6，不屬於任何任務）

1. 在 GCP 為 `flutterinspectorkit` 建立 service account，授予 `roles/firebasehosting.admin`，建議另外授予 `roles/serviceusage.apiKeysViewer`。
2. 把 JSON 金鑰存成 GitHub repo secret `FIREBASE_SERVICE_ACCOUNT_JSON`。
3. 在那之前，可以本機手動部署：`cd website && npx firebase-tools deploy --only hosting --project flutterinspectorkit`。
4. **部署後檢查**（CI 部署或手動部署之後都要做）：

   ```bash
   curl -sI https://flutterinspectorkit.web.app/       | head -1   # HTTP/2 200
   curl -sI https://flutterinspectorkit.web.app/zh-tw/ | head -1   # HTTP/2 200
   ```

---

## 10. 執行方式

1. **Subagent-driven（建議）**：同一個 session 依 SKILL.md STAGE 2 執行，`total_tasks=4`，全部序列。
   - T1：主進程原地改 `.pubignore`（🛑 微任務煞車），**立即 commit**。
   - T2：派發給 1 個 implementer（快/便宜 tier）。計畫裡已寫好所有檔案的全文，不需要讀取 worktree 以外的檔案。
   - T3：派發給 1 個 implementer（標準 tier）。
   - T4：派發給 1 個 implementer（標準 tier）。
   - 每個任務都由 verifier 依該任務的「驗收」段落和 §6 範圍驗收規則做兩階段驗收。全部完成後，主對話跑 §7，包含目視檢查與文案對照。
2. **Parallel session**：在另一個獨立 session 依序跑 T1 → T4，適合想人工逐步盯的情況。本計畫是純序列，同時開兩個寫入者不會變快，反而會在同一個 worktree 裡產生並行 commit，**不建議**。

---

## 11. 修訂紀錄

**修訂 1（回應 plan-verifier 初審 REVISE）**

| 項目 | 修改 | 位置 |
|:---|:---|:---|
| B1-1 | 安裝段新增 `androidNote`／`androidLink`（中英）：Android 必須啟用 core library desugaring，不論是否開啟通知。連到新欄位 `SITE_META.androidSetupUrl`，也就是英文 README 的 `#live-notification-opt-in`，中英都連這裡。中文另外註明說明只有英文版。不寫 `desugar_jdk_libs` 的版本 | §3.1、§4 A10、T3 `site.ts`、T4 `LandingPage.astro` |
| B1-2 | 標題「Two steps to start／兩步開始」改為「Get started／開始使用」；lead 補上 Android 建置選項 | T3 `site.ts` |
| B1-3 | `pledges.lead` 改成「不該左右 App 架構」，不再暗示完全不影響建置 | T3 `site.ts` |
| B1-4 | 出處清單與 R10 的對照範圍擴大到 README Usage（`README.md:59-115`、`README.md:510-532`），並註明 zh README 缺的段落要對照英文 README；§4 A8 同步 | T3 出處清單、§4 A8、§8 R10、§7 第 5 步 |
| B2 | T2 不再從參考 repo `cp`。`tsconfig.json`、`.gitignore`、`firebase.json` 全文寫進計畫；workflow 驗收改成和本計畫的 `yaml` 區塊 `diff`；和參考 repo 的比對註明為 planner 事前實測 | T2、§7 事前實測 |
| M1 | 時間軸 filter chip 文案刪掉「不會丟失目前位置／without losing your place」（README 把這句話歸給書籤功能） | T3 `site.ts` |
| M2 | 原 T5（workflow）併入 T2；T1 由主進程先 commit；`total_tasks` 從 5 改為 4，全部序列執行；§5 #19 的任務欄改為 T2 | §5、§6、T1、T2、§10 |
| M3 | 刪掉 T4 步驟 4.7，目視檢查移到 §7 第 4 步，由主對話用 Playwright 或 chrome-devtools 截 1280／390 px × light／dark，沒有可用工具時改在暫停點請使用者確認 | T4、§7 |
| M4 | T3、T4 的範圍驗收改用 `$BASE` 的 `git diff --name-only` 加 `git ls-files --others`，並寫出預期的檔案數（17／6） | T3、T4 驗收 |
| L1 | prepare-assets 與 verify-dist 的截圖路徑一律由 `shotSrc(id)` 推出；註明 verify-dist 是預算的唯一權威 | T3 步驟 3.3、T4 步驟 4.1 |
| L2 | 刪除 `if (ref.startsWith('//')) continue;`、og-card 尺寸檢查、多餘的 `mkdir(PUBLIC_DIR)`；prepare-assets 也不再重複檢查預算（交給 verify-dist） | T3 步驟 3.3、T4 步驟 4.1 |
| L4 | T2 新增步驟 2.9：CLAUDE.md §3「無 CI 機制」那一行改寫為「Flutter 側仍無 CI，唯一的 workflow 只管 website/」；§5 新增 #20 | T2、§5 |
| L5 | §9 新增部署後檢查：`curl -sI` 確認 `/` 和 `/zh-tw/` 回 200 | §9 |
| L3 | 未處理（verifier 標為選填） | — |
