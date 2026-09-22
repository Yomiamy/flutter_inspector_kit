# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy for shell commands。輸出在進入 context 前先被壓縮，常見操作省 60–90% token。

> 本檔隨專案走。RTK 屬**個人環境**（需自行安裝 `rtk` 並設定 hook），未安裝時本檔規則自動失效——直接下原始指令即可，不會有任何錯誤。

## 🔴 先搞清楚：hook 會自動改寫，多數指令不用手動加

若已設定 `rtk hook claude`（PreToolUse, matcher `Bash`），這些指令**你直接下原始指令即可**，hook 會自動補上 `rtk`：

`git` · `grep` · `ls` · `ps` · `gh` · `cargo` · `docker`

**hook 不覆蓋、必須手動加 `rtk`** 的重度輸出指令：

`flutter` · `dart` · `find` · `npm`

```bash
flutter test          # ❌ 未壓縮
rtk flutter test      # ✅

git status            # ✅ hook 已自動改成 rtk git status
rtk git status        # ✅ 同上，寫不寫都一樣
```

**絕不加 `rtk`**：`echo`、`cd`、`pwd`、`export`、`alias` 等 shell 內建（hook 也不碰）。

> 上述名單由 `echo '{"tool_name":"Bash","tool_input":{"command":"<cmd>"}}' | rtk hook claude` 實測得出。hook 升級後名單可能變動，有疑慮就重跑這行驗證，別憑記憶。

## Meta Commands

```bash
rtk gain              # Show token savings
rtk gain --history    # Command history with savings
rtk discover          # Find missed RTK opportunities
rtk proxy <cmd>       # Run raw (no filtering, for debugging)
```

## 🔴 grep 要「原文」時，別用 grep

**`grep` 的壓縮擋不掉。** hook 在最外層自動套 `rtk grep`，命中數一多就被壓成摘要——連 `rtk proxy grep` 也救不了，因為 `proxy` 繞過的是 rtk 自身的過濾，繞不過 hook 的改寫：

```
grep -n "^def test_" test_route.py
→ 12 matches in 0 files:
  [+12 more]          ← 行號與內容全不見
```

所以「拿掉 rtk 就能看到原文」是**錯的**，白費一次呼叫。依意圖選工具：

| 意圖 | 用什麼 | 理由 |
|------|--------|------|
| 找符號／檔案分佈（要輪廓） | `grep`（hook 自動壓縮） | 實測 144 行壓到十幾行；`rtk gain` 顯示 grep 佔總節省 75%（78% 壓縮率） |
| 讀某檔案的**具體值**（版號、常數、簽名） | **Read 工具** | 一次到位，且合乎「原生工具優先」 |
| 必須逐行看原文 | `sed -n '10,40p' <file>` 或 `rtk proxy grep` | `sed` 不在 hook 名單內；`rtk proxy` 對部分情境有效，失敗就改用 `sed`/Read |

**判準**：輸出是拿來**下判斷的證據**（版號、SHA、diff 逐字比對、行號）就要原文；只是用來**定位**（哪些檔案有這個符號）就讓它壓。

> 實例：為了讀出 `version: 2.1.0`，先跑 `grep` 拿到 `1 matches in 0 files`，再拿掉 `rtk` 重跑、仍是摘要——來回三四次才改用 Read。歸因錯誤比多花的 token 貴。

## Token 最佳化與寫入規範

### 1. 程式碼與檔案變更
* 優先使用原生工具（`Write`、`Edit`），或需要語意化改寫時用 Serena。
* **嚴禁**在 shell 中使用 `echo "..." > file`、`cat <<EOF > file` 或 `sed`/`awk` 寫入程式碼。這能節省高達 90% 的 Input Token，也避免 shell 轉義踩坑。

### 2. 別對已經精簡的輸出套 rtk

輸出已被自身 flag 限死在數行內時（`git log --oneline -5`、`git branch --show-current`、`git rev-list -n 1`、`grep -c`），加不加實測輸出一字不差。

反面佐證：`rtk gain` 顯示 `rtk read` 呼叫 516 次卻只省 11.8%——**對本來就精簡的輸出套 rtk，效益趨近於零**；而 `rtk grep` 604 次省下 78%，是真正該用的地方。

不過這件事多半不必你操心：hook 覆蓋的指令一律自動改寫，不逐次評估反而省下判斷成本。真正要記的只有兩條——**`flutter`/`dart`/`find`/`npm` 要手動加**，以及**要原文時別用 grep**。
