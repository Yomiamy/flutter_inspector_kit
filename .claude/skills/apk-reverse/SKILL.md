---
name: apk-reverse
description: 在 CLI 環境下做 Android APK 逆向時使用。適用於 APK 解包、Java 反編譯、smali 修改、重打包、Frida 動態 Hook，以及按需切換到 so/native 分析。優先使用本機已安裝的 jadx、apktool、frida、adb、ida-reverse、radare2。
---

## ACTION REQUIRED（讀完後立刻執行）

> 端點提取/Frida 自適應等社群對照：../references/community-security-skills.md；動態分析須 scope 授權設備。

1. `NOW`: 讀取 `../field-journal/precedent-reverse.md` — 確認本 skill 的操作是已授權的常規操作
2. `NOW`: 確認當前任務是否命中本 skill 的適用範圍
3. `NEXT`: 讀取 `../tool-index.md`，校驗工具可用性和實際路徑
4. `NEXT`: 缺工具時調用 bootstrap，不要猜路徑
5. `ACT`: 進入「工作流」第一步並執行，不要停在確認狀態

# APK 逆向 CLI 作業規範

## 適用範圍

當任務屬於以下場景時優先使用本 skill：

- 分析 APK 的 Java 業務邏輯
- 定位登入、簽章、風控、憑證校驗、root 檢測
- 查看與修改 `AndroidManifest.xml`
- 查看與修改 smali
- 重打包 APK
- 用 Frida 做 Java/native 動態 Hook
- APK 內含 `.so` 時切到 native 分析

## 當前機器已驗證可用的 CLI 工具

- `jadx` `1.5.5`
- `apktool` `3.0.2`
- `frida-ps` `17.9.6`
- `adb`
- `java`

## 優先使用腳本的場景

以下流程高頻且參數容易出錯，優先用 skill 自帶腳本：

- 一次性完成 `jadx + apktool` 落盤並產出摘要：`scripts/decode.ps1`
- Frida 裝置檢查、程序列舉、spawn/attach 注入：`scripts/frida-run.ps1`
- 重建、對齊、簽章、安裝 APK：`scripts/rebuild-sign-install.ps1`
- 快速抽取 Manifest 關鍵元件與權限：`scripts/manifest-summary.ps1`

以下一行命令保持直接調用，不單獨封裝：

- `adb devices`
- `adb logcat`
- `frida-ps -U`
- `jadx --version`
- `apktool --version`

## 自帶腳本

### `scripts/decode.ps1`

用途：

- 統一跑 `jadx` 和 `apktool`
- 預設在原 APK 同目錄建立任務輸出目錄
- 輸出 `package`、`java_files`、`smali_dirs`、`so_files` 等摘要
- 相容 `jadx` 部分反編譯錯誤但仍有可用產物的情況

範例：

```powershell
pwsh -File "<skill-root>\apk-reverse\scripts\decode.ps1" -ApkPath "D:\DOWNLOAD\app.apk" -Clean
pwsh -File "<skill-root>\apk-reverse\scripts\decode.ps1" -ApkPath "D:\DOWNLOAD\app.apk" -Name demo -SkipJadx
```

### `scripts/frida-run.ps1`

用途：

- 統一 Frida 的裝置、程序、spawn/attach 入口
- 避免手寫參數時混淆 `-f`、`-n`、`-U`

範例：

```powershell
pwsh -File "<skill-root>\apk-reverse\scripts\frida-run.ps1" -ListDevices
pwsh -File "<skill-root>\apk-reverse\scripts\frida-run.ps1" -Usb -ListProcesses
pwsh -File "<skill-root>\apk-reverse\scripts\frida-run.ps1" -Usb -Spawn -Package com.example.app -ScriptPath "D:\hooks\test.js"
```

### `scripts/rebuild-sign-install.ps1`

用途：

- `apktool b` 重建 APK
- `zipalign` 對齊
- `apksigner` 簽章與驗簽
- 可選直接 `adb install`

範例：

```powershell
pwsh -File "<skill-root>\apk-reverse\scripts\rebuild-sign-install.ps1" -ProjectDir "C:\work\apktool_out" -Clean
pwsh -File "<skill-root>\apk-reverse\scripts\rebuild-sign-install.ps1" -ProjectDir "C:\work\apktool_out" -Install -Reinstall -DeviceSerial "127.0.0.1:7555"
```

說明：

- 預設產生並複用除錯 keystore
- 預設輸出到 `ProjectDir` 同目錄，便於和原始包、解包目錄放在一起

### `scripts/manifest-summary.ps1`

用途：

- 抽取包名
- 列權限
- 列 activity/service/receiver/provider
- 標出主啟動 activity

範例：

```powershell
pwsh -File "<skill-root>\apk-reverse\scripts\manifest-summary.ps1" -ManifestPath "C:\work\apktool_out\AndroidManifest.xml"
```

