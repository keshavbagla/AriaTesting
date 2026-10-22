#!/usr/bin/env bash
set -euo pipefail

REFERENCE_SOURCE=${1:?Set the checked-out reference application source directory}
AUDITED_PINNED_SOURCE=21af1f41561a6d83ae44933dd36d9daa5e6a6e4c
EXPECTED_SOURCE=${APP_SOURCE_REVISION:-}
APP_IMAGE=${APP_IMAGE:-}
APP_IMAGE_DIGEST=${APP_IMAGE_DIGEST:-}

if [[ ! "$EXPECTED_SOURCE" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'APP_SOURCE_REVISION must be a full commit SHA from the selected reference source.' >&2
  exit 2
fi

if ! ACTUAL_SOURCE=$(git -C "$REFERENCE_SOURCE" rev-parse --verify HEAD 2>/dev/null); then
  echo "Expected a Git checkout at $REFERENCE_SOURCE" >&2
  exit 2
fi
if [[ "$ACTUAL_SOURCE" != "$EXPECTED_SOURCE" ]]; then
  echo "Reference source checkout $ACTUAL_SOURCE does not match APP_SOURCE_REVISION $EXPECTED_SOURCE" >&2
  exit 2
fi

if [[ "${APP_IMAGE_LOCAL:-false}" != true ]]; then
  echo 'Mutation controls require the selected reference image to be pulled or built before use.' >&2
  exit 2
fi

if [[ "$APP_IMAGE" == ghcr.io/qa-test-automation-frameworks/quality-reference-application@* ]]; then
  if [[ ! "$APP_IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo 'APP_IMAGE_DIGEST must be an immutable SHA-256 digest.' >&2
    exit 2
  fi
  expected_image="ghcr.io/qa-test-automation-frameworks/quality-reference-application@${APP_IMAGE_DIGEST}"
  if [[ "$APP_IMAGE" != "$expected_image" ]]; then
    echo 'Candidate mutation controls require the selected immutable QRA registry image.' >&2
    exit 2
  fi
elif [[ "$EXPECTED_SOURCE" == "$AUDITED_PINNED_SOURCE" \
    && "${GITHUB_RUN_ID:-}" =~ ^[1-9][0-9]*$ \
    && "$APP_IMAGE" == "quality-reference-application:aria-${GITHUB_RUN_ID}" ]]; then
  if [[ ! "$APP_IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo 'The audited local QRA image must have a SHA-256 image ID.' >&2
    exit 2
  fi
  : # The default shared-app job builds this exact audited source into its run-local image.
else
  echo 'Mutation controls require the audited local pin or a descriptor-selected immutable QRA image.' >&2
  exit 2
fi

echo "Verified mutation source $ACTUAL_SOURCE against the selected QRA image identity."
