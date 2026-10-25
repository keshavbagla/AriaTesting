#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REFERENCE_SOURCE=${1:-reference-app}
CONTROL_MODE=${2:-normal}
SELF_TEST_PATCH=${3:-}
if [[ "$CONTROL_MODE" != normal && "$CONTROL_MODE" != --planted-survivor && "$CONTROL_MODE" != --self-test-patch ]]; then
  echo "Unknown mutation control mode: $CONTROL_MODE" >&2
  exit 2
fi
if [[ "$REFERENCE_SOURCE" != /* ]]; then
  REFERENCE_SOURCE="$REPO_ROOT/$REFERENCE_SOURCE"
fi
bash "$REPO_ROOT/scripts/verify-reference-app-mutation-source.sh" "$REFERENCE_SOURCE"

cd "$REPO_ROOT"
EVIDENCE_ROOT="$REPO_ROOT/work/evidence/claim-model-controls/controls"
mkdir -p "$EVIDENCE_ROOT"

run_control() {
  local name=$1
  local patch_file=$2
  local expected_index=$3
  local image="quality-reference-application:f2-${name}-${GITHUB_RUN_ID:-local}"
  local candidate
  candidate=$(mktemp -d "${RUNNER_TEMP:-/tmp}/f2-${name}.XXXXXX")
  local control_dir="$EVIDENCE_ROOT/$name"
  rm -rf "$control_dir"
  mkdir -p "$control_dir/test-results/initial" "$control_dir/test-results/replay"

  cleanup_candidate() {
    docker image rm "$image" >/dev/null 2>&1 || true
    rm -rf "$candidate"
  }
  local cleanup_command
  printf -v cleanup_command 'docker image rm %q >/dev/null 2>&1 || true; rm -rf -- %q' "$image" "$candidate"
  trap "$cleanup_command" EXIT

  git -C "$REFERENCE_SOURCE" archive HEAD | tar -x -C "$candidate"
  if [[ "$CONTROL_MODE" == --planted-survivor ]]; then
    patch_file=planted-survivor.patch
  fi
  local patch_path="$REPO_ROOT/src/test/resources/claim-model-mutations/$patch_file"
  if [[ "$CONTROL_MODE" == --self-test-patch ]]; then
    patch_path=${SELF_TEST_PATCH:?Set an explicit self-test patch path}
  fi
  if [[ ! -s "$patch_path" ]]; then
    echo 'Invalid mutation patch: empty or missing input.' >&2
    exit 2
  fi
  if ! git -C "$candidate" apply --check "$patch_path"; then
    echo 'Invalid mutation patch: git rejected the input.' >&2
    exit 2
  fi
  git -C "$candidate" apply "$patch_path"
  docker build \
    --build-arg "APP_SOURCE_SHA=f2-mutation-$name" \
    --tag "$image" \
    "$candidate"
  local image_id
  image_id=$(docker image inspect --format '{{.Id}}' "$image")
  local receipt="$control_dir/counterexample.json"
  local verification_status=0

  set +e
  APP_IMAGE="$image" \
  APP_IMAGE_LOCAL=true \
  APP_SOURCE_REVISION="f2-mutation-$name" \
  APP_IMAGE_DIGEST="$image_id" \
  FRAMEWORK_SOURCE_REVISION="${FRAMEWORK_SOURCE_REVISION:-${GITHUB_SHA:-unknown}}" \
  CLAIM_MODEL_CONTROL_NAME="$name" \
  bash "$REPO_ROOT/scripts/with-reference-application.sh" \
    ./gradlew --no-daemon --max-workers=1 --rerun-tasks sharedReferenceAppTest \
    --tests com.aria.framework.contracts.claims.ReferenceApplicationStateMachineTest \
    > "$control_dir/initial-run.log" 2>&1
  verification_status=$?
  set -e
  if [[ -d "$REPO_ROOT/build/test-results/sharedReferenceAppTest" ]]; then
    cp "$REPO_ROOT"/build/test-results/sharedReferenceAppTest/TEST-*.xml "$control_dir/test-results/initial/" 2>/dev/null || true
  fi

  if [[ "$verification_status" -eq 0 ]]; then
    python3 - "$control_dir/test-results/initial" <<'PYTHON'
import pathlib
import sys
import xml.etree.ElementTree as ET
cases = [case for report in pathlib.Path(sys.argv[1]).glob("TEST-*.xml")
         for case in ET.parse(report).getroot().iter("testcase")]
if len(cases) != 1 or cases[0].get("name") != "The independent claims model matches 120 bounded API observations":
    raise SystemExit("No single native model test pass proves a surviving mutation")
if any(node.tag in {"failure", "error", "skipped"} for node in cases[0]):
    raise SystemExit("The native model test did not pass completely")
PYTHON
    echo "Mutant survived: $name passed the native model test." >&2
    exit 1
  fi

  if [[ ! -s "$receipt" ]]; then
    echo "The $name mutation did not retain a first-divergence receipt." >&2
    exit 1
  fi

  local replay_status=0
  set +e
  APP_IMAGE="$image" \
  APP_IMAGE_LOCAL=true \
  APP_SOURCE_REVISION="f2-mutation-$name" \
  APP_IMAGE_DIGEST="$image_id" \
  FRAMEWORK_SOURCE_REVISION="${FRAMEWORK_SOURCE_REVISION:-${GITHUB_SHA:-unknown}}" \
  CLAIM_MODEL_CONTROL_NAME="$name" \
  CLAIM_MODEL_REPLAY_RECEIPT="$receipt" \
  bash "$REPO_ROOT/scripts/with-reference-application.sh" \
    ./gradlew --no-daemon --max-workers=1 --rerun-tasks sharedReferenceAppTest \
    --tests com.aria.framework.contracts.claims.ReferenceApplicationStateMachineTest \
    > "$control_dir/replay-run.log" 2>&1
  replay_status=$?
  set -e
  if [[ -d "$REPO_ROOT/build/test-results/sharedReferenceAppTest" ]]; then
    cp "$REPO_ROOT"/build/test-results/sharedReferenceAppTest/TEST-*.xml "$control_dir/test-results/replay/" 2>/dev/null || true
  fi

  python3 "$REPO_ROOT/scripts/validate-claim-model-control.py" \
    --name "$name" \
    --receipt "$receipt" \
    --replay-receipt "$control_dir/replay.json" \
    --initial-junit "$control_dir/test-results/initial" \
    --replay-junit "$control_dir/test-results/replay" \
    --initial-exit "$verification_status" \
    --replay-exit "$replay_status" \
    --expected-index "$expected_index" \
    --framework-revision "${FRAMEWORK_SOURCE_REVISION:-${GITHUB_SHA:-unknown}}" \
    --target-revision "f2-mutation-$name" \
    --target-digest "$image_id" \
    --output "$control_dir/control-summary.json"
  trap - EXIT
  cleanup_candidate
}

run_control allow-terminal-reopen allow-terminal-reopen.patch 13
run_control allow-foreign-member-read allow-foreign-member-read.patch 2
