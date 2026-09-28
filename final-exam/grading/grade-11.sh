#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t11
ns_exists "$NS" || fail "namespace $NS does not exist"

for f in base/kustomization.yaml base/deployment.yaml base/service.yaml overlays/exam/kustomization.yaml; do
  [ -f "$WORKDIR/task11/$f" ] || fail "$WORKDIR/task11/$f not found — the task mandates this exact layout"
done

oc get deployment exam-kustom-app -n "$NS" >/dev/null 2>&1 || fail "Deployment exam-kustom-app not found in $NS (expected 'exam-' name prefix from overlay)"

REPLICAS=$(oc get deployment exam-kustom-app -n "$NS" -o jsonpath='{.spec.replicas}')
[ "$REPLICAS" = "3" ] || fail "expected 3 replicas from overlay, got $REPLICAS"

LABEL=$(oc get deployment exam-kustom-app -n "$NS" -o jsonpath='{.metadata.labels.env}')
[ "$LABEL" = "exam" ] || fail "expected label env=exam on exam-kustom-app, got '$LABEL'"

oc get svc exam-kustom-app -n "$NS" >/dev/null 2>&1 || fail "Service exam-kustom-app not found — the overlay must prefix/label the base's Service too, not just the Deployment"
SVC_LABEL=$(oc get svc exam-kustom-app -n "$NS" -o jsonpath='{.metadata.labels.env}')
[ "$SVC_LABEL" = "exam" ] || fail "expected label env=exam on Service exam-kustom-app, got '$SVC_LABEL'"

BASE_REPLICAS=$(grep -E '^[[:space:]]*replicas:' "$WORKDIR/task11/base/deployment.yaml" | head -1 | awk '{print $2}')
[ "$BASE_REPLICAS" = "3" ] && fail "base/deployment.yaml itself declares 3 replicas — the overlay must do the patching, the base must stay at 1"

pass "kustomize overlay applied correctly: exam-kustom-app, 3 replicas, env=exam label, base untouched"
