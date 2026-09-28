#!/usr/bin/env bash
# Shared helpers sourced by every grade-*.sh script.
set -uo pipefail

pass() { echo "PASS: $*"; exit 0; }
fail() { echo "FAIL: $*"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || fail "missing required command on grading host: $1"; }

need oc

# Any script that logs in as a different user (task 01/02/03) must restore the
# original kube context on exit so grading never leaves you logged in as a
# test user mid-exam.
ORIG_CTX="$(oc config current-context 2>/dev/null || true)"
restore_context() { [ -n "$ORIG_CTX" ] && oc config use-context "$ORIG_CTX" >/dev/null 2>&1; }
trap restore_context EXIT

ns_exists() { oc get namespace "$1" >/dev/null 2>&1; }

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/work"
