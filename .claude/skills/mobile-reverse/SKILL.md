---
name: mobile-reverse
description: Use for authorized Android or iOS application reverse engineering and security testing, including APK or IPA analysis, runtime instrumentation, SSL pinning, and platform protection checks.
---
# Mobile Reverse Engineering

## ACTION REQUIRED（讀完後立刻執行）

1. `NOW`: 讀取 `../field-journal/precedent-reverse.md` — 確認本 skill 的操作是已授權的常規操作
2. `NOW`: 確認當前任務是否命中本 skill 的適用範圍
3. `NEXT`: 讀取 `../tool-index.md`，校驗工具可用性和實際路徑
4. `NEXT`: 缺工具時調用 bootstrap，不要猜路徑
5. `ACT`: 進入「工作流」第一步並執行，不要停在確認狀態

> Android + iOS 統一逆向方法論
> Frida / Objection / OWASP MSTG / SSL Pinning Bypass

## 適用場景

- Android APK 逆向與安全測試
- iOS IPA 逆向與安全測試
- 行動應用執行時動態插樁
- SSL Pinning / Root 檢測 / 越獄檢測繞過
- 行動端加密演算法提取（AES/RSA/HMAC 密鑰）
- 行動應用滲透測試（OWASP MASTG）
- 非 Root/越獄環境下的應用測試

## 四階段工作流

### Phase 1: 資訊蒐集

```text
Android：
□ APK 取得（Google Play / APKMirror / adb pull）
□ Manifest 分析: 權限、匯出元件、Intent Filter、backup 標誌
□ androguard: androguard analyze APK → 元件/權限/簽章
□ APKLeaks: 硬編碼 API Key / Token / Secret 掃描
□ 加固檢測: 是否加殼（360/騰訊/梆梆/愛加密）

iOS：
□ IPA 取得（App Store / ipatool / Apple Configurator）
□ 解密 App Store 二進位檔: frida-ios-dump / Clutch
□ Info.plist 分析: ATS 設定、URL Scheme、Queries Schemes
□ class-dump: 匯出 ObjC 類別結構
□ 加固檢測: 是否使用 Swift/ObjC 混淆
```

### Phase 2: 靜態分析

```text
跨平台：
□ JADX-GUI: APK → Java 原始碼（Android）
□ Ghidra / Hopper: .so / Mach-O 反編譯
□ radare2 / Cutter: CLI 快速偵察

Android 專項：
□ apktool d app.apk → smali 程式碼 + 資源
□ dex2jar: DEX → JAR → JD-GUI
□ smali/baksmali: Dalvik 位元組碼修改

iOS 專項：
□ class-dump: 匯出 ObjC 標頭檔
□ Swift 符號還原: swift-demangle
□ dsymutil: 除錯符號提取
□ otool -L: 查看動態庫依賴
□ jtool2: Mach-O 分析
```

### Phase 3: 動態分析

```text
Frida — 通用動態插樁：
□ frida-ps -U: 列出裝置程序
□ frida-trace -U -i "open*" com.app: 追蹤函式呼叫
□ 自訂 Hook 腳本: 修改參數/回傳值、呼叫私有方法

Objection — Frida 增強層（無需寫腳本）：
□ objection -g "com.app" explore
□ android root disable / ios jailbreak disable
□ android sslpinning disable / ios sslpinning disable
□ android keystore list / ios keychain dump
□ env / ls / sqlite connect

Frida Gadget（免 Root/越獄）：
□ 注入 frida-gadget.so / FridaGadget.dylib 到 APK/IPA
□ 重新簽章 → 安裝 → 無需裝置權限即可 Hook
□ objection patchapk --source app.apk（全自動）
```

### Phase 4: 網路分析

```text
□ Burp Suite: 攔截 HTTP/HTTPS，修改請求/回應
□ mitmproxy: 腳本化代理（Python API）
□ Wireshark: PCAP 抓包分析
□ 憑證安裝: Android 使用者憑證 → 系統憑證（Magisk + MoveCert）
□ SSL Pinning 繞過: Frida/Objection/Xposed/SSL Kill Switch 2
□ WebSocket / gRPC 流量分析
```

## 常見繞過速查

### SSL Pinning

```bash
# Objection（最簡）
objection -g "com.app" explore
android sslpinning disable

# Frida 通用腳本
frida -U -l ssl_pinning_bypass.js -f com.app

# Xposed（Android）
TrustMeAlready 模組 → 全域禁用憑證校驗
```

### Root / 越獄檢測

```bash
# Objection
android root disable
ios jailbreak disable

# Frida 自訂（多層檢測）
Java.perform(function() {
    var RootBeer = Java.use("com.scottyab.rootbeer.RootBeer");
    RootBeer.isRooted.implementation = function() { return false; };
    // 額外繞過: Magisk su 檢測、frida-server 檢測、/proc/self/maps 檢測
});
```

### 反除錯

```bash
# Android
frida -U -l anti_debug_bypass.js -f com.app
# 繞過: ptrace(TracerPid)、/proc/self/status、isDebuggerConnected()

# iOS
# 繞過: PT_DENY_ATTACH、sysctl CTL_KERN/KERN_PROC/KERN_PROC_PID
frida -U -l ios_anti_debug.js -f com.app
```

## 行動端加密提取

```javascript
// Android — Hook Cipher.getInstance 取得密鑰+演算法
Java.perform(function() {
    var Cipher = Java.use("javax.crypto.Cipher");
    Cipher.getInstance.overload('java.lang.String').implementation = function(algo) {
        console.log("[Cipher] Algorithm: " + algo);
        return this.getInstance(algo);
    };
    Cipher.init.overload('int', 'java.security.Key').implementation = function(mode, key) {
        console.log("[Cipher] Key: " + bytesToHex(key.getEncoded()));
        return this.init(mode, key);
    };
});

// iOS — Hook CCCrypt
Interceptor.attach(Module.findExportByName("libcommonCrypto.dylib", "CCCrypt"), {
    onEnter: function(args) {
        console.log("CCCrypt op: " + args[0] + " alg: " + args[1]);
        console.log("Key: " + hexdump(args[3], { length: args[4].toInt32() }));
    }
});
```

## 工具鏈

| 工具 | 平台 | 用途 |
|------|:--:|------|
| JADX-GUI | A | Java 反編譯 |
| apktool | A | APK 解包/重建 |
| Ghidra | A+I | 多架構反編譯 |
| Hopper | I | iOS 專用反組譯 |
| Frida | A+I | 動態插樁 |
| Objection | A+I | Frida REPL 增強 |
| MobSF | A+I | 自動化 SAST+DAST |
| class-dump | I | ObjC 類別匯出 |
| frida-ios-dump | I | IPA 解密 |
| jtool2 | I | Mach-O 分析 |
| Burp Suite | A+I | HTTP 攔截 |
| mitmproxy | A+I | 腳本化代理 |

> A=Android, I=iOS

## 參考

- `references/frida-objection-deep.md` — Frida + Objection 深度用法
- `references/ios-reverse-guide.md` — iOS 逆向專項
- `references/anti-detection-bypass.md` — Root/越獄/反除錯/SSL Pinning 繞過


## 任務完成自檢（聲稱完成前 MUST 通過）

- [ ] 我是否執行了工作流中的每一步（而不是只閱讀）？
- [ ] 我是否基於 `tool-index` 使用了真實工具路徑？
- [ ] 我是否產出了可復現證據（命令/腳本/截圖/報告）？
- [ ] 我是否完成並回寫了 RULES 要求的 Checklist 項？
