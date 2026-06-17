#!/usr/bin/env bash
set -euo pipefail

TICKET_ID=""
PREFIX=""
SLUG=""
BASE_REF="origin/main"
WORKTREE_PARENT=""
SKIP_FETCH=0
SKIP_LOCAL_CONFIG_SYNC=0
COPIED_LOCAL_CONFIG_PATHS=()
LOCAL_CONFIG_SOURCE_ROOTS=()

usage() {
  cat <<'EOF'
Usage:
  prepare_issue_dev_workspace.sh --ticket-id "2351" --prefix "fix/" --slug "password-fields-validator-error" [options]
  prepare_issue_dev_workspace.sh --prefix "chore/" --slug "cleanup-skill-docs" [options]

Required:
  --prefix          Branch prefix such as fix/, feature/, chore/
  --slug            Lowercase kebab-case English slug

Optional:
  --issue-id        GitHub issue ID such as 2351 or BUG-2351
  --base            Base ref to branch from. Default: origin/main
  --worktree-parent Parent directory for the new worktree. Default: parent of current repo
  --skip-fetch      Skip fetching remote refs before creation
  --skip-local-config-sync
                    Do not copy local-only development config files into the new worktree
  --help            Show this message
EOF
}

add_local_config_source_root() {
  local source_root="$1"

  if [[ ! -d "${source_root}" ]]; then
    return 0
  fi

  local existing_source_root
  for existing_source_root in "${LOCAL_CONFIG_SOURCE_ROOTS[@]}"; do
    if [[ "${existing_source_root}" == "${source_root}" ]]; then
      return 0
    fi
  done

  LOCAL_CONFIG_SOURCE_ROOTS+=("${source_root}")
}

discover_local_config_source_roots() {
  LOCAL_CONFIG_SOURCE_ROOTS=()
  add_local_config_source_root "${REPO_ROOT}"

  local worktree_line
  local source_root
  while IFS= read -r worktree_line; do
    if [[ "${worktree_line}" != worktree\ * ]]; then
      continue
    fi

    source_root="${worktree_line#worktree }"
    if [[ "${source_root}" == "${REPO_ROOT}" ]]; then
      continue
    fi

    if [[ -e "${source_root}/.env" || -e "${source_root}/.env.local" ]]; then
      add_local_config_source_root "${source_root}"
    fi
  done < <(git worktree list --porcelain)
}

copy_local_config_path() {
  local relative_path="$1"
  local source_root
  local source_path
  local target_path="${WORKTREE_PATH}/${relative_path}"

  for source_root in "${LOCAL_CONFIG_SOURCE_ROOTS[@]}"; do
    source_path="${source_root}/${relative_path}"
    if [[ ! -e "${source_path}" ]]; then
      continue
    fi

    mkdir -p "$(dirname "${target_path}")"
    if [[ -d "${source_path}" ]]; then
      mkdir -p "${target_path}"
      cp -R "${source_path}/." "${target_path}/"
    else
      cp "${source_path}" "${target_path}"
    fi

    COPIED_LOCAL_CONFIG_PATHS+=("${relative_path}")
    return 0
  done
}

