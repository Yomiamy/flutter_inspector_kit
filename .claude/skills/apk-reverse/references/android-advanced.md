# Android 高級逆向參考

> 涵蓋 Native SO 分析、Frida 高級用法、SSL Pinning 繞過、Root 檢測對抗、加固脫殼、Flutter/React Native 逆向。

---

## Native SO 逆向

### 分析流程

```text
1. 從 APK 中提取 .so 檔案
   unzip app.apk lib/arm64-v8a/*.so -d extracted/

2. 確認架構和基本資訊
   file libxxx.so
   rabin2 -I libxxx.so

3. 找 JNI 進入點
   - 搜尋 JNI_OnLoad（動態註冊）
   - 搜尋 Java_com_xxx_yyy（靜態註冊）
   - nm -D libxxx.so | grep -i java

4. IDA/Ghidra 載入分析
   - 匯入 JNI 標頭檔（jni.h 型別）
   - 標註 JNIEnv* 參數
   - 找 RegisterNatives 呼叫（動態註冊的函式表）

5. 定位關鍵邏輯
   - 從 Java 層 native 方法名追蹤
   - 從字串（密鑰、URL、錯誤訊息）交叉引用
   - 從 crypto 函式庫函式（AES/MD5/SHA）呼叫追蹤
```

### JNI 函式註冊

```c
// 靜態註冊：函式名 = Java_包名_類名_方法名
JNIEXPORT jstring JNICALL Java_com_example_app_Security_getSign(
    JNIEnv *env, jobject thiz, jstring input) { ... }

// 動態註冊：在 JNI_OnLoad 中呼叫 RegisterNatives
static JNINativeMethod methods[] = {
    {"getSign", "(Ljava/lang/String;)Ljava/lang/String;", (void*)native_getSign},
};

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    JNIEnv *env;
    vm->GetEnv((void**)&env, JNI_VERSION_1_6);
    jclass clazz = env->FindClass("com/example/app/Security");
    env->RegisterNatives(clazz, methods, sizeof(methods)/sizeof(methods[0]));
    return JNI_VERSION_1_6;
}
```

### IDA 中分析 JNI 的技巧

```text
1. 匯入 JNI 型別庫
   File → Load File → Parse C Header → jni.h

2. 標註第一個參數為 JNIEnv*
   右鍵參數 → Set type → JNIEnv*
   這樣 env->FindClass / env->GetMethodID 等呼叫會自動識別

3. 找 RegisterNatives
   搜尋對 JNIEnv vtable offset 0x35C (ARM64) 的呼叫
   → 第三個參數是 JNINativeMethod 陣列
   → 從陣列中提取所有 native 函式位址
```

---

## Frida 高級用法

### Hook Native 函式

```javascript
// Hook libc 函式
Interceptor.attach(Module.findExportByName("libc.so", "open"), {
    onEnter: function(args) {
        this.path = args[0].readUtf8String();
        console.log("[open] " + this.path);
    },
    onLeave: function(retval) {
        if (this.path.includes("su") || this.path.includes("magisk")) {
            console.log("[open] Blocked root check: " + this.path);
            retval.replace(-1);  // 回傳失敗
        }
    }
});

// Hook 自訂 SO 中的函式
var base = Module.findBaseAddress("libsecurity.so");
var targetFunc = base.add(0x1234);  // 偏移位址
Interceptor.attach(targetFunc, {
    onEnter: function(args) {
        console.log("arg0: " + args[0].readUtf8String());
    },
    onLeave: function(retval) {
        console.log("return: " + retval.readUtf8String());
    }
});
```

### Hook Java 方法

```javascript
Java.perform(function() {
    // Hook 實例方法
    var Security = Java.use("com.example.app.Security");
    Security.getSign.implementation = function(input) {
        console.log("[getSign] input: " + input);
        var result = this.getSign(input);  // 呼叫原方法
        console.log("[getSign] output: " + result);
        return result;
    };

    // Hook 建構子
    Security.$init.overload('java.lang.String').implementation = function(key) {
        console.log("[Security.<init>] key: " + key);
        this.$init(key);
    };

    // Hook 多載方法
    Security.encrypt.overload('java.lang.String', 'int').implementation = function(data, mode) {
        console.log("[encrypt] data=" + data + " mode=" + mode);
        return this.encrypt(data, mode);
    };
});
```

