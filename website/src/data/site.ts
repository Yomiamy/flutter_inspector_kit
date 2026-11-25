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
          'Replay a captured call through the original Dio instance (pass it to the interceptor as sourceDio): same headers, base URL and interceptors',
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
        lead: 'Route changes and database operations sit on the same timeline as the requests around them, and your key-value stores have a tab of their own.',
        points: [
          'Switch between navigation history and the live route stack; each event keeps the params and args its route was opened with',
          'Record insert, update, delete and query operations; browse real SQLite or ObjectBox tables by registering your own DatabaseBrowserSource adapter',
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
          {
            id: 'layout-inspect-loupe',
            alt: 'Magnifier and crosshair aiming at a button, with a card showing its size, constraints and offset',
          },
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
          'Opt-in capture of uncaught errors turns them into error logs and never swallows them',
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
          detail: 'Authorization, Cookie, Set-Cookie and X-Api-Key headers, plus route parameters such as token, password, pin and apiKey, are masked in every share and export.',
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
          '將 Dio 以 sourceDio 傳給 interceptor 後，即可透過原本的 Dio 實例重送已擷取的請求，沿用相同的 headers、base URL 與 interceptors',
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
        lead: '頁面切換與資料庫操作，和它們前後的請求排在同一條時間軸上；key-value 儲存則有自己的分頁。',
        points: [
          '在導航事件歷史與即時 route stack 之間切換；每個事件都記錄開啟該 route 時帶的 Params 與 Args',
          '記錄 insert、update、delete、query 操作；註冊自己實作的 DatabaseBrowserSource adapter，即可瀏覽 SQLite 或 ObjectBox 的真實資料表',
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
          {
            id: 'layout-inspect-loupe',
            alt: '放大鏡與十字準星瞄準一顆按鈕，卡片列出它的尺寸、constraints 與 offset',
          },
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
          'opt-in 的錯誤擷取會把未捕捉的錯誤轉成 error log，絕不吞掉錯誤',
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
          detail: 'Authorization、Cookie、Set-Cookie 與 X-Api-Key 這幾個 header，以及 token、password、pin、apiKey 等路由參數，在每一條分享與匯出路徑上都會被遮罩。',
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
