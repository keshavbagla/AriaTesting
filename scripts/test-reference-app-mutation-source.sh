#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GUARD="$REPO_ROOT/scripts/verify-reference-app-mutation-source.sh"
SOURCE_SHA=$(git -C "$REPO_ROOT" rev-parse --verify HEAD)
PINNED_SOURCE=21af1f41561a6d83ae44933dd36d9daa5e6a6e4c
ZERO_SHA=0000000000000000000000000000000000000000
DIGEST=sha256:0000000000000000000000000000000000000000000000000000000000000000
LOCAL_DIGEST=sha256:1111111111111111111111111111111111111111111111111111111111111111
IMAGE="ghcr.io/qa-test-automation-frameworks/quality-reference-application@${DIGEST}"

expect_pass() {
  local source=$1 image=$2 digest=$3 run_id=${4:-123} image_local=${5:-true}
  if ! env -i PATH="$PATH" APP_IMAGE_LOCAL="$image_local" APP_SOURCE_REVISION="$source" \
      APP_IMAGE="$image" APP_IMAGE_DIGEST="$digest" GITHUB_RUN_ID="$run_id" \
      bash "$GUARD" "$REPO_ROOT" >/dev/null 2>&1; then
    echo 'Expected the reference-app mutation identity to pass.' >&2
    exit 1
  fi
}

expect_fail() {
  local source=$1 image=$2 digest=$3 run_id=${4:-123} image_local=${5:-true}
  if env -i PATH="$PATH" APP_IMAGE_LOCAL="$image_local" APP_SOURCE_REVISION="$source" \
      APP_IMAGE="$image" APP_IMAGE_DIGEST="$digest" GITHUB_RUN_ID="$run_id" \
      bash "$GUARD" "$REPO_ROOT" >/dev/null 2>&1; then
    echo 'An invalid reference-app mutation identity was accepted.' >&2
    exit 1
  fi
}

expect_pass "$PINNED_SOURCE" quality-reference-application:aria-123 "$LOCAL_DIGEST"
expect_pass "$SOURCE_SHA" "$IMAGE" "$DIGEST"
expect_fail invalid quality-reference-application:aria-123 ''
expect_fail "$ZERO_SHA" "$IMAGE" "$DIGEST"
expect_fail "$SOURCE_SHA" quality-reference-application:candidate "$DIGEST"
expect_fail "$SOURCE_SHA" "ghcr.io/untrusted/quality-reference-application@${DIGEST}" "$DIGEST"
expect_fail "$SOURCE_SHA" "$IMAGE" sha256:1111111111111111111111111111111111111111111111111111111111111111
expect_fail "$SOURCE_SHA" "$IMAGE" ''
expect_fail "$SOURCE_SHA" "$IMAGE" "$DIGEST" 123 false

echo '9 reference-app mutation identity controls passed'
