# Frida Bypass Kit — Android 通用安全繞過框架

> 來源：[FridaBypassKit](https://github.com/okankurtuluss/FridaBypassKit)（2025）
> 適用場景：APK 動態分析時需要繞過 root 檢測、SSL pinning、模擬器檢測、反除錯

## 概述

FridaBypassKit 是一個整合了四大繞過能力的 Frida 腳本，無需針對特定 APP 客製，開箱即用。

## 四大繞過能力

### 1. Root 檢測繞過

- Hook `File.exists()` 隱藏 su 二進位檔
- 攔截 `Runtime.exec()` 的 root 檢查呼叫
- 從 PackageManager 隱藏 root 相關包（Magisk、SuperSU 等）
- 修改系統屬性使裝置看起來未 root

### 2. SSL Pinning 繞過

- Hook `TrustManagerImpl.verifyChain()`
- Hook `TrustManagerImpl.checkTrustedRecursive()`
- 繞過憑證鏈驗證
- 回傳空憑證鏈避免校驗
- 相容 OkHttp、Retrofit 和自訂實作

### 3. 模擬器檢測繞過

- 偽造 TelephonyManager 回傳值
- 回傳假電話號碼和電信業者名稱
- 修改 Build 屬性

### 4. 反除錯繞過

- Hook `Debug.isDebuggerConnected()`
- 阻止除錯器檢測
- 繞過反除錯檢查

## 使用方法

```bash
# 前置條件
pip install frida-tools
adb push frida-server /data/local/tmp/
adb shell chmod 755 /data/local/tmp/frida-server
adb shell su -c /data/local/tmp/frida-server &

# 注入目標 APP
frida -U -f com.example.app -l FridaBypassKit.js
```

## 其他推薦 Frida 繞過腳本

| 專案 | 特點 | 連結 |
|------|------|------|
| httptoolkit/frida-interception-and-unpinning | 直接 MitM 所有 HTTPS 流量 | [GitHub](https://github.com/httptoolkit/frida-interception-and-unpinning) |
| 0xCD4/SSL-bypass | 通用非客製 SSL 繞過 | [GitHub](https://github.com/0xCD4/SSL-bypass) |
| incogbyte/ssl-bypass gist | 繞過常見 SSL pinning 方法 | [Gist](https://gist.github.com/incogbyte/1e0e2f38b5602e72b1380f21ba04b15e) |
| Zero3141/Frida-OkHttp-Bypass | 專門針對 OkHttp CertificatePinner | [GitHub](https://github.com/Zero3141/Frida-OkHttp-Bypass) |

## 與本包的整合

在 `apk-reverse` 工作流中，當遇到以下情況時使用：

1. APP 檢測到 root 拒絕執行 → 啟用 Root Detection Bypass
2. 抓包時 HTTPS 請求看不到明文 → 啟用 SSL Pinning Bypass
3. APP 檢測到模擬器拒絕執行 → 啟用 Emulator Detection Bypass
4. 附加 Frida 後 APP 崩潰 → 啟用 Debug Detection Bypass

推薦組合使用：先跑完整 FridaBypassKit，再針對性調整。
