#!/bin/bash
# PreToolUse / PostToolUse hook：委派工作目錄邊界 Sensor（Issue #134，§4 Guide→Sensor）
#
# MCP 呼叫無法指定 cwd，派發 prompt 裡的「工作目錄」段落只是寫給另一個 LLM 看的
# 道德勸說（Guide），沒有強制力。本 hook 補上確定性的偵測（Sensor）：
#
#   pre  — 檢查派發 prompt 是否含目標 worktree 絕對路徑；缺失/不符 → exit 2 阻擋。
#          放行時順手把主 repo 與其他 worktree 的 git status 存成快照。
#   post — 讀 pre 端快照做 before/after 差集，偵測目標 worktree 以外的實際寫入
#          與新增 commit。**只告警不阻斷**（PostToolUse 動作已完成，回捲無意義）。
#
# 掛載方式（.claude/settings.local.json，本地設定不進版控——沿用既有三個 hook 的慣例）：
#
#   "PreToolUse": [
#     { "matcher": "mcp__gemini-cli__ask-gemini",
#       "hooks": [{ "type": "command",
#         "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/wf-guard-delegate-cwd.sh pre" }] }
#   ],
#   "PostToolUse": [
#     { "matcher": "mcp__gemini-cli__ask-gemini",
#       "hooks": [{ "type": "command",
#         "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/wf-guard-delegate-cwd.sh post" }] }
#   ]
#
# False positive 防護：非委派工具、無 state 檔、branch 對不上、stage 非 2、
# 不在 worktree 中、路徑命中白名單、hook 自身例外 —— 任一命中即放行（exit 0）。

mode="${1:-}"
input=$(cat)

WF_HOOK_MODE="$mode" python3 -c '
import json, sys, glob, hashlib, time

# --- LOGIC-START ---
# 本區段由 tests/test_delegate_cwd_logic.py 抽出獨立執行，
# 因此必須自給自足：import 寫在區段內，只定義純函式，
# 不可有任何 side effect 或依賴區段外的變數。
import os, subprocess, tempfile, shutil

def whitelist_roots():
    """允許寫入的路徑根清單。一律動態解析，禁止硬編碼假設的標準路徑。"""
    roots = []

    def add(p):
        if p:
            roots.append(os.path.realpath(os.path.expanduser(p)))

    # git 內部：worktree 的所有 git 操作都經由主 repo 的 .git
    for arg in ("--git-common-dir", "--git-dir"):
        try:
            out = subprocess.check_output(
                ["git", "rev-parse", arg], stderr=subprocess.DEVNULL
            ).decode().strip()
            if out:
                add(out)
        except Exception:
            pass

    # Dart/Flutter 套件快取：先讀環境變數，未設才回退預設值
    add(os.environ.get("PUB_CACHE") or "~/.pub-cache")

    # Flutter/Dart SDK 根：從 which 反解（本機走 fvm，不在標準路徑）
    for exe in ("flutter", "dart"):
        w = shutil.which(exe)
        if w:
            add(os.path.dirname(os.path.dirname(os.path.realpath(w))))
    add(os.environ.get("FLUTTER_ROOT"))
    add("~/fvm")

    # 工具鏈的使用者層設定與快取
    for p in ("~/.gitconfig", "~/.config/git", "~/.ssh/known_hosts",
              "~/.dart-tool", "~/.flutter", "~/.dartServer",
              "~/.config/gh", "~/.npm", "~/.cache"):
        add(p)

    # 暫存目錄
    add(os.environ.get("TMPDIR") or tempfile.gettempdir())
    add("/tmp")
    add("/private/tmp")

    return sorted(set(r for r in roots if r))


def is_allowed(path, roots):
    """path 是否落在白名單內。

    兩側都在此處 realpath——不假設 roots 已正規化。macOS 上 /home 是 autofs
    掛載點（realpath 會展開成 /System/Volumes/Data/home），只對單側 realpath
    會讓比對失準；使用者的 PUB_CACHE 或 SDK 路徑經 symlink 時同理。
    以路徑分隔符為界，避免 /x/.pub-cache-evil 被 /x/.pub-cache 誤判命中。
    """
    rp = os.path.realpath(path)
    for r in roots:
        rr = os.path.realpath(r)
        if rp == rr or rp.startswith(rr + os.sep):
            return True
    return False


