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