### 記憶體搜尋與修改

```javascript
// 搜尋記憶體中的字串
Process.enumerateModules().forEach(function(module) {
    if (module.name === "libtarget.so") {
        Memory.scan(module.base, module.size, "48 65 6C 6C 6F", {  // "Hello"
            onMatch: function(address, size) {
                console.log("Found at: " + address);
            }
        });
    }
});

// 修改記憶體（patch 指令）
var addr = Module.findBaseAddress("libsecurity.so").add(0x5678);
Memory.patchCode(addr, 4, function(code) {
    var writer = new Arm64Writer(code, {pc: addr});
    writer.putNop();  // 替換為 NOP
    writer.flush();
});
```

---

## SSL Pinning 繞過

### 通用方案（推薦）

```javascript
// Frida 通用 SSL Pinning 繞過
// 來源: https://github.com/0xCD4/SSL-bypass
Java.perform(function() {
    // 1. TrustManager 繞過
    var TrustManager = Java.registerClass({
        name: 'com.custom.TrustManager',
        implements: [Java.use('javax.net.ssl.X509TrustManager')],
        methods: {
            checkClientTrusted: function(chain, authType) {},
            checkServerTrusted: function(chain, authType) {},
            getAcceptedIssuers: function() { return []; }
        }
    });

    // 2. SSLContext 替換
    var SSLContext = Java.use('javax.net.ssl.SSLContext');
    var sslContext = SSLContext.getInstance("TLS");
    sslContext.init(null, [TrustManager.$new()], null);

    // 3. OkHttp CertificatePinner 繞過
    try {
        var CertificatePinner = Java.use('okhttp3.CertificatePinner');
        CertificatePinner.check.overload('java.lang.String', 'java.util.List').implementation = function() {};
    } catch(e) {}
});
```

### 各框架繞過

| 框架 | 繞過方法 |
|------|---------|
| OkHttp3 | Hook `CertificatePinner.check` 回傳空 |
| Retrofit | 同 OkHttp（底層用 OkHttp） |
| Volley | Hook `HurlStack` 的 SSL 工廠 |
| Flutter | Hook `dart:io` 的 `SecurityContext`（需要特殊腳本） |
| React Native | Hook `OkHttpClientProvider` |
| WebView | Hook `WebViewClient.onReceivedSslError` |

### Flutter 專項

```javascript
// Flutter SSL Pinning 繞過（需要找到 ssl_verify_peer_cert 函式）
var flutter_lib = Module.findBaseAddress("libflutter.so");
// 搜尋 ssl_verify_peer_cert 的特徵碼
var pattern = "FF 03 05 D1 FD 7B 0F A9";  // ARM64 特徵
Memory.scan(flutter_lib, Module.findModuleByName("libflutter.so").size, pattern, {
    onMatch: function(address) {
        Interceptor.replace(address, new NativeCallback(function() {
            return 0;  // 回傳成功
        }, 'int', []));
    }
});
```

---

## Root 檢測繞過

### 常見檢測方式

| 檢測方式 | 繞過方法 |
|---------|---------|
| 檢查 `/system/app/Superuser.apk` | Hook `File.exists()` 回傳 false |
| 檢查 `su` 命令 | Hook `Runtime.exec()` 攔截 su 呼叫 |
| 檢查 `/proc/self/mounts` | Hook 檔案讀取，過濾 magisk 相關 |
| SafetyNet/Play Integrity | Magisk Hide / Zygisk + Shamiko |
| 檢查 Magisk 包名 | 隨機化 Magisk 包名 |
| 檢查 `/data/adb/` | Hook `opendir`/`access` |

### Frida 通用 Root 繞過

```javascript
Java.perform(function() {
    // Hook File.exists
    var File = Java.use("java.io.File");
    File.exists.implementation = function() {
        var path = this.getAbsolutePath();
        var blacklist = ["su", "Superuser", "magisk", "busybox", "xposed"];
        for (var i = 0; i < blacklist.length; i++) {
            if (path.toLowerCase().includes(blacklist[i])) {
                return false;
            }
        }
        return this.exists();
    };

    // Hook System.getProperty
    var System = Java.use("java.lang.System");
    System.getProperty.overload('java.lang.String').implementation = function(key) {
        if (key === "ro.debuggable" || key === "ro.secure") {
            return "1";
        }
        return this.getProperty(key);
    };
});
```

