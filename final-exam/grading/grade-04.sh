#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t04
ns_exists "$NS" || fail "namespace $NS does not exist"

oc get deployment webapp -n "$NS" >/dev/null 2>&1 || fail "Deployment webapp not found in $NS"

REPLICAS=$(oc get deployment webapp -n "$NS" -o jsonpath='{.spec.replicas}')
[ "$REPLICAS" = "2" ] || fail "expected 2 replicas, got $REPLICAS"

READY=$(oc get deployment webapp -n "$NS" -o jsonpath='{.status.readyReplicas}')
[ "$READY" = "2" ] || fail "expected 2 readyReplicas, got '$READY' — deployment not fully healthy"

REQ_CPU=$(oc get deployment webapp -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
REQ_MEM=$(oc get deployment webapp -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')
LIM_CPU=$(oc get deployment webapp -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}')
LIM_MEM=$(oc get deployment webapp -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')
[[ "$REQ_CPU" =~ ^(100m|0\.1)$ ]]   || fail "requests.cpu is '$REQ_CPU', expected 100m"
[ "$REQ_MEM" = "128Mi" ]            || fail "requests.memory is '$REQ_MEM', expected 128Mi"
[[ "$LIM_CPU" =~ ^(250m|0\.25)$ ]]  || fail "limits.cpu is '$LIM_CPU', expected 250m"
[ "$LIM_MEM" = "256Mi" ]            || fail "limits.memory is '$LIM_MEM', expected 256Mi"

READINESS_PORT=$(oc get deployment webapp -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.port}')
READINESS_PATH=$(oc get deployment webapp -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}')
[ "$READINESS_PORT" = "8080" ] || fail "readiness probe must be an httpGet on port 8080 (got port='$READINESS_PORT' — wrong type or port)"
[ "$READINESS_PATH" = "/" ]    || fail "readiness probe httpGet path is '$READINESS_PATH', expected /"

LIVENESS_PORT=$(oc get deployment webapp -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.tcpSocket.port}')
[ "$LIVENESS_PORT" = "8080" ] || fail "liveness probe must be a tcpSocket check on port 8080 (got port='$LIVENESS_PORT' — wrong type or port)"

oc get svc webapp -n "$NS" >/dev/null 2>&1 || fail "Service webapp not found in $NS"
SVC_PORT=$(oc get svc webapp -n "$NS" -o jsonpath='{.spec.ports[0].port}')
[ "$SVC_PORT" = "8080" ] || fail "expected Service port 8080, got $SVC_PORT"

pass "webapp deployment healthy: 2/2 ready, resources + both probes configured, service on 8080"
