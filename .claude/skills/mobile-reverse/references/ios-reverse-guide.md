# iOS 逆向工程專項

## IPA 取得與解密

```bash
# 從 App Store 下載
ipatool search "Target App"
ipatool purchase -b com.target.app
ipatool download -b com.target.app -o app.ipa

# 從裝置提取已安裝應用
# 越獄裝置
scp root@device:/private/var/containers/Bundle/Application/*/Target.app .

# 解密（App Store 二進位檔為加密 FAT 格式）
# frida-ios-dump（推薦）
python3 dump.py com.target.app -o decrypted.ipa

# Clutch
Clutch -i  # 列出已安裝
Clutch -d 1  # 解密第 1 個

# dumpdecrypted
DYLD_INSERT_LIBRARIES=dumpdecrypted.dylib /path/to/App
```

## Mach-O 分析

```bash
# 基本資訊
otool -l TargetBinary | grep crypt    # 加密狀態
otool -L TargetBinary                 # 動態庫依賴
otool -hv TargetBinary                # 標頭資訊
jtool2 --pages TargetBinary           # 記憶體頁資訊

# Fat Binary 瘦身
lipo -info TargetBinary
lipo TargetBinary -thin arm64 -output TargetBinary_arm64

# 符號分析
nm -g TargetBinary                    # 匯出符號
nm -a TargetBinary                    # 全部符號
swift-demangle <mangled_name>         # Swift 符號還原

# class-dump
class-dump -H TargetBinary -o headers/
# 匯出 ObjC 類別及方法宣告到 headers/ 目錄
```

## Objective-C 執行環境分析

```text
訊息傳遞機制：
objc_msgSend(id self, SEL op, ...)  →  動態方法派發
  ↓
執行環境查找：
1. 類別方法列表 cache
2. 類別方法列表
3. 逐級父類別查找
4. +resolveInstanceMethod / +resolveClassMethod
5. forwardingTargetForSelector
6. methodSignatureForSelector + forwardInvocation
```

### Frida ObjC Hook

```javascript
// Hook 實例方法
var hook = ObjC.classes.ClassName["- instanceMethod:"];
Interceptor.attach(hook.implementation, {
    onEnter: function(args) {
        // args[0] = self, args[1] = selector, args[2+] = method args
        console.log("self: " + new ObjC.Object(args[0]));
        console.log("arg: " + args[2].toInt32());
    }
});

// Hook 類別方法
var hook = ObjC.classes.ClassName["+ classMethod:"];
Interceptor.attach(hook.implementation, { ... });

// 呼叫 ObjC 方法
var NSString = ObjC.classes.NSString;
var str = NSString.stringWithString_("test");
console.log(str.UTF8String());
```

## Swift 逆向

```text
Swift 名稱修飾（Name Mangling）：
$s10ModuleName5ClassC6method3argSi_tF
  │ │         │     │ │      │  │   └─ 參數型別
  │ │         │     │ │      │  └───── 回傳型別  
  │ │         │     │ │      └──────── 參數名
  │ │         │     │ └─────────────── 方法名
  │ │         │     └──────────────── 類別名(長度+名稱)
  │ │         └────────────────────── 模組名
  │ └──────────────────────────────── 識別符標識
  └────────────────────────────────── 全域標識

工具: swift-demangle, Hopper (自動還原)
```

## 越獄檢測繞過

```text
檢測方法分類：

1. 檔案系統檢查：
   □ /Applications/Cydia.app
   □ /var/lib/apt/
   □ /bin/bash
   □ /usr/sbin/sshd
   → Hook NSFileManager.fileExistsAtPath:

2. 沙箱逃逸檢測：
   □ fork() 是否成功（沙箱內禁止）
   □ system() 呼叫
   → Hook fork → 回傳 -1

3. Dyld 注入檢測：
   □ _dyld_get_image_count > 限制值
   → 限制回傳值在合理範圍

4. Scheme 檢測：
   □ cydia:// URL Scheme
   → Hook UIApplication.canOpenURL:

5. sysctl 檢測：
   □ CTL_KERN/KERN_PROC/KERN_PROC_PID → kinfo_proc
   → Hook sysctl → 清空 p_flag P_TRACED 位元
```

### Frida 統一繞過腳本

```javascript
// 檔案檢測繞過
var NSFileManager = ObjC.classes.NSFileManager;
var defaultManager = NSFileManager.defaultManager();
Interceptor.attach(defaultManager["- fileExistsAtPath:"].implementation, {
    onLeave: function(retval) {
        var path = ObjC.Object(args[2]).toString();
        if (path.includes("Cydia") || path.includes("apt") || 
            path.includes("sshd") || path.includes("bash")) {
            retval.replace(0); // false
        }
    }
});

// fork 繞過
Interceptor.replace(Module.findExportByName(null, "fork"), 
    new NativeCallback(function() { return -1; }, 'int', []));

// dyld 繞過
var _dyld_get_image_count = Module.findExportByName(null, "_dyld_get_image_count");
Interceptor.attach(_dyld_get_image_count, {
    onLeave: function(retval) {
        if (retval.toInt32() > 200) retval.replace(200);
    }
});
```

## 關鍵防護繞過清單

| 防護 | iOS 繞過方法 |
|------|-------------|
| App Store 加密 | frida-ios-dump / Clutch |
| SSL Pinning | Objection `ios sslpinning disable` / SSL Kill Switch 2 |
| 越獄檢測 | Objection `ios jailbreak disable` / 自訂 Frida Hook |
| 反除錯 (PT_DENY_ATTACH) | Frida 啟動後注入 / debugserver |
| 完整性校驗 | Hook MAC 檢查 / 程式碼簽章驗證 |
| 反注入 | 修改 Mach-O 去除 __RESTRICT 段 |
| Swift 混淆 | swift-demangle + LLM 輔助語意還原 |
| 螢幕截圖防護 | Hook UIScreen.mainScreen.snapshotViewAfterScreenUpdates |

Source: OWASP MSTG, frida-ios-dump, The iPhone Wiki
