# APK 安全測試速查

> 基於 OWASP MASTG（Mobile Application Security Testing Guide）整理。
> 涵蓋靜態分析、動態分析、網路通訊、資料儲存、認證授權、程式碼保護六大維度。

---

## 靜態分析檢查清單

### Manifest 審計

```text
□ android:debuggable="true" → 可除錯（生產環境不應出現）
□ android:allowBackup="true" → 資料可備份提取
□ android:exported="true" 的元件 → 暴露的 Activity/Service/Receiver/Provider
□ 自訂權限 protectionLevel → 是否為 normal（應為 signature）
□ intent-filter 中的 scheme → 自訂 deeplink 是否可被劫持
□ android:usesCleartextTraffic="true" → 允許明文 HTTP
□ minSdkVersion 過低 → 可能缺少安全特性
```

### 程式碼審計關鍵點

```text
□ 硬編碼密鑰/Token（搜尋 "key"、"secret"、"password"、"api_key"）
□ 不安全的亂數（java.util.Random 而非 SecureRandom）
□ 不安全的加密（ECB 模式、DES、MD5 用於密碼）
□ WebView 設定（setJavaScriptEnabled + addJavascriptInterface = RCE 風險）
□ SQL 注入（rawQuery 拼接使用者輸入）
□ 路徑遍歷（ContentProvider 的 openFile 未校驗路徑）
□ 日誌洩漏（Log.d/Log.i 輸出敏感資訊）
□ 剪貼簿洩漏（ClipboardManager 儲存敏感資料）
□ 隱式 Intent 洩漏（sendBroadcast 未指定包名）
```

### 第三方函式庫審計

```text
□ 過時的 OkHttp/Retrofit 版本（已知漏洞）
□ 過時的 WebView 核心
□ 含已知漏洞的 SDK（檢查 CVE）
□ 廣告 SDK 資料蒐集範圍
□ 推播 SDK 設定（是否洩漏 token）
```

---

## 動態分析檢查清單

### Frida Hook 優先目標

| 目標 | Hook 點 | 目的 |
|------|---------|------|
| 登入認證 | `LoginActivity.login()` | 觀察憑證處理 |
| 簽章產生 | `*Sign*`、`*sign*`、`*encrypt*` | 還原簽章演算法 |
| SSL Pinning | `CertificatePinner.check` | 繞過抓包 |
| Root 檢測 | `*root*`、`*su*`、`*magisk*` | 繞過檢測 |
| 加密操作 | `javax.crypto.Cipher` | 提取密鑰/IV |
| Token 儲存 | `SharedPreferences.getString` | 觀察 token 讀寫 |
| 網路請求 | `OkHttpClient.newCall` | 觀察請求建構 |

### 常用 Frida 一行命令

```bash
# 追蹤所有加密操作
frida-trace -U -f com.target.app -j '*Cipher*!*'

# 追蹤所有 HTTP 請求
frida-trace -U -f com.target.app -j '*OkHttp*!*'

# 追蹤 SharedPreferences 讀寫
frida-trace -U -f com.target.app -j '*SharedPreferences*!*'

# 追蹤所有 native 函式呼叫
frida-trace -U -f com.target.app -i 'Java_*'
```

### Objection 快速命令

```bash
# 連線
objection -g com.target.app explore

# 常用命令
android hooking list activities
android hooking list services
android sslpinning disable
android root disable
android clipboard monitor
env                              # 查看應用目錄
sqlite connect <db_path>         # 連線資料庫
```

---

## 網路通訊安全

### 抓包設定

```text
方法 1: 系統代理 + Burp/mitmproxy
- 設定 WiFi 代理 → Burp 監聽位址
- 安裝 CA 憑證到裝置
- Android 7+ 需要 network_security_config 或 Frida 繞過

方法 2: VPN 模式（推薦）
- 使用 HttpCanary / Packet Capture
- 不需要 root，不需要設定代理
- 但無法解密 SSL Pinning 的流量

方法 3: Frida + r2frida
- 直接在程序內攔截網路呼叫
- 不受代理/VPN 限制
```

### 檢查項

