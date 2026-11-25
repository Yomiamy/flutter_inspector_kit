#!/usr/bin/env python3
# PreToolUse(Edit|Write) hook：主對話 worktree 凍結（G1-A）
# 規格：docs/features/2026-11-21-main-session-guard-and-missing-coverage.md §4.1
#
# 只擋一種情況：hook 輸入的 cwd 位於某個 workflow 綁定的 linked worktree W 內，
# 而 Edit/Write 的 file_path 落在主 repo R 內、W 外，且該檔所屬的 checkout 是
# 主 checkout 或另一個已綁定 workflow 的 worktree（主 repo 的規劃文件原檔、其他 workflow）。
#
# 「綁定」對 cwd 與目標用同一個判定：路徑往上第一個含 .git 的目錄 D ——
#   .git 是目錄（主 checkout）或找不到 → 未綁定（不跑 git）；
#   .git 是檔案（linked worktree）且 D/.claude/workflow-state/<branch-slug>.json 存在 → 已綁定。
# 不掃描其他 worktree 的 state 檔：並行 workflow、主 repo 的 STAGE 0a/0b 不受影響；
# stage 值不參與判定（done/5/6 一樣綁定）。目標落在「未綁定的 linked worktree」（例如
# Claude Code isolation: worktree 建立的 subagent worktree）放行——那是另一份 checkout，
# 寫進去不會改到主 checkout 或其他 workflow。
# 目標路徑以詞法（normpath）與 realpath 各判一次，兩者都通過才放行（防 .. 與 symlink 逃逸）。
#
# fail-closed：任何未預期錯誤 → exit 2，訊息前綴 [WF-FREEZE ERROR]（越界為 [WF-FREEZE BLOCK]）。
# settings 的 onFailure: block 另外涵蓋腳本起不來、逾時——因此 python3 缺失、shebang 失敗、
# 執行權限遺失時，所有 session（含主 checkout）的 Edit/Write 都會被擋（mode 由 settings 測試鎖定）。
# cwd 在已綁定 worktree 內時，判定綁定就要跑 git：git 失敗會連 repo 外的寫入（scratchpad、memory）一起擋。
# 解除：Bash 不受本 hook 影響（可直接修本檔）；cd 離開 W 即解除綁定；
# 或由使用者在 .claude/settings.local.json 設 "disableAllHooks": true（官方開關，會停用全部 hooks）。
#
# 已知盲區（規格 §5.3）：
# - 只攔 Edit/Write 的 tool_input.file_path。Bash 寫檔（sed -i、>、tee、cp、mv）完全不受凍結。
# - cwd 漂回主 repo（cd <R>）時視為未綁定，此時寫主 repo 不會被擋。
# - macOS 檔案系統不分大小寫：以不同大小寫拼寫主 repo 路徑可繞過凍結判定。
# - EnterWorktree 時 settings 隨 session 移到 W，$CLAUDE_PROJECT_DIR 仍是 R；若 W 的 settings 比 R 新
#   （R 尚無本腳本），onFailure: block 會擋該 session 所有 Edit/Write，以 Bash `git -C <R> pull` 自救。
#
# 掛載於 .claude/settings.json（matcher: Edit|Write）；條目由 tests/test_project_settings_hooks.sh 鎖定。
import json
import os
import subprocess
import sys


def inside(p, root):
    return p == root or p.startswith(root + os.sep)


def checkout_of(path):
    """path 往上第一個含 .git 的目錄；找不到回傳 None。"""
    d = path
    while not os.path.lexists(os.path.join(d, ".git")):
        if d == os.path.dirname(d):
            return None
        d = os.path.dirname(d)
    return d


def bound_repo(d):
    """d 是已綁定 workflow 的 linked worktree → 回傳主 repo 根 R；否則 None。"""
    if d is None or os.path.isdir(os.path.join(d, ".git")):
        return None  # 主 checkout 不跑 git：fail-closed 的影響面只限 worktree 內的 session

    def git(*args):
        return subprocess.check_output(["git", "-C", d] + list(args),
                                       stderr=subprocess.DEVNULL, text=True).strip()

    branch = git("branch", "--show-current")
    state = os.path.join(d, ".claude", "workflow-state", branch.replace("/", "-") + ".json")
    if not os.path.isfile(state):
        return None
    return os.path.realpath(os.path.dirname(git("rev-parse", "--path-format=absolute", "--git-common-dir")))


def main():
    data = json.loads(sys.stdin.read())
    w = checkout_of(os.path.realpath(data.get("cwd") or os.getcwd()))
    r = bound_repo(w)
    if not r:
        sys.exit(0)
    fp = data["tool_input"]["file_path"]
    for p in (os.path.normpath(fp), os.path.realpath(fp)):
        if not inside(p, r) or inside(p, w):
            continue
        owner = checkout_of(p)
        if os.path.isfile(os.path.join(owner, ".git")) and not bound_repo(owner):
            continue  # 未綁定的 linked worktree（如 isolation subagent 的 worktree）
        rel = os.path.relpath(p, owner).split(os.sep)
        sys.stderr.write(
            "[WF-FREEZE BLOCK] 目標在主 repo 內、但不在本 session 綁定的 worktree 內。\n"
            "  被擋路徑：" + fp + "\n"
            "  綁定 worktree：" + w + "\n"
            "  請改寫：" + os.path.join(w, *rel) + "\n"
            "若這次寫入屬於主 repo 上另一個 workflow（STAGE 0a/0b），先 cd " + r + " 再寫。\n")
        sys.exit(2)
    sys.exit(0)


try:
    main()
except Exception as e:  # SystemExit 不是 Exception，正常 exit 不會落到這裡
    sys.stderr.write(
        "[WF-FREEZE ERROR] 凍結 hook 自身錯誤，依 fail-closed 拒絕本次寫入：" + repr(e) + "\n"
        "這不是越界判定。請停下回報使用者，由使用者決定處置"
        "（Bash 不受本 hook 影響；cd 離開 worktree 即解除綁定）。\n")
    sys.exit(2)
