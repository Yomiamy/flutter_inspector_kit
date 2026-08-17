# Frida + Objection 深度用法

## Frida 核心 API

### Java 執行環境 (Android)

```javascript
Java.perform(function() {
    // 取得類別實例
    var String = Java.use("java.lang.String");

    // Hook 靜態方法
    var System = Java.use("java.lang.System");
    System.getProperty.overload('java.lang.String').implementation = function(key) {
        console.log("System.getProperty: " + key);
        return this.getProperty(key);
    };

    // Hook 建構子
    var File = Java.use("java.io.File");
    File.$init.overload('java.lang.String').implementation = function(path) {
        console.log("File opened: " + path);
        return this.$init(path);
    };

    // 枚舉已載入類別
    Java.enumerateLoadedClasses({
        onMatch: function(className) { console.log(className); },
        onComplete: function() {}
    });

    // 修改回傳值
    var RootDetector = Java.use("com.app.security.RootDetector");
    RootDetector.isDeviceRooted.implementation = function() {
        return false;
    };
});
```

### Native 層 (Android + iOS)

```javascript
// Hook 匯出函式
Interceptor.attach(Module.findExportByName(null, "open"), {
    onEnter: function(args) {
        this.path = Memory.readUtf8String(args[0]);
    },
    onLeave: function(retval) {
        console.log("open(" + this.path + ") = " + retval);
    }
});

// Hook 任意位址（透過偏移）
var base = Module.findBaseAddress("libnative.so");
var target = base.add(0x12345);
Interceptor.attach(target, {
    onEnter: function(args) {
        console.log("Function called from: " + Thread.backtrace(this.context, Backtracer.ACCURATE)
            .map(DebugSymbol.fromAddress).join('\n'));
    }
});

// 修改回傳值
Interceptor.attach(Module.findExportByName(null, "strcmp"), {
    onLeave: function(retval) {
        if (retval.toInt32() === 0) return; // strings equal, skip
        // Force match
        retval.replace(0);
    }
});
```

### ObjC 執行環境 (iOS)

```javascript
// Hook ObjC 方法
var hook = ObjC.classes.ViewController["- viewDidLoad"];
Interceptor.attach(hook.implementation, {
    onEnter: function(args) {
        console.log("viewDidLoad called");
    }
});

// 枚舉所有類別
ObjC.enumerateLoadedClasses({
    onMatch: function(className) { console.log(className); },
    onComplete: function() {}
});

// 呼叫 ObjC 方法
var NSString = ObjC.classes.NSString;
var str = NSString.stringWithString_("Hello from Frida");
```

## Objection 命令速查

### 通用

```bash
objection -g "com.app" explore           # 啟動
objection -g "com.app" explore -q        # 靜默啟動（只注入不等待）
objection patchapk --source app.apk      # 自動注入 Frida Gadget
objection signapk --source app.apk       # 僅簽章

# 檔案系統
env              # 應用資料目錄
ls               # 列出檔案
file download /path/to/file  # 下載檔案
file upload local.txt /remote/path  # 上傳檔案

# SQLite
sqlite connect /path/to/db.sqlite
.tables          # 列出表格
select * from users;  # 查詢
```

### Android 專用

```bash
android root disable              # 繞過 Root 檢測
android sslpinning disable        # 繞過 SSL Pinning
android hooking list classes      # 枚舉類別
android hooking list class_methods com.app.Main  # 枚舉方法
android hooking watch class com.app.Main  # Hook 所有方法
android intent launch_activity com.app.MainActivity  # 啟動 Activity
android heap search instances com.app.User  # 堆積搜尋
android keystore list             # Keystore 項目
```

### iOS 專用

```bash
ios jailbreak disable             # 繞過越獄檢測
ios sslpinning disable            # 繞過 SSL Pinning
ios keychain dump                 # 匯出 Keychain
ios nsuserdefaults get            # NSUserDefaults
ios nsurlcache dump               # HTTP 快取
ios cookies get                   # 讀取 Cookies
ios pasteboard monitor            # 監聽剪貼簿
ios ui dump                       # UI 層次結構
ios plist cat Info.plist          # 讀取 plist
```

## 免 Root/越獄部署

### Android — Frida Gadget 注入

```bash
# 1. 解包 APK
apktool d app.apk -o app_unpacked

# 2. 下載 frida-gadget 並放入 lib 目錄
cp frida-gadget-17.x.x-android-arm64.so \
   app_unpacked/lib/arm64-v8a/libfrida-gadget.so

# 3. 在 smali 中注入 System.loadLibrary("frida-gadget")
# 修改主 Activity 的 onCreate 或 attachBaseContext

# 4. 重建並簽章
apktool b app_unpacked -o app_patched.apk
uber-apk-signer -a app_patched.apk

# 5. Objection 自動化
objection patchapk --source app.apk --skip-resources
```

### iOS — Frida Gadget 注入

```bash
# 1. 解密 App Store IPA
python3 frida-ios-dump.py -u -p com.app.target

# 2. 注入 FridaGadget.dylib
# 修改 Mach-O Load Commands，加入 @executable_path/FridaGadget.dylib

# 3. 重新簽章
codesign -f -s "Apple Development" Payload/App.app

# 4. 透過 Xcode sideload 或 AltStore 安裝
```

## SSL Pinning 繞過進階

### 多層繞過（Android）

```javascript
// 1. OkHttp CertificatePinner
var CertificatePinner = Java.use("okhttp3.CertificatePinner");
CertificatePinner.check.overload('java.lang.String', 'java.util.List').implementation = function() {};

// 2. TrustManager 自訂
var TrustManagerImpl = Java.use("com.android.org.conscrypt.TrustManagerImpl");
TrustManagerImpl.verifyChain.implementation = function() { return []; };

// 3. WebView SSL Error
var SslErrorHandler = Java.use("android.webkit.SslErrorHandler");
SslErrorHandler.proceed.implementation = function() { return this.proceed(); };

// 4. Network Security Config
// 需要修改 AndroidManifest.xml → android:networkSecurityConfig="@xml/network_security_config"
// xml 中加入信任使用者憑證
```

### 多層繞過（iOS）

```javascript
// 1. NSURLSession
var SecTrustEvaluate = Module.findExportByName("Security", "SecTrustEvaluate");
Interceptor.replace(SecTrustEvaluate, new NativeCallback(function(trust, result) {
    Memory.writeU32(result, 1); // kSecTrustResultProceed = 1
    return 0; // errSecSuccess
}, 'int', ['pointer', 'pointer']));

// 2. Alamofire
// Hook ServerTrustManager.evaluate → 始終回傳 success
```

Source: Frida docs, Objection wiki, OWASP MSTG
