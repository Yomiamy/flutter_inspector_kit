#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

RETRO_CLAUDE="${WORKTREE_ROOT}/.claude/skills/retro/SKILL.md"
RETRO_AGENTS="${WORKTREE_ROOT}/.agents/skills/retro/SKILL.md"
WORKFLOW_SKILL="${WORKTREE_ROOT}/.claude/skills/gen-dev-workflow/SKILL.md"
BRAINSTORM_DOC="$(ls "${WORKTREE_ROOT}"/docs/brainstorm/*workflow-brainstorm.md 2>/dev/null | head -1)"

echo "=== Running Retro Skill Verification Tests ==="

# Test 1: Check skill files existence
echo -n "Test 1: Skill file exists in .claude and accessible in .agents... "
if [[ ! -f "${RETRO_CLAUDE}" ]]; then
  echo "FAILED: ${RETRO_CLAUDE} not found"
  exit 1
fi
if [[ ! -f "${RETRO_AGENTS}" ]]; then
  echo "FAILED: ${RETRO_AGENTS} not accessible"
  exit 1
fi
echo "PASSED"

# Test 2: Check YAML frontmatter
echo -n "Test 2: YAML frontmatter contains name: retro and valid description... "
if ! grep -q "^name: retro" "${RETRO_CLAUDE}"; then
  echo "FAILED: name: retro not found in frontmatter"
  exit 1
fi
if ! grep -q "description:" "${RETRO_CLAUDE}"; then
  echo "FAILED: description not found in frontmatter"
  exit 1
fi
echo "PASSED"

# Test 3: Check core Mechanical vs Judgement dichotomy rules
echo -n "Test 3: Mechanical vs Judgement dichotomy rules... "
if ! grep -q "Mechanical" "${RETRO_CLAUDE}" || ! grep -q "Judgement" "${RETRO_CLAUDE}"; then
  echo "FAILED: Mechanical vs Judgement not found in ${RETRO_CLAUDE}"
  exit 1
fi
if ! grep -q "自動化檢查" "${RETRO_CLAUDE}"; then
  echo "FAILED: 自動化檢查 not found in ${RETRO_CLAUDE}"
  exit 1
fi
if ! grep -E -q "(嚴禁|禁止).*prompt|rules" "${RETRO_CLAUDE}"; then
  echo "FAILED: prohibition against adding mechanical rules to prompt/rules not found"
  exit 1
fi
echo "PASSED"

# Test 4: Check STAGE 6 retro guidance in gen-dev-workflow
echo -n "Test 4: gen-dev-workflow STAGE 6 references retro... "
if ! grep -q "/retro" "${WORKFLOW_SKILL}"; then
  echo "FAILED: /retro reference not found in ${WORKFLOW_SKILL}"
  exit 1
fi
echo "PASSED"

# Test 5: Check brainstorm doc marks C5 as completed
echo -n "Test 5: brainstorm doc marks C5 as completed... "
if ! grep -E -q "\*\*C5\*\*.*✅ 已完成" "${BRAINSTORM_DOC}"; then
  echo "FAILED: C5 not marked as completed in ${BRAINSTORM_DOC}"
  exit 1
fi
echo "PASSED"

echo "=== All Retro Skill Tests Passed ==="
