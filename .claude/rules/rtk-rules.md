# RTK - Rust Token Killer (Google Antigravity)

**Usage**: Token-optimized CLI proxy for shell commands.

## Rule

Always prefix shell commands with `rtk` to minimize token consumption.

Examples:

```bash
rtk git status
rtk cargo test
rtk ls src/
rtk grep "pattern" src/
rtk find "*.rs" .
rtk docker ps
rtk gh pr list
```

## Meta Commands

```bash
rtk gain              # Show token savings
rtk gain --history    # Command history with savings
rtk discover          # Find missed RTK opportunities
rtk proxy <cmd>       # Run raw (no filtering, for debugging)
```

## 🔴 grep 要「原文」時，別用 grep

輸出過濾是**環境層**行為，不是 `rtk` 前綴造成的——`grep` 不論加不加 `rtk`，命中數一多就會被壓成摘要：

```
grep -n "packageVersion" lib/src/version.dart
→ 2 matches in 0 files:
  [+2 more]          ← 值不見了
```

所以「拿掉 rtk 就能看到原文」是**錯的**，白費一次呼叫。依意圖選工具：

| 意圖 | 用什麼 | 理由 |
|------|--------|------|
| 找符號／檔案分佈（要輪廓） | `rtk grep` | 實測 144 行壓到十幾行；`rtk gain` 顯示 grep 佔總節省 75%（78% 壓縮率） |
| 讀某檔案的**具體值**（版號、常數、簽名） | **Read 工具** | 一次到位，且合乎「原生工具優先」 |
| 必須用 grep 且要看到原文 | `rtk proxy grep ...` | `proxy` 的定義就是不過濾 |

**判準**：輸出是拿來**下判斷的證據**（版號、SHA、diff 逐字比對）就要原文；只是用來**定位**（哪些檔案有這個符號）就用 `rtk grep`。

> 實例：為了讀出 `version: 2.1.0`，先跑 `grep` 拿到 `1 matches in 0 files`，再拿掉 `rtk` 重跑、仍是摘要——來回三四次才改用 Read。歸因錯誤比多花的 token 貴。

## Why

RTK filters and compresses command output before it reaches the LLM context, saving 60-90% tokens on common operations. Always use `rtk <cmd>` instead of raw commands.

## Token 最佳化與寫入規範 (Token Optimization Rules)

在 Claude Code 與 Antigravity-CLI 中執行時，必須遵守以下 Token 節省準則：

### 1. 程式碼與檔案變更
* 優先使用原生工具（如 `write_file`/`write_to_file`、`replace_file_content`）。
* **嚴禁**在 shell 中使用 `echo "..." > file`、`cat <<EOF > file` 或 `sed`/`awk` 等指令進行程式碼寫入或編輯。這能節省高達 90% 的 Input Token。

### 2. 指令代理分流
* **必須加上 `rtk` 前綴** 的指令：`git`, `grep`, `find`, `ls`, `ps`, `gh`, `flutter`, `dart` 等（減少 60-90% 輸出 token）。
* **絕對不要加上 `rtk` 前綴** 的指令：`echo`, `cd`, `pwd`, `export`, `alias` 等內建指令（避免無謂的 API 呼叫與環境解析錯誤）。

**「一律加」是預設，不必逐次評估**——判斷成本比偶爾漏壓縮更貴。唯一例外是輸出已被自身 flag 限死在數行內時（`git log --oneline -5`、`git branch --show-current`、`git rev-list -n 1`、`grep -c`），加不加實測輸出一字不差，可省則省但不值得為此猶豫。

反面佐證：`rtk gain` 顯示 `rtk read` 呼叫 516 次卻只省 11.8%——**對本來就精簡的輸出套 rtk，效益趨近於零**；而 `rtk grep` 604 次省下 78%，是真正該用的地方。