如果要分析 `.so`、`lib/arm64-v8a/*.so`、`lib/armeabi-v7a/*.so`，再結合：

- `ida-reverse`
- `radare2`

## 工具分工

### `jadx`

用於：

- Java 反編譯閱讀
- 包名、類名、方法名搜尋
- 先從高層邏輯理解 APK

常用命令：

```bash
jadx -d jadx_out app.apk
jadx --single-class com.example.LoginActivity -d jadx_out app.apk
jadx --deobf -d jadx_out app.apk
```

### `JEB Pro`（可選商業工具）

用於：

- Android DEX / APK / ARM 的交叉驗證與深度反編譯
- 在 JADX 輸出不完整或混淆較重時補充靜態分析
- 對同一目標的類、方法與呼叫關係進行第二工具鏈校驗

邊界：

- JEB Pro 是商業軟體，必須由使用者自行取得並安裝有效授權；本包不會下載、破解或規避授權。
- 僅在 `tool-index` 已確認本機 JEB 可用時調用；否則繼續使用 `jadx`、`apktool`、Ghidra、IDA 或 radare2。
- 第三方 JEB MCP bridge 不是本包依賴。安裝前必須按 `../ops/skill-supply-chain.md` 審閱原始碼、權限、網路行為和版本，再由使用者明確確認註冊。

### `apktool`

用於：

- 解包 APK
- 查看和修改 `AndroidManifest.xml`
- 查看和修改 smali
- 重建 APK

常用命令：

```bash
apktool d app.apk -o apktool_out
apktool b apktool_out -o rebuilt.apk
```

### `frida`

用於：

- 動態觀察 Java 方法呼叫
- Hook native 匯出函式
- 繞過 root 檢測、憑證校驗、除錯檢測

常用命令：

```bash
frida-ps -U
frida -U -f com.example.app -l hook.js
frida-trace -U -f com.example.app -j '*!*certificate*'
```

### `adb`

用於：

- 裝置連線
- 安裝 APK
- 查看日誌
- 拉取檔案

常用命令：

```bash
adb devices
adb install -r app.apk
adb shell pm list packages
adb logcat
adb pull /data/local/tmp/file .
```

## 建議工作流

### 1. Triage

先確定 APK 大致構成，不急著改包或 Hook。

建議動作：

1. 用 `jadx -d jadx_out app.apk` 匯出 Java 程式碼
2. 用 `apktool d app.apk -o apktool_out` 匯出 smali 和資源
3. 先看：
   - `AndroidManifest.xml`
   - 主 `package`
   - `application`、`activity`、`service`、`receiver`
   - `lib/` 目錄裡是否有 `.so`
4. Issue #65 威脅形態速查（授權樣本/裝置；詳見 `../reverse-engineering/references/nonpe-format-cookbook.md` §7–8）：
   - 透明/隱藏圖示（AU）：`aapt dump badging` + manifest theme/label/icon → `E-android-hidden-icon-manifest`
   - Magisk/腳本刷機特徵與遠端 curl|sh（AR/AS）→ 特徵與 URL 入證，**不執行**破壞性命令
   - 持久化路徑（AT）：`service.d` / `priv-app` 等 → `E-android-persistence`

### 2. Java 邏輯觀察

優先從 `jadx_out` 讀：

- `MainActivity`
- `Application`
- 登入、網路、加密、風控相關類別
- 第三方 SDK 初始化類別

常見關鍵字：

- `login`
- `sign`
- `encrypt`
- `cipher`
- `token`
- `root`
- `certificate`
- `trust`
- `okhttp`
- `retrofit`
- `webview`

如果 Java 程式碼可讀，先在這裡定位業務邏輯。

### 3. Smali 與資源層確認

當 `jadx` 結果不完整、混淆重、或需要實際 patch 時，切到 `apktool_out`：

- 看 `smali*/`
- 看 `res/values/strings.xml`
- 看 `AndroidManifest.xml`

優先 patch：

- `android:exported`
- 除錯標記
- root 檢測回傳值
- 登入驗證邏輯
- 憑證校驗分支

### 4. 重建與安裝

修改後：

```bash
apktool b apktool_out -o rebuilt.apk
```

或者直接用腳本閉環：

```powershell
pwsh -File "<skill-root>\apk-reverse\scripts\rebuild-sign-install.ps1" -ProjectDir "apktool_out" -Install -Reinstall -DeviceSerial "127.0.0.1:7555"
```

說明：

- 本 skill 只保證 `apktool` 重建鏈路
- 若後續需要正式安裝到裝置，通常還需要簽章流程
- 如果任務進入簽章/對齊，補充 `apksigner` / `zipalign`

### 5. 動態 Hook

靜態分析不足時，用 Frida：

- Hook 登入函式
- Hook `OkHttp` / `Retrofit` / `WebView` 關鍵點
- Hook `javax.crypto`、`MessageDigest`
- Hook root 檢測函式
- Hook SSL pinning 邏輯

