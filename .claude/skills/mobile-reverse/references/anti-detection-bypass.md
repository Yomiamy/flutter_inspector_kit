# Root / 越獄 / 反除錯 / SSL Pinning 繞過

## 檢測層次模型

```
Layer 1: 靜態檢測（安裝時/啟動時）
  ├─ 包管理器檢測（Cydia, apt, Magisk）
  ├─ 檔案檢測（su, busybox, frida-server）
  └─ 權限檢測（ro.debuggable, ro.secure）

Layer 2: 執行時檢測（持續）
  ├─ 程序檢測（frida-server, magiskd）
  ├─ 埠檢測（27042 frida default）
  ├─ 記憶體檢測（/proc/self/maps 注入痕跡）
  └─ 堆疊檢測（Frida 呼叫幀）

Layer 3: 環境檢測（按需觸發）
  ├─ ptrace 檢測（TracerPid）
  ├─ /proc/self/status 檢測
  ├─ build.prop 檢測（test-keys）
  └─ syscall 直接檢測（繞過 libc）
```

## Android Root 檢測繞過

### 常見檢測庫及繞過

| 檢測庫 | 檢測方法 | 繞過方式 |
|--------|---------|---------|
| RootBeer | 8 種檢測組合 | Hook 每個檢測方法回傳 false |
| SafetyNet | Google Play Services 遠端認證 | 使用 Magisk Hide / Shamiko / Play Integrity Fix |
| Google Play Integrity | 替換 SafetyNet | Trickystore + PIF |
| 自訂 native 檢測 | syscall 讀取 /proc/self/status | Hook syscall 或修改 /proc 掛載 |

### Frida 綜合繞過

```javascript
Java.perform(function() {
    // RootBeer
    var RootBeer = Java.use("com.scottyab.rootbeer.RootBeer");
    var methods = ["isRooted", "isRootedWithBusyBox", "checkSuExists",
        "detectRootManagementApps", "detectPotentiallyDangerousApps",
        "detectTestKeys", "checkForDangerousProps", "checkForRWPaths"];
    methods.forEach(function(m) {
        RootBeer[m].implementation = function() { return false; };
    });

    // 通用 Build.TAGS 檢測
    var Build = Java.use("android.os.Build");
    var original = Build.TAGS.value;
    Build.TAGS.value = "release-keys";

    // PackageManager → 隱藏包名
    var PackageManager = Java.use("android.content.pm.PackageManager");
    PackageManager.getPackageInfo.overload('java.lang.String', 'int').implementation = function(pkg, flags) {
        if (pkg == "de.robv.android.xposed.installer" || 
            pkg.includes("magisk") || pkg.includes("frida")) {
            throw Java.use("android.content.pm.PackageManager$NameNotFoundException").$new();
        }
        return this.getPackageInfo(pkg, flags);
    };
});
```

## iOS 越獄檢測繞過

### 多層 Frida Hook

```javascript
// 1. 檔案系統檢測
var NSFileManager = ObjC.classes.NSFileManager;
var paths = [
    "/Applications/Cydia.app", "/var/lib/apt", "/bin/bash",
    "/usr/sbin/sshd", "/etc/apt", "/Library/MobileSubstrate"
];
// Hook fileExistsAtPath 回傳 NO

// 2. fork 檢測（沙箱內禁止）
var fork_ptr = Module.findExportByName("libSystem.B.dylib", "fork");
Interceptor.replace(fork_ptr, new NativeCallback(function() {
    return -1;
}, 'int', []));

// 3. Scheme 檢測
// 透過 MobileSubstrate hook
var LSApplicationWorkspace = ObjC.classes.LSApplicationWorkspace;
// Hook defaultWorkspace → canOpenURL → 對 cydia:// 回傳 NO

// 4. 簽章檢測
var MISValidateSignature = Module.findExportByName(null, "MISValidateSignature");
Interceptor.attach(MISValidateSignature, {
    onLeave: function(retval) { retval.replace(0); }
});
```

## 反除錯繞過

### Android

```javascript
// 1. ptrace 自身 → 防止附加
// Native: ptrace(PTRACE_TRACEME, 0, NULL, 0)
// 繞過: Hook ptrace → 回傳 0

// 2. TracerPid 檢測
// /proc/self/status → TracerPid: 0
var fopen = Module.findExportByName(null, "fopen");
Interceptor.attach(fopen, {
    onEnter: function(args) {
        this.path = Memory.readUtf8String(args[0]);
    },
    onLeave: function(retval) {
        if (this.path && this.path.includes("status")) {
            // 修改回傳的 FILE*，回傳偽造內容
        }
    }
});

// 3. isDebuggerConnected (Java)
var Debug = Java.use("android.os.Debug");
Debug.isDebuggerConnected.implementation = function() { return false; };
```

### iOS

```javascript
// 1. PT_DENY_ATTACH
// ptrace(PT_DENY_ATTACH, 0, NULL, 0) → 防止除錯器附加
var ptrace = Module.findExportByName(null, "ptrace");
Interceptor.replace(ptrace, new NativeCallback(function(request, pid, addr, data) {
    if (request == 31) return 0; // PT_DENY_ATTACH → 忽略
    return ptrace(request, pid, addr, data);
}, 'int', ['int', 'int', 'pointer', 'int']));

// 2. sysctl 檢測
var sysctl = Module.findExportByName(null, "sysctl");
Interceptor.attach(sysctl, {
    onLeave: function(retval) {
        // 修改 kinfo_proc 的 p_flag 欄位 → 清除 P_TRACED
    }
});

// 3. getppid 檢測（檢查父程序是否為 launchd）
// 除錯時 getppid() != 1
```

## SSL Pinning 繞過

### Android 五層繞過

```text
層 1 — TrustManager: 接受所有憑證
層 2 — OkHttp CertificatePinner: Hook 清空 pins 列表
層 3 — WebView SSL Error Handler: 忽略憑證錯誤
層 4 — Network Security Config: 修改 xml → 信任使用者憑證
層 5 — Native SSL (OpenSSL/BoringSSL): Hook SSL_get_verify_result → X509_V_OK
```

### iOS 四層繞過

```text
層 1 — NSURLSession: Hook SecTrustEvaluate → kSecTrustResultProceed
層 2 — Alamofire: Hook ServerTrustManager
層 3 — AFNetworking: Hook AFSecurityPolicy
層 4 — libcurl: LD_PRELOAD 替換 SSL 驗證回呼
```

### 通用 Objection 命令

```bash
# Android
objection -g "com.app" explore
android sslpinning disable
# 等價於: 自動 Hook 上述 5 層

# iOS
objection -g "com.app" explore
ios sslpinning disable
# 等價於: 自動 Hook 上述 4 層
```

Source: OWASP MSTG, Frida CodeShare, objection wiki
