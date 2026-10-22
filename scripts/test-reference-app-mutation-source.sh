#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GUARD="$REPO_ROOT/scripts/verify-reference-app-mutation-source.sh"
REAL_GIT=$(command -v git)
SOURCE_SHA=$("$REAL_GIT" -C "$REPO_ROOT" rev-parse --verify HEAD)
PINNED_SOURCE=21af1f41561a6d83ae44933dd36d9daa5e6a6e4c
ZERO_SHA=0000000000000000000000000000000000000000
DIGEST=sha256:0000000000000000000000000000000000000000000000000000000000000000
LOCAL_DIGEST=sha256:1111111111111111111111111111111111111111111111111111111111111111
IMAGE="ghcr.io/qa-test-automation-frameworks/quality-reference-application@${DIGEST}"
MOCK_BIN=$(mktemp -d)
trap 'rm -rf "$MOCK_BIN"' EXIT
cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
if [[ "${1:-}" == -C && "${3:-}" == rev-parse && "${4:-}" == --verify && "${5:-}" == HEAD ]]; then
  printf '%s\n' "${MOCK_GIT_HEAD:?}"
else
  exec "${MOCK_REAL_GIT:?}" "$@"
fi
MOCK_GIT
chmod +x "$MOCK_BIN/git"
MOCK_PATH="$MOCK_BIN:$PATH"

expect_pass() {
  local source=$1 image=$2 digest=$3 run_id=${4:-123} image_local=${5:-true} actual_source=${6:-$SOURCE_SHA}
  if ! env -i PATH="$MOCK_PATH" APP_IMAGE_LOCAL="$image_local" APP_SOURCE_REVISION="$source" \
      APP_IMAGE="$image" APP_IMAGE_DIGEST="$digest" GITHUB_RUN_ID="$run_id" \
      MOCK_GIT_HEAD="$actual_source" MOCK_REAL_GIT="$REAL_GIT" \
      bash "$GUARD" "$REPO_ROOT" >/dev/null 2>&1; then
    echo 'Expected the reference-app mutation identity to pass.' >&2
    exit 1
  fi
}

expect_fail() {
  local source=$1 image=$2 digest=$3 run_id=${4:-123} image_local=${5:-true} actual_source=${6:-$SOURCE_SHA}
  if env -i PATH="$MOCK_PATH" APP_IMAGE_LOCAL="$image_local" APP_SOURCE_REVISION="$source" \
      APP_IMAGE="$image" APP_IMAGE_DIGEST="$digest" GITHUB_RUN_ID="$run_id" \
      MOCK_GIT_HEAD="$actual_source" MOCK_REAL_GIT="$REAL_GIT" \
      bash "$GUARD" "$REPO_ROOT" >/dev/null 2>&1; then
    echo 'An invalid reference-app mutation identity was accepted.' >&2
    exit 1
  fi
}

expect_pass "$PINNED_SOURCE" quality-reference-application:aria-123 "$LOCAL_DIGEST" 123 true "$PINNED_SOURCE"
expect_pass "$SOURCE_SHA" "$IMAGE" "$DIGEST"
expect_fail invalid quality-reference-application:aria-123 ''
expect_fail "$ZERO_SHA" "$IMAGE" "$DIGEST"
expect_fail "$SOURCE_SHA" quality-reference-application:candidate "$DIGEST"
expect_fail "$SOURCE_SHA" "ghcr.io/untrusted/quality-reference-application@${DIGEST}" "$DIGEST"
expect_fail "$SOURCE_SHA" "$IMAGE" sha256:1111111111111111111111111111111111111111111111111111111111111111
expect_fail "$SOURCE_SHA" "$IMAGE" ''
expect_fail "$SOURCE_SHA" "$IMAGE" "$DIGEST" 123 false
expect_fail "$SOURCE_SHA" "$IMAGE" "$DIGEST" 123 true "$PINNED_SOURCE"

echo '10 reference-app mutation identity controls passed'