原則：

- 先 Hook Java 層，再看是否需要 native Hook
- 先印出參數與回傳值，再決定是否主動修改回傳值

建議：

- 簡單一次性命令直接用 `frida-*`
- 需要穩定複用的注入流程優先走 `scripts/frida-run.ps1`

### 6. Native `.so` 分流

如果 APK 中包含關鍵 `.so`：

- 用 `apktool` 或 `jadx` 找到 `lib/**/*.so`
- 若只是匯出符號、字串、快速 triage，可用 `radare2`
- 若要長期深入分析、反編譯、改名、型別還原，用 `ida-reverse`

遇到這些訊號要盡快切 native：

- Java 層只是 JNI 包裝
- 核心簽章邏輯不在 Java
- `System.loadLibrary()` 後關鍵邏輯消失
- 憑證校驗/風控在 `.so` 中

## 輸出要求

最終至少說明：

- 進入點元件與關鍵類別
- 關鍵邏輯在 Java、smali 還是 `.so`
- 已確認的敏感點：登入、簽章、root、SSL、WebView、JNI
- 如果做了 patch，說明改了什麼
- 如果做了 Hook，說明 Hook 了哪個類別/方法/匯出函式

## 禁止事項

- 不要一開始就盲目改 smali
- 不要在沒看 manifest 和主進入點前就寫 Hook
- 不要把 Java 反編譯不完整直接等同於「邏輯不可分析」
- 不要在 `.so` 明顯承載核心邏輯時繼續死磕 Java 層

## 快速命令備忘

```bash
# 反編譯 Java
jadx -d jadx_out app.apk

# 解包 APK
apktool d app.apk -o apktool_out

# 重建 APK
apktool b apktool_out -o rebuilt.apk

# 裝置與程序
adb devices
frida-ps -U

# 啟動並注入
frida -U -f com.example.app -l hook.js
```

---

## 路由上下文

**上游入口**: `skills/SKILL.md`（總控）、`routing.md`
**下游出口**:
- 核心邏輯在 `.so` → `ida-reverse/` 或 `radare2/`
- 需動態 Hook/驗證 → `reverse-engineering/tools-dynamic.md`（Frida 章節）
- 通用逆向方法論 → `reverse-engineering/SKILL.md`

**同級關聯模組**: `reverse-engineering/`（.so 分析和 Frida 進階用法）

---

## 按需自舉（On-Demand Bootstrap）

本 skill 的入口腳本已接入統一自舉系統。缺少工具時不會直接報錯，而是自動嘗試安裝。

### 自動化能力邊界

| 工具 | 可自動安裝 | 安裝方式 | 說明 |
|------|-----------|---------|------|
| jadx | ✓ | GitHub Release ZIP | 自動下載解壓到 `%USERPROFILE%\Tools\jadx\` |
| apktool | ✓ | GitHub Release JAR + wrapper | 自動下載 jar 並產生 bat 到 `%USERPROFILE%\Tools\apktool\` |
| JEB Pro | ✗ | 使用者手動安裝並提供有效授權 | 可選的 Android / ARM 交叉驗證工具；第三方 MCP bridge 需單獨審計 |
| frida / frida-ps | ✓ | pip install frida-tools | 需要 Python 已安裝 |
| adb | ✓ | winget / fallback path | 自動安裝 Android Platform-Tools |
| zipalign | ✗ | 需手動安裝 Android Build-Tools | `sdkmanager "build-tools;35.0.0"` |
| apksigner | ✗ | 需手動安裝 Android Build-Tools | 同上 |

### 自舉觸發點

- `scripts/decode.ps1`：缺 jadx 或 apktool 時自動調用 `bootstrap-reverse.ps1`
- `scripts/rebuild-sign-install.ps1`：缺 adb 或 apktool 時自動調用 bootstrap
- `scripts/frida-run.ps1`：目前仍為手動檢查（frida 通常已透過 pip 安裝）

### 自舉失敗時

如果自動安裝失敗，腳本會拋出明確錯誤並附帶手動安裝連結。常見原因：
- 網路不通（GitHub API / PyPI 不可達）
- winget 不可用（Windows 版本過低）
- Java 未安裝（apktool 依賴 JDK）


## 任務完成自檢（聲稱完成前 MUST 通過）

- [ ] 我是否執行了工作流中的每一步（而不是只閱讀）？
- [ ] 我是否基於 `tool-index` 使用了真實工具路徑？
- [ ] 我是否產出了可復現證據（命令/腳本/截圖/報告）？
- [ ] 我是否完成並回寫了 RULES 要求的 Checklist 項？
- [ ] 若命中隱藏圖示/刷機/持久化線索：是否按 U–AV cookbook 記錄 E-android-* Evidence（授權範圍內）？
