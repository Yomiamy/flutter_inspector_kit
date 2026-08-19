#!/usr/bin/env python3
"""wf-guard-delegate-cwd.sh 的純函式自我檢查。

執行：python3 .claude/hooks/tests/test_delegate_cwd_logic.py
成功印 OK 並以 0 離開；任一 assert 失敗即非零離開。

只涵蓋「會反覆修改且改錯代價最高」的純函式（白名單比對、路徑判定、
差集計算）。端到端情境（hook 實際被 Claude Code 觸發）需偽造整個執行
環境，harness 複雜度遠超被測腳本，走手動驗證清單（見計畫 §5.4）。
"""
import os
import sys

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "wf-guard-delegate-cwd.sh")


def load_logic():
    """從 hook 腳本抽出 python 段落並執行，取得其中定義的純函式。"""
    src = open(HOOK).read()
    start = src.index("# --- LOGIC-START ---")
    end = src.index("# --- LOGIC-END ---")
    ns = {}
    exec(compile(src[start:end], HOOK, "exec"), ns)
    return ns


def test_is_allowed_path():
    ns = load_logic()
    is_allowed = ns["is_allowed"]
    roots = ["/repo/.git", "/home/u/.pub-cache"]

    assert is_allowed("/repo/.git", roots)
    assert is_allowed("/repo/.git/worktrees/x/HEAD", roots)
    assert is_allowed("/home/u/.pub-cache/hosted/foo/bar.dart", roots)
    # 黑名單：同一顆 repo 內，.git 以外的工作區檔案
    assert not is_allowed("/repo/lib/main.dart", roots)
    assert not is_allowed("/repo/docs/x.md", roots)
    # 前綴相似但不同目錄，不可誤判為命中
    assert not is_allowed("/repo/.github/workflows/ci.yml", roots)
    assert not is_allowed("/home/u/.pub-cache-evil/x", roots)


def test_whitelist_roots():
    ns = load_logic()
    roots = ns["whitelist_roots"]()
    assert isinstance(roots, list) and roots
    assert all(os.path.isabs(r) for r in roots), "白名單必須全為絕對路徑"
    # PUB_CACHE 未設時回退 ~/.pub-cache
    assert any("pub-cache" in r for r in roots)


def test_diff_entries():
    ns = load_logic()
    diff = ns["diff_entries"]
    before = {" M lib/a.dart", "?? tmp.txt"}
    after = {" M lib/a.dart", "?? tmp.txt", " M lib/b.dart"}
    # P-9：只回報新增的，既有 dirty 不算越界
    assert diff(before, after) == {"lib/b.dart"}
    assert diff(before, before) == set()
    # 委派前 dirty、委派後變乾淨 → 不是越界
    assert diff(after, before) == set()


if __name__ == "__main__":
    test_is_allowed_path()
    test_whitelist_roots()
    test_diff_entries()
    print("OK")