sync_local_config_files() {
  COPIED_LOCAL_CONFIG_PATHS=()
  discover_local_config_source_roots
  shopt -s nullglob

  local root_env_path
  local source_root
  for source_root in "${LOCAL_CONFIG_SOURCE_ROOTS[@]}"; do
    for root_env_path in "${source_root}"/.env "${source_root}"/.env.*; do
      copy_local_config_path "${root_env_path#"${source_root}/"}"
    done
  done

  copy_local_config_path "android/key.properties"
  copy_local_config_path "android/app/google-services.json"
  copy_local_config_path "ios/Runner/GoogleService-Info.plist"

  local signing_path
  for source_root in "${LOCAL_CONFIG_SOURCE_ROOTS[@]}"; do
    for signing_path in "${source_root}"/android/*.keystore "${source_root}"/android/*.jks; do
      copy_local_config_path "${signing_path#"${source_root}/"}"
    done
  done

  local fastlane_private_path
  for source_root in "${LOCAL_CONFIG_SOURCE_ROOTS[@]}"; do
    for fastlane_private_path in \
      "${source_root}"/ios/fastlane/*.json \
      "${source_root}"/ios/fastlane/*.plist \
      "${source_root}"/ios/fastlane/*.p8 \
      "${source_root}"/ios/fastlane/*.p12 \
      "${source_root}"/ios/fastlane/*.mobileprovision \
      "${source_root}"/android/fastlane/*.json \
      "${source_root}"/android/fastlane/*.plist \
      "${source_root}"/android/fastlane/*.p8 \
      "${source_root}"/android/fastlane/*.p12 \
      "${source_root}"/android/fastlane/*.mobileprovision; do
      copy_local_config_path "${fastlane_private_path#"${source_root}/"}"
    done
  done

  shopt -u nullglob
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket-id|--issue-id)
      TICKET_ID="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --slug)
      SLUG="${2:-}"
      shift 2
      ;;
    --base)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --worktree-parent)
      WORKTREE_PARENT="${2:-}"
      shift 2
      ;;
    --skip-fetch)
      SKIP_FETCH=1
      shift
      ;;
    --skip-local-config-sync)
      SKIP_LOCAL_CONFIG_SYNC=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${PREFIX}" || -z "${SLUG}" ]]; then
  echo "Missing required arguments" >&2
  usage >&2
  exit 1
fi

if [[ -n "${TICKET_ID}" ]] && ! [[ "${TICKET_ID}" =~ ^([A-Z][A-Z0-9]*-)?[0-9]+$ ]]; then
  echo "Invalid issue id: ${TICKET_ID}" >&2
  exit 1
fi

if ! [[ "${PREFIX}" =~ ^(fix/|feature/|chore/)$ ]]; then
  echo "Unsupported prefix: ${PREFIX}" >&2
  exit 1
fi

if ! [[ "${SLUG}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Slug must be lowercase kebab-case: ${SLUG}" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_NAME="$(basename "${REPO_ROOT}")"
REPO_PARENT="$(dirname "${REPO_ROOT}")"

if [[ -z "${WORKTREE_PARENT}" ]]; then
  WORKTREE_PARENT="${REPO_PARENT}"
fi

if [[ -n "${TICKET_ID}" ]]; then
  TICKET_ID_LOWER="$(printf '%s' "${TICKET_ID}" | tr '[:upper:]' '[:lower:]')"
  BRANCH_NAME="${PREFIX}${TICKET_ID}-${SLUG}"
  WORKTREE_NAME="${REPO_NAME}-${TICKET_ID_LOWER}-${SLUG}"
else
  BRANCH_NAME="${PREFIX}${SLUG}"
  WORKTREE_NAME="${REPO_NAME}-${SLUG}"
fi
WORKTREE_PATH="${WORKTREE_PARENT}/${WORKTREE_NAME}"

if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
  jq -n \
    --arg status "blocked" \
    --arg reason "branch_exists" \
    --arg branch "${BRANCH_NAME}" \
    --arg worktreePath "${WORKTREE_PATH}" \
    --arg baseRef "${BASE_REF}" \
    '{
      status: $status,
      reason: $reason,
      branch: $branch,
      worktreePath: $worktreePath,
      baseRef: $baseRef
    }'
  exit 2
fi

if [[ -e "${WORKTREE_PATH}" ]]; then
  jq -n \
    --arg status "blocked" \
    --arg reason "worktree_path_exists" \
    --arg branch "${BRANCH_NAME}" \
    --arg worktreePath "${WORKTREE_PATH}" \
    --arg baseRef "${BASE_REF}" \
    '{
      status: $status,
      reason: $reason,
      branch: $branch,
      worktreePath: $worktreePath,
      baseRef: $baseRef
    }'
  exit 3
fi

if [[ "${SKIP_FETCH}" -eq 0 && "${BASE_REF}" == origin/* ]]; then
  REMOTE_NAME="${BASE_REF%%/*}"
  REMOTE_BRANCH="${BASE_REF#*/}"
  git fetch "${REMOTE_NAME}" "${REMOTE_BRANCH}" --prune
fi

git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null || {
  echo "Base ref does not resolve to a commit: ${BASE_REF}" >&2
  exit 4
}

mkdir -p "${WORKTREE_PARENT}"
git worktree add -b "${BRANCH_NAME}" "${WORKTREE_PATH}" "${BASE_REF}"

COPIED_LOCAL_CONFIG_PATHS=()
if [[ "${SKIP_LOCAL_CONFIG_SYNC}" -eq 0 ]]; then
  sync_local_config_files
fi

CURRENT_BRANCH="$(
  git -C "${WORKTREE_PATH}" branch --show-current
)"
STATUS_SHORT="$(
  git -C "${WORKTREE_PATH}" status --short
)"

jq -n \
  --arg status "created" \
  --arg ticketId "${TICKET_ID}" \
  --arg branch "${BRANCH_NAME}" \
  --arg worktreePath "${WORKTREE_PATH}" \
  --arg worktreeName "${WORKTREE_NAME}" \
  --arg baseRef "${BASE_REF}" \
  --arg currentBranch "${CURRENT_BRANCH}" \
  --arg repoRoot "${REPO_ROOT}" \
  --arg repoName "${REPO_NAME}" \
  --arg statusShort "${STATUS_SHORT}" \
  --argjson localConfigSyncSkipped "${SKIP_LOCAL_CONFIG_SYNC}" \
  --arg copiedLocalConfigPaths "$(printf '%s\n' "${COPIED_LOCAL_CONFIG_PATHS[@]}")" \
  '{
    status: $status,
    ticketId: $ticketId,
    branch: $branch,
    worktreeName: $worktreeName,
    worktreePath: $worktreePath,
    baseRef: $baseRef,
    repoRoot: $repoRoot,
    repoName: $repoName,
    currentBranch: $currentBranch,
    statusShort: $statusShort,
    localConfigSyncSkipped: ($localConfigSyncSkipped == 1),
    copiedLocalConfigPaths: ($copiedLocalConfigPaths | split("\n") | map(select(length > 0)))
  }'