```text
□ 是否使用 HTTPS（所有 API 呼叫）
□ 是否有 SSL Pinning（憑證綁定）
□ 憑證驗證是否正確（不接受自簽章）
□ 是否有憑證透明度（CT）檢查
□ API 密鑰是否在請求中明文傳輸
□ Token 是否有過期機制
□ 是否有請求簽章防竄改
□ 是否有重放攻擊防護（nonce/timestamp）
□ WebSocket 是否加密
□ 是否有敏感資料在 URL 參數中（會被日誌記錄）
```

---

## 資料儲存安全

### 檢查位置

| 位置 | 風險 | 檢查命令 |
|------|------|---------|
| SharedPreferences | 明文儲存 token/密碼 | `adb shell cat /data/data/pkg/shared_prefs/*.xml` |
| SQLite 資料庫 | 未加密的敏感資料 | `adb pull /data/data/pkg/databases/` |
| 外部儲存 | 任何應用可讀 | `adb shell ls /sdcard/Android/data/pkg/` |
| 應用日誌 | 洩漏除錯資訊 | `adb logcat \| grep pkg` |
| 備份檔案 | allowBackup=true | `adb backup -f backup.ab pkg` |
| 鍵盤快取 | 輸入歷史 | 檢查 `inputType` 是否為 `textPassword` |
| 截圖保護 | 敏感頁面可截圖 | 檢查 `FLAG_SECURE` |

### 加密儲存方案對比

| 方案 | 安全性 | 說明 |
|------|--------|------|
| SharedPreferences 明文 | ❌ | root 後直接讀取 |
| EncryptedSharedPreferences | ✓ | AndroidX Security 函式庫 |
| SQLCipher | ✓ | 加密 SQLite |
| Android Keystore | ✓✓ | 硬體級密鑰保護 |
| 自訂 AES 加密 | ⚠️ | 取決於密鑰管理 |

---

## 認證與授權

### 常見漏洞

| 漏洞 | 測試方法 |
|------|---------|
| 弱密碼策略 | 嘗試 123456、password 等 |
| 無鎖定機制 | 暴力破解登入介面 |
| Token 不過期 | 登出後重放舊 token |
| 越權存取 | 修改請求中的 user_id |
| 簡訊驗證碼可暴力破解 | 4/6 位數字無頻率限制 |
| OAuth 設定錯誤 | redirect_uri 可竄改 |
| 生物辨識繞過 | Hook BiometricPrompt |
| 裝置綁定繞過 | 修改 device_id |

### 測試 Payload

```bash
# 越權測試
curl -H "Authorization: Bearer USER_A_TOKEN" \
     "https://api.target.com/users/USER_B_ID/profile"

# Token 重放
# 1. 正常登入取得 token
# 2. 登出
# 3. 用舊 token 請求 → 應該回傳 401

# 簡訊驗證碼暴力破解
for code in $(seq 0000 9999); do
    curl -X POST "https://api.target.com/verify" \
         -d "phone=13800138000&code=$code"
done
```

---

## 程式碼保護評估

| 保護措施 | 檢測方法 | 繞過難度 |
|---------|---------|---------|
| ProGuard 混淆 | jadx 查看類名是否為 a/b/c | 低（只是重新命名） |
| 字串加密 | 搜尋解密函式，Hook 取得明文 | 中 |
| 反除錯 | 嘗試 attach debugger | 中（Frida 可繞過） |
| Root 檢測 | 在 root 裝置上執行 | 中（通用腳本繞過） |
| 模擬器檢測 | 在模擬器上執行 | 低-中 |
| 完整性校驗 | 修改 APK 後安裝 | 中（patch 校驗函式） |
| 加固/殼 | 查看進入類別和 .so | 中-高（需脫殼） |
| Native 保護 | 核心邏輯在 .so | 高（需 IDA 分析） |
| VMP 虛擬化 | 程式碼被虛擬化執行 | 極高 |

---

## 快速測試流程（30 分鐘）

```text
1. [5min] 解包 + Manifest 審計
   apktool d app.apk
   檢查 debuggable/allowBackup/exported/cleartext

2. [10min] 程式碼快速審計
   jadx -d out app.apk
   搜尋: password, key, secret, token, http://

3. [5min] 網路測試
   設定代理 → 操作 APP → 檢查是否有明文/弱加密

4. [5min] 儲存檢查
   adb shell → 檢查 shared_prefs 和 databases

5. [5min] 動態驗證
   Frida hook 關鍵函式 → 確認發現
```