---

## 加固/殼識別與脫殼

### 常見加固廠商

| 加固 | 識別特徵 | 脫殼方式 |
|------|---------|---------|
| 360 加固 | `libjiagu.so`、`com.stub.StubApp` | FART / Frida dump dex |
| 騰訊樂固 | `libshell*.so`、`com.tencent.StubShell` | FART / BlackDex |
| 梆梆加固 | `libDexHelper.so`、`com.secneo.apkwrapper` | FART |
| 愛加密 | `libexec.so`、`s.h.e.l.l` | Frida dump |
| 網易易盾 | `libnesec.so` | Frida dump |
| 娜迦 | `libnaga.so` | Frida dump |

### 通用脫殼方法

```text
方法 1: FART（ART 環境脫殼）
- 刷入 FART ROM 或使用 Frida 版 FART
- 自動 dump 所有 ClassLoader 載入的 dex

方法 2: Frida DEX Dump
- frida -U -f com.target.app -l dex_dump.js
- 在 DexFile::OpenMemory 處 hook，dump 記憶體中的 dex

方法 3: BlackDex
- 免 root 脫殼工具
- 直接安裝 BlackDex APK，選擇目標應用脫殼

方法 4: 手動 dump
- 用 Frida 枚舉所有 ClassLoader
- 找到應用的 ClassLoader → 取得 DexFile 物件
- 讀取 dex 記憶體區域並儲存
```

### Frida DEX Dump 腳本

```javascript
Java.perform(function() {
    Java.enumerateClassLoaders({
        onMatch: function(loader) {
            try {
                var dexFiles = loader.getDexFileList();
                console.log("ClassLoader: " + loader);
                console.log("  DEX files: " + dexFiles);
            } catch(e) {}
        },
        onComplete: function() {}
    });
});
```

---

## React Native / Flutter 逆向

### React Native

```text
1. 解壓 APK → assets/index.android.bundle（JS 程式碼）
2. 格式化 JS → 搜尋 API 位址、密鑰、簽章邏輯
3. 如果有 Hermes 位元組碼（.hbc 檔案）→ 用 hermes-dec 反編譯
4. Hook: 用 Frida hook Java 層的 ReactBridge
```

### Flutter

```text
1. Flutter 程式碼編譯為 libapp.so（Dart AOT）
2. 無法直接反編譯為 Dart 原始碼
3. 分析方法：
   - reFlutter 工具：patch libflutter.so 取得 snapshot
   - Doldrums：解析 Dart snapshot 還原類別/函式資訊
   - Frida hook libflutter.so 中的關鍵函式
4. 網路分析：Flutter 不走系統代理，需要特殊處理 SSL
```

---

## 工具速查

| 工具 | 用途 | 安裝 |
|------|------|------|
| jadx | Java 反編譯 | 已在 bootstrap 中 |
| apktool | 解包/重打包 | 已在 bootstrap 中 |
| Frida | 動態 Hook | `pip install frida-tools` |
| Objection | Frida 封裝（更易用） | `pip install objection` |
| MobSF | 自動化行動安全分析 | Docker 部署 |
| BlackDex | 免 root 脫殼 | APK 安裝 |
| FART | ART 脫殼 | 刷入 ROM 或 Frida 版 |
| hermes-dec | Hermes 位元組碼反編譯 | npm 安裝 |
| reFlutter | Flutter 逆向輔助 | pip 安裝 |
| Magisk + Shamiko | Root 隱藏 | 刷入 |

---

## 參考資源

| 資源 | 說明 | 連結 |
|------|------|------|
| OWASP MASTG | 行動安全測試指南 | https://mas.owasp.org/ |
| FridaBypassKit | 通用繞過框架 | https://github.com/okankurtuluss/FridaBypassKit |
| SSL-bypass | 通用 SSL Pinning 繞過 | https://github.com/0xCD4/SSL-bypass |
| awesome-frida | Frida 資源合集 | https://github.com/dweinstein/awesome-frida |
| Android Security Awesome | Android 安全資源 | https://github.com/ashishb/android-security-awesome |
