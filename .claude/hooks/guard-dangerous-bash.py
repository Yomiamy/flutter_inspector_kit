#!/usr/bin/env python3
# PreToolUse(Bash) hook：危險指令分級（G1-B），常駐生效，與 workflow 狀態無關
# 規格：docs/features/2026-11-21-main-session-guard-and-missing-coverage.md §4.2
#
#   deny：rm 同時帶 -r/-R 與 -f，目標為 / ~ $HOME ${HOME}（含尾斜線與 /*）；force push 到 main
#         （-f / --force* / +refspec；省略 refspec 或 HEAD 時看該處當前 branch；--all／--branches 視同含 main）
#   ask ：git reset --hard；git checkout . / git restore .；git clean 帶 -f
#
# 以 shlex 切詞，依 ; && || | & ( ) 換行切成子指令逐段比對；剝除前綴 sudo、rtk（含 rtk proxy）與 VAR=val；
# 子指令 `cd <dir>` 與 `git -C <dir>` 會更新判斷 branch 用的目錄。heredoc 內文先剝除，不當指令比對。
#
# fail-open：解析失敗或任何例外 → 放行（exit 0、無輸出），settings 亦設 onFailure: continue。
# Bash 是凍結 hook（fail-closed）壞掉時的自救通道；本護欄壞掉只退回「沒有護欄」的現狀。
#
# 已知盲區（規格 §5.3）：字串層比對。執行期變數展開（$X 展開成 /）、腳本檔與 bash -c 內的指令、
# 反引號、混淆寫法（$IFS、base64）都偵測不到；引號不平衡等 shlex 無法解析的部分放行（之前已切出的子指令照判）。
# shlex 把詞中的 # 當註解起點（如 echo foo#bar; rm -rf ~、URL 含 #），同一行其後的內容不比對。
# git push 帶值選項的長選項縮寫（唯一前綴，如 --push-opt ci.skip、--rep x）不認得，值會被當成 refspec；完整寫法與 -o 已處理。
# 偶數個反斜線結尾的行會被誤當行接續（echo a\\⏎rm -rf ~），下一行併進上一段。
# 以保留字或前綴開頭的段漏判：{ … }、then、do、!、time、env、command、xargs、sudo -u root。
# 雙引號內的 "$(…)" 不比對。
# git --git-dir <dir>（空格分隔）：值被當成子指令，整段漏判。
# git checkout ./ 不算 git checkout .，不 ask。
# 子 shell 內的 cd 會延續到外層，後續 branch 判斷可能指向錯的目錄。
# git push --mirror（不帶 -f 也會強制覆寫遠端 main）不比對。
# branch 在執行前查一次：同一指令內先 git switch/checkout 再省略 refspec 的 force push（git switch main && git push -f）判不到。
# hook ask 在 bypassPermissions 下不保證跳出確認，dontAsk／-p 下會變成拒絕；不可逆項目因此一律放在 deny 層。
#
# 掛載於 .claude/settings.json（matcher: Bash）；條目由 tests/test_project_settings_hooks.sh 鎖定。
import io
import json
import os
import re
import shlex
import subprocess
import sys

SEP_CHARS = set(";&|()\n")
HEREDOC_BODY = re.compile(r"(<<-?[ \t]*(['\"]?)(\w+)\2[^\n]*)\n.*?\n[ \t]*\3[ \t]*(?=\n|$)", re.S)
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


class KeepNewline(io.StringIO):
    # shlex 跳過 # 註解時用 readline() 吃整行，連結尾 \n 一起吃掉；把 \n 退回，下一行才不會併進上一段
    def readline(self, *args):
        line = super().readline(*args)
        if line.endswith("\n"):
            self.seek(self.tell() - 1)
        return line


def segments(cmd):
    src = HEREDOC_BODY.sub(r"\1", cmd).replace("\\\n", "")  # 行接續（\ + 換行）依 bash 語意併回同一行
    lx = shlex.shlex(KeepNewline(src), posix=True, punctuation_chars=";&|()<>\n")
    lx.whitespace = " \t\r"
    lx.whitespace_split = True
    seg, skip = [], False
    for tok in lx:
        sep = bool(tok) and set(tok) <= SEP_CHARS  # 引號產生的空參數（""）是一般 token，不是分隔符
        if skip and not sep:  # 目標 token 才丟；遇到分隔符不吞（echo '>'; git push -f 的引號 > 被誤當重導向）
            skip = False
        elif set(tok) <= set("<>&") and set(tok) & set("<>"):  # 重導向：丟掉運算子、目標與前置 fd（2>&1 → 2、>&、1）
            if seg and seg[-1].isdigit():
                seg.pop()
            skip = True
        elif sep:
            yield seg
            seg, skip = [], False
        else:
            seg.append(tok)
    yield seg


