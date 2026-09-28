#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t09
ns_exists "$NS" || fail "namespace $NS does not exist"

oc get resourcequota t09-quota -n "$NS" >/dev/null 2>&1 || fail "ResourceQuota t09-quota not found"
Q_PODS=$(oc get resourcequota t09-quota -n "$NS" -o jsonpath='{.spec.hard.pods}')
Q_CPU=$(oc get resourcequota t09-quota -n "$NS" -o jsonpath='{.spec.hard.cpu}')
Q_MEM=$(oc get resourcequota t09-quota -n "$NS" -o jsonpath='{.spec.hard.memory}')
[ "$Q_PODS" = "4" ] || fail "quota pods hard limit is '$Q_PODS', expected 4"
[[ "$Q_CPU" =~ ^(2(\.0)?|2000m)$ ]] || fail "quota cpu hard limit is '$Q_CPU', expected 2"
[[ "$Q_MEM" =~ ^(2Gi|2048Mi)$ ]] || fail "quota memory hard limit is '$Q_MEM', expected 2Gi"

oc get limitrange t09-limits -n "$NS" >/dev/null 2>&1 || fail "LimitRange t09-limits not found"
LR_DEF_CPU=$(oc get limitrange t09-limits -n "$NS" -o jsonpath='{.spec.limits[0].default.cpu}')
LR_DEF_MEM=$(oc get limitrange t09-limits -n "$NS" -o jsonpath='{.spec.limits[0].default.memory}')
LR_REQ_CPU=$(oc get limitrange t09-limits -n "$NS" -o jsonpath='{.spec.limits[0].defaultRequest.cpu}')
LR_REQ_MEM=$(oc get limitrange t09-limits -n "$NS" -o jsonpath='{.spec.limits[0].defaultRequest.memory}')
[[ "$LR_DEF_CPU" =~ ^(200m|0\.2)$ ]] || fail "LimitRange default.cpu is '$LR_DEF_CPU', expected 200m"
[ "$LR_DEF_MEM" = "256Mi" ]          || fail "LimitRange default.memory is '$LR_DEF_MEM', expected 256Mi"
[[ "$LR_REQ_CPU" =~ ^(100m|0\.1)$ ]] || fail "LimitRange defaultRequest.cpu is '$LR_REQ_CPU', expected 100m"
[ "$LR_REQ_MEM" = "128Mi" ]          || fail "LimitRange defaultRequest.memory is '$LR_REQ_MEM', expected 128Mi"

oc get deployment nolimits-app -n "$NS" >/dev/null 2>&1 || fail "Deployment nolimits-app not found"
EXPLICIT=$(oc get deployment nolimits-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.requests}')
[ -z "$EXPLICIT" ] || [ "$EXPLICIT" = "{}" ] || fail "nolimits-app has explicit resources set ($EXPLICIT) — task requires relying on the LimitRange defaults, not hardcoding resources on the container"

READY=$(oc get deployment nolimits-app -n "$NS" -o jsonpath='{.status.readyReplicas}')
[ "$READY" = "1" ] || fail "nolimits-app is not Ready (readyReplicas=$READY) — did the LimitRange defaults actually apply?"

POD=$(oc get pod -n "$NS" -l app=nolimits-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
EFFECTIVE_REQ_CPU=$(oc get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
EFFECTIVE_REQ_MEM=$(oc get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null)
[[ "$EFFECTIVE_REQ_CPU" =~ ^(100m|0\.1)$ ]] || fail "pod's effective cpu request is '$EFFECTIVE_REQ_CPU', expected 100m from the LimitRange default"
[ "$EFFECTIVE_REQ_MEM" = "128Mi" ]           || fail "pod's effective memory request is '$EFFECTIVE_REQ_MEM', expected 128Mi from the LimitRange default"

pass "quota + limitrange correctly configured (values verified), nolimits-app scheduled via LimitRange defaults"
