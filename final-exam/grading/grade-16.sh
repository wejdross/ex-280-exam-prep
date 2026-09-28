#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t16
ns_exists "$NS" || fail "namespace $NS does not exist"

ORIGINAL_IMAGE=quay.io/redhattraining/hello-world-nginx:v1.0

oc get deployment rollout-app -n "$NS" >/dev/null 2>&1 || fail "Deployment rollout-app not found"

HISTORY_LINES=$(oc rollout history deployment/rollout-app -n "$NS" 2>/dev/null | grep -c '^[0-9]')
[ "$HISTORY_LINES" -ge 2 ] || fail "rollout history has only $HISTORY_LINES revision(s), expected at least 2 (deploy :v1.0, roll forward to :latest, then roll back)"

CURRENT_IMAGE=$(oc get deployment rollout-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')
[ "$CURRENT_IMAGE" = "$ORIGINAL_IMAGE" ] || fail "current image is '$CURRENT_IMAGE', expected it to be rolled back to '$ORIGINAL_IMAGE'"

REPLICAS=$(oc get deployment rollout-app -n "$NS" -o jsonpath='{.spec.replicas}')
[ "$REPLICAS" = "2" ] || fail "rollout-app has $REPLICAS replicas, expected 2"

READY=$(oc get deployment rollout-app -n "$NS" -o jsonpath='{.status.readyReplicas}')
[ "$READY" = "2" ] || fail "rollout-app is not fully Ready after rollback (readyReplicas=$READY)"

pass "rollout-app rolled forward then back to $ORIGINAL_IMAGE, 2/2 ready, $HISTORY_LINES revisions in history"
