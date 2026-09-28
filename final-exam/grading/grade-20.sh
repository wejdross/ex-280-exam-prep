#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t20

if ! ns_exists "$NS"; then
  oc new-project "$NS" >/dev/null
fi

if ! oc get deployment broken-app -n "$NS" >/dev/null 2>&1; then
  # Seed a realistic OpenShift-specific trap: a stock upstream image that
  # binds to a privileged port as root — restricted-v2 SCC blocks it.
  oc create deployment broken-app --image=docker.io/library/nginx:latest -n "$NS" >/dev/null 2>&1
  echo "Seeded a broken 'broken-app' Deployment in $NS."
  echo "Diagnose with 'oc describe pod' / 'oc logs' and fix it declaratively, then re-run: task grade:20"
  exit 1
fi

# A pod stuck in CrashLoopBackOff (the seeded failure mode) briefly reports Ready right after
# each restart before crashing again — a single instantaneous check can catch it mid-window
# and false-pass. Require Ready across two checks 15s apart before declaring it healthy.
check_ready() {
  READY=$(oc get deployment broken-app -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  DESIRED=$(oc get deployment broken-app -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  DESIRED=${DESIRED:-1}
  [ "$READY" = "$DESIRED" ] && [ -n "$READY" ]
}

check_ready || fail "broken-app is not fully Ready ($READY/$DESIRED) — keep diagnosing (oc describe pod, oc logs)"
sleep 15
check_ready || fail "broken-app looked Ready once but is not stable ($READY/$DESIRED on recheck) — likely still crash-looping, keep diagnosing"

pass "broken-app is healthy and stable across two checks 15s apart ($READY/$DESIRED ready)"
