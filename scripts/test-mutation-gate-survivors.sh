#!/usr/bin/env bash
# Run the actual gate against a harmless patch; infrastructure failures are not proof.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir=${1:-reference-app}
output="$repo_root/work/evidence/mutation-gate-selftests"
mkdir -p "$output"
temporary=$(mktemp -d "${RUNNER_TEMP:-/tmp}/aria-gate-input.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
: > "$temporary/empty.patch"
printf 'not a unified diff\n' > "$temporary/garbled.patch"
for gate in claim-model reference-pact; do
  for input in empty garbled; do
    invalid_log="$output/$gate-$input.log"
    invalid_status=0
    bash "$repo_root/scripts/verify-$gate-mutations.sh" "$source_dir" --self-test-patch "$temporary/$input.patch" > "$invalid_log" 2>&1 || invalid_status=$?
    cat "$invalid_log"
    if [[ "$invalid_status" -eq 0 ]] || ! grep -Fq 'Invalid mutation patch:' "$invalid_log"; then
      echo "Self-test failed: $gate must reject $input patch input." >&2
      exit 1
    fi
  done
  log="$output/$gate.log"
  status=0
  bash "$repo_root/scripts/verify-$gate-mutations.sh" "$source_dir" --planted-survivor > "$log" 2>&1 || status=$?
  cat "$log"
  if [[ "$status" -eq 0 ]] || ! grep -Fq 'Mutant survived:' "$log"; then
    echo "Self-test failed: $gate must reject a surviving mutation, not an infrastructure error." >&2
    exit 1
  fi
  echo "PASS: $gate rejected the planted survivor (native gate exit $status)."
done