def diff_entries(before, after):
    """P-9：只回報 after 新增的項目，委派前既有的 dirty 檔案不算越界。

    輸入為 `git status --porcelain` 的行集合，回傳越界檔案的相對路徑集合。
    呼叫端已帶 `-c core.quotepath=false`，故非 ASCII 檔名為 UTF-8 原文而非
    八進位轉義；此處只需剝掉 git 對含空白檔名加的外層引號。
    """
    added = set(after) - set(before)
    out = set()
    for line in added:
        p = line[3:] if len(line) > 3 else ""
        # rename/copy 的 "old -> new"，取新路徑
        if " -> " in p:
            p = p.split(" -> ", 1)[1]
        p = p.strip().strip(chr(34))
        if p:
            out.add(p)
    return out
# --- LOGIC-END ---


def die_open():
    sys.exit(0)


def main():
    mode = os.environ.get("WF_HOOK_MODE", "")
    if mode not in ("pre", "post"):
        die_open()

    # P-1：payload 解析失敗一律放行
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            die_open()
        data = json.loads(raw)
    except Exception:
        die_open()

    # P-2：只管委派管道
    tool_name = data.get("tool_name") or data.get("toolCall", {}).get("name", "")
    if "ask-gemini" not in str(tool_name):
        die_open()

    # P-6（前半）：必須身處 worktree。--git-dir == --git-common-dir 表示在主 repo
    try:
        gd = os.path.realpath(subprocess.check_output(
            ["git", "rev-parse", "--git-dir"], stderr=subprocess.DEVNULL).decode().strip())
        gcd = os.path.realpath(subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], stderr=subprocess.DEVNULL).decode().strip())
    except Exception:
        die_open()
    if gd == gcd:
        die_open()

    # P-3：找 state 檔
    state_dir = os.environ.get("WF_STATE_DIR", "")
    state_files = []
    if state_dir and os.path.isdir(state_dir):
        state_files = glob.glob(os.path.join(state_dir, "*.json"))
    else:
        check = os.getcwd()
        while check and check != "/":
            wf = os.path.join(check, ".claude", "workflow-state")
            if os.path.isdir(wf):
                fs = [f for f in glob.glob(os.path.join(wf, "*.json"))
                      if not os.path.basename(f).startswith(".batch-")]
                if fs:
                    state_files = fs
                    break
            check = os.path.dirname(check)
    if not state_files:
        die_open()

    # P-4：branch 必須對得上 state 檔
    try:
        branch = subprocess.check_output(
            ["git", "branch", "--show-current"], stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        die_open()
    if not branch:
        die_open()
    slug = branch.replace("/", "-")
    matched = next((f for f in state_files if os.path.basename(f) == slug + ".json"), None)
    if not matched:
        die_open()

    try:
        st = json.load(open(matched))
        if not isinstance(st, dict):
            die_open()
    except Exception:
        die_open()

    # P-5：只有 STAGE 2 會委派 implementer
    if str(st.get("stage", "")) != "2":
        die_open()

    # P-6（後半）：目標 worktree 路徑
    target = None
    try:
        out = subprocess.check_output(
            ["git", "worktree", "list", "--porcelain"], stderr=subprocess.DEVNULL).decode()
        cur = None
        for line in out.splitlines():
            if line.startswith("worktree "):
                cur = line[len("worktree "):].strip()
            elif line.startswith("branch ") and cur:
                if line[len("branch "):].strip() == "refs/heads/" + branch:
                    target = os.path.realpath(cur)
                    break
    except Exception:
        die_open()
    if not target:
        die_open()

    if mode == "pre":
        run_pre(data, target, gcd)
    else:
        run_post(st, branch, target, gcd)


def repo_paths(target, gcd):
    """需要監看的 repo：主 repo + 所有非目標 worktree。"""
    paths = []
    try:
        out = subprocess.check_output(
            ["git", "worktree", "list", "--porcelain"], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            if line.startswith("worktree "):
                p = os.path.realpath(line[len("worktree "):].strip())
                if p != target:
                    paths.append(p)
    except Exception:
        pass
    return paths


def take_status(paths):
    """R-3：只跑 git status --porcelain，不做全檔案系統遍歷（實測 23ms）。

    --untracked-files=normal 天然滿足 P-10：.gitignore 內的檔案不會出現。
    """
    snap = {}
    for p in paths:
        try:
            entries = subprocess.check_output(
                ["git", "-C", p, "-c", "core.quotepath=false",
                 "status", "--porcelain", "--untracked-files=normal"],
                stderr=subprocess.DEVNULL).decode().splitlines()
            head = subprocess.check_output(
                ["git", "-C", p, "rev-parse", "HEAD"], stderr=subprocess.DEVNULL).decode().strip()
            snap[p] = {"entries": entries, "head": head}
        except Exception:
            continue
    return snap


def snapshot_path(gcd):
    key = hashlib.sha1(gcd.encode()).hexdigest()[:12]
    tmp = os.environ.get("TMPDIR") or tempfile.gettempdir()
    return os.path.join(tmp, "wf-cwd-sensor-" + key + ".json")


def run_pre(data, target, gcd):
    ti = data.get("tool_input", {})
    prompt = ti.get("prompt") if isinstance(ti, dict) else None
    if not isinstance(prompt, str):
        die_open()

    # R-4：只比對「是否含目標 worktree 絕對路徑」，不比對整段格式
    if target not in prompt:
        if "工作目錄" not in prompt:
            sys.stderr.write(
                "[WF-CWD BLOCK] 派發 prompt 缺少〈工作目錄與邊界〉段落。\n"
                "MCP 呼叫無法指定 cwd，不寫死絕對路徑，子進程可能在主 repo 動手。\n"
                "請在 prompt 最前面加上：\n\n"
                "  工作目錄：" + target + "\n"
                "  🔴 邊界：不得存取或修改此目錄以外的任何檔案。若任務看似需要跨出\n"
                "     此目錄，停止並回報，不要自行動手。\n")
        else:
            sys.stderr.write(
                "[WF-CWD BLOCK] 派發 prompt 的工作目錄路徑與當前 workflow 不符。\n"
                "  應為：" + target + "\n"
                "  但 prompt 中未出現該路徑（可能是舊 worktree 的過期路徑）。\n"
                "請更正為上述路徑後重新派發。\n")
        # BUG-1 教訓：PreToolUse 只有 exit 2 具阻擋力，exit 1 屬 non-blocking
        sys.exit(2)

    # 放行 → 存快照供 post 端差集（搭便車，零額外掛載點）
    try:
        snap = {"ts": time.time(), "repos": take_status(repo_paths(target, gcd))}
        with open(snapshot_path(gcd), "w") as f:
            json.dump(snap, f)
    except Exception:
        pass
    sys.exit(0)


def run_post(st, branch, target, gcd):
    sp = snapshot_path(gcd)
    try:
        snap = json.load(open(sp))
    except Exception:
        die_open()  # 未配對（pre 未跑或已被清理）
    finally:
        try:
            os.remove(sp)
        except Exception:
            pass

    # 孤兒快照：超過一小時視為過期，不告警
    if time.time() - float(snap.get("ts", 0)) > 3600:
        die_open()

    before = snap.get("repos", {})
    after = take_status(list(before.keys()))

    violations = {}
    new_commits = {}
    roots = whitelist_roots()
    for repo, aft in after.items():
        bef = before.get(repo, {})
        added = diff_entries(bef.get("entries", []), aft.get("entries", []))
        # P-7/P-8：套白名單過濾（git status 只回報工作區檔案，讀取行為天然不入列）
        bad = sorted(p for p in added if not is_allowed(os.path.join(repo, p), roots))
        if bad:
            violations[repo] = bad
        if bef.get("head") and aft.get("head") and bef["head"] != aft["head"]:
            new_commits[repo] = {"before": bef["head"], "after": aft["head"]}

    if not violations and not new_commits:
        sys.exit(0)

    lines = ["", "=" * 68,
             "[WF-CWD ALERT] 偵測到委派子進程在目標 worktree 外造成變動",
             "=" * 68,
             "目標 worktree：" + target, ""]
    for repo, paths in violations.items():
        lines.append("越界寫入 @ " + repo)
        lines.extend("    - " + p for p in paths)
    for repo, hs in new_commits.items():
        lines.append("越界 commit @ " + repo)
        lines.append("    " + hs["before"][:8] + " → " + hs["after"][:8])
    lines += ["",
              "若這是你自己的改動請忽略；否則請檢查該子進程的派發 prompt 是否寫對工作目錄，",
              "並確認上列變動是否需要回退。",
              "=" * 68, ""]
    sys.stderr.write("\n".join(lines) + "\n")

    # AC-B5：稽核紀錄。寫入失敗一律吞掉，不影響流程
    try:
        wf_dir = None
        check = os.getcwd()
        while check and check != "/":
            d = os.path.join(check, ".claude", "workflow-state")
            if os.path.isdir(d):
                wf_dir = d
                break
            check = os.path.dirname(check)
        if wf_dir:
            rec = {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "branch": branch,
                "worktree": target,
                "paths": {k: v for k, v in violations.items()},
                "new_commits": new_commits,
            }
            with open(os.path.join(wf_dir, "cwd-violations.log"), "a") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass

    # U-1：只告警不阻斷
    sys.exit(0)


# P-11：fail-open — hook 壞掉不能連帶讓整條 workflow 不能動
try:
    main()
except SystemExit:
    raise
except BaseException:
    sys.exit(0)
' <<< "$input"

exit $?
