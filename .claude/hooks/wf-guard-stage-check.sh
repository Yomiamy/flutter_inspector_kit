#!/bin/bash
# PreToolUse(Agent / invoke_subagent) hook for Claude Code & Antigravity (agy).
# Guardrail: prevents dispatching `responder` agent without advancing state to STAGE 5.
#
# False positive protection:
#   - Only triggers if `responder` agent is being dispatched.
#   - Only acts if an active workflow state file exists in the worktree/repo.
#   - Bypasses immediately (exit 0) if no workflow state file is found.

input=$(cat)

# Run verification in python
python3 -c '
import json, sys, os, glob, subprocess

try:
    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)
    data = json.loads(raw)
except Exception:
    sys.exit(0)

# Check tool name
tool_name = data.get("tool_name") or data.get("toolCall", {}).get("name", "")

# Extract invoked agent names/types across Claude Code & Antigravity schemas
agent_types = []

# Claude Code schema: .tool_input.name / .tool_input.subagent_type
tool_input = data.get("tool_input", {})
if isinstance(tool_input, dict):
    if "name" in tool_input and isinstance(tool_input["name"], str):
        agent_types.append(tool_input["name"].lower())
    if "subagent_type" in tool_input and isinstance(tool_input["subagent_type"], str):
        agent_types.append(tool_input["subagent_type"].lower())
    if "agent" in tool_input and isinstance(tool_input["agent"], str):
        agent_types.append(tool_input["agent"].lower())

# Antigravity schema: .toolCall.args.Subagents / .toolCall.args.TypeName
tc = data.get("toolCall", {})
tc_args = tc.get("args", tc.get("Arguments", {}))
if isinstance(tc_args, dict):
    if "TypeName" in tc_args and isinstance(tc_args["TypeName"], str):
        agent_types.append(tc_args["TypeName"].lower())
    if "name" in tc_args and isinstance(tc_args["name"], str):
        agent_types.append(tc_args["name"].lower())
    if "subagents" in tc_args and isinstance(tc_args["subagents"], list):
        for sa in tc_args["subagents"]:
            if isinstance(sa, dict) and "TypeName" in sa and isinstance(sa["TypeName"], str):
                agent_types.append(sa["TypeName"].lower())
    if "Subagents" in tc_args and isinstance(tc_args["Subagents"], list):
        for sa in tc_args["Subagents"]:
            if isinstance(sa, dict) and "TypeName" in sa and isinstance(sa["TypeName"], str):
                agent_types.append(sa["TypeName"].lower())

# If responder is not being dispatched, allow immediately
if not any("responder" in a for a in agent_types):
    sys.exit(0)

# Check if there is an active workflow state file in current directory or repo
state_dir = os.environ.get("WF_STATE_DIR", "")
state_files = []
if state_dir and os.path.isdir(state_dir):
    state_files = glob.glob(os.path.join(state_dir, "*.json"))
else:
    # Look in .claude/workflow-state in current dir or up to git root
    cwd = os.getcwd()
    check_dir = cwd
    while check_dir and check_dir != "/":
        wf_dir = os.path.join(check_dir, ".claude", "workflow-state")
        if os.path.isdir(wf_dir):
            files = [f for f in glob.glob(os.path.join(wf_dir, "*.json")) if not os.path.basename(f).startswith(".batch-")]
            if files:
                state_files = files
                break
        check_dir = os.path.dirname(check_dir)

# If no state file found, bypass (allow out-of-workflow standalone calls)
if not state_files:
    sys.exit(0)

# Match state file strictly with current branch
matched_file = None
try:
    branch = subprocess.check_output(["git", "branch", "--show-current"], stderr=subprocess.DEVNULL).decode().strip()
    if branch:
        branch_slug = branch.replace("/", "-")
        for sf in state_files:
            if os.path.basename(sf) == f"{branch_slug}.json":
                matched_file = sf
                break
except Exception:
    pass

# If the current branch has no matching workflow state, bypass immediately
# (Prevents false positives when a workflow is active on another worktree/branch)
if not matched_file:
    sys.exit(0)

# Inspect state
try:
    with open(matched_file, "r") as f:
        st_data = json.load(f)
    stage = str(st_data.get("stage", ""))
    
    # In STAGE 5, stage should be "5" or "responder"
    if stage in ("5", "responder"):
        sys.exit(0)
    
    rel_path = os.path.relpath(matched_file)
    sys.stderr.write(f"""[WF-GUARD BLOCK] 偵測到派發 responder agent，但當前 workflow 狀態為 stage: "{stage}"（非 stage: 5）。
依據獨立入口規範，進入 STAGE 5 回覆 PR Review 前必須先推進狀態機。
請先執行：
  wf-state.sh advance {rel_path} 5 --confirmed
（或若為新對話獨立入口：wf-state.sh init --mode jump --stage 5 --branch <branch>）
推進狀態完成後，方可再次派發 responder。\n""")
    sys.exit(1)
except Exception:
    sys.exit(0)
' <<< "$input"

exit $?