def short_has(arg, ch):
    return arg.startswith("-") and not arg.startswith("--") and ch in arg[1:]


def branch_of(d):
    try:
        return subprocess.check_output(
            ["git", "-C", d, "branch", "--show-current"],
            stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""


def rm_hit(args):
    flags, targets, opts_done = [], [], False
    for a in args:
        if not opts_done and a == "--":
            opts_done = True
        elif not opts_done and a.startswith("-"):
            flags.append(a)
        else:
            targets.append(a)
    recursive = any(short_has(f, "r") or short_has(f, "R") or f == "--recursive" for f in flags)
    force = any(short_has(f, "f") or f == "--force" for f in flags)

    def critical(t):
        if not t:  # 空參數（rm -rf ""）什麼都不刪
            return False
        t = t[:-2] if t.endswith("/*") else t
        return (t.rstrip("/") or "/") in ("/", "~", "$HOME", "${HOME}")

    return recursive and force and any(critical(t) for t in targets)


PUSH_VALUE_OPTS = ("--push-option", "--repo", "--receive-pack", "--exec", "--recurse-submodules")  # 值在下一個 token 的選項


def push_main_hit(args, d):
    pos, opts, skip = [], [], False
    for a in args:
        if skip:
            skip = False  # 選項的值不是 refspec（git 的第一個位置參數永遠是 repository，--repo 的值不佔位）
        elif a.startswith("-"):
            opts.append(a)
            skip = a in PUSH_VALUE_OPTS or (not a.startswith("--") and a.find("o") == len(a) - 1)  # 短旗標串以 o 結尾（-o、-fo）取下一個 token 當值
        else:
            pos.append(a)
    args = opts
    refspecs = pos[1:]
    # 短旗標串中 -o 吃掉其後整串當值（-oflag 的 f 是值），只有 o 之前的 f 算 force
    force = any(a.startswith("--force") or short_has(a.split("o", 1)[0], "f") for a in args) \
        or any(r.startswith("+") for r in refspecs)
    if not force:
        return False
    dsts = [r.lstrip("+").split(":")[-1] for r in refspecs] or (["main"] if {"--all", "--branches"} & set(args) else ["HEAD"])
    return any(x in ("main", "refs/heads/main") or (x == "HEAD" and branch_of(d) == "main")
               for x in dsts)


def classify(seg, d):
    """回傳 (level, 規則名) 或 None。"""
    if os.path.basename(seg[0]) == "rm":
        return ("deny", "rm -rf 目標為 / ~ $HOME") if rm_hit(seg[1:]) else None
    if os.path.basename(seg[0]) != "git":
        return None
    i = 1
    while i < len(seg) and seg[i].startswith("-"):
        if seg[i] == "-C" and i + 1 < len(seg):
            d = os.path.join(d, os.path.expanduser(seg[i + 1]))
        i += 2 if seg[i] in ("-C", "-c") else 1
    if i >= len(seg):
        return None
    sub, args = seg[i], seg[i + 1:]
    if sub == "push" and push_main_hit(args, d):
        return ("deny", "force push 到 main")
    if sub == "reset" and "--hard" in args:
        return ("ask", "git reset --hard")
    if sub in ("checkout", "restore") and "." in args:
        return ("ask", "git " + sub + " .")
    if sub == "clean" and any(short_has(a, "f") or a == "--force" for a in args):
        return ("ask", "git clean -f")
    return None


def main():
    data = json.loads(sys.stdin.read())
    cmd = data["tool_input"]["command"]
    d = data.get("cwd") or os.getcwd()
    hits = []
    try:
        for seg in segments(cmd):
            while seg and (seg[0] in ("sudo", "rtk") or ASSIGN.match(seg[0])):
                seg = seg[2:] if seg[:2] == ["rtk", "proxy"] else seg[1:]
            if not seg:
                continue
            if seg[0] == "cd" and len(seg) > 1:
                target = os.path.join(d, os.path.expanduser(seg[1]))
                if os.path.isdir(target):  # cd 失敗時 shell 留在原目錄，後續段仍在那裡執行
                    d = target
                continue
            hit = classify(seg, d)
            if hit:
                hits.append(hit + (" ".join(seg),))
    except ValueError:
        pass  # shlex 解析不了的尾段（引號不平衡）放行，已切出的子指令照判
    for level in ("deny", "ask"):
        found = [h for h in hits if h[0] == level]
        if found:
            reason = "[WF-BASH %s] 命中規則：%s｜子指令：%s" % (
                level.upper(), "；".join(h[1] for h in found), "；".join(h[2] for h in found))
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": level,
                "permissionDecisionReason": reason}}, ensure_ascii=False))
            return


try:
    main()
except Exception:
    sys.exit(0)  # fail-open（見檔首）
