#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t24
ns_exists "$NS" || fail "namespace $NS does not exist"

# --- headless Service ---
oc get svc t24-db -n "$NS" >/dev/null 2>&1 || fail "Service t24-db not found"
CIP=$(oc get svc t24-db -n "$NS" -o jsonpath='{.spec.clusterIP}')
[ "$CIP" = "None" ] || fail "Service t24-db has clusterIP '$CIP', expected 'None' (headless)"

# --- StatefulSet ---
oc get statefulset t24-db -n "$NS" >/dev/null 2>&1 || fail "StatefulSet t24-db not found"
SVCNAME=$(oc get statefulset t24-db -n "$NS" -o jsonpath='{.spec.serviceName}')
[ "$SVCNAME" = "t24-db" ] || fail "StatefulSet serviceName is '$SVCNAME', expected 't24-db'"
REPL=$(oc get statefulset t24-db -n "$NS" -o jsonpath='{.spec.replicas}')
[ "$REPL" = "2" ] || fail "StatefulSet replicas is '$REPL', expected 2"

VCT=$(oc get statefulset t24-db -n "$NS" -o jsonpath='{.spec.volumeClaimTemplates[0].metadata.name}')
[ "$VCT" = "data" ] || fail "volumeClaimTemplate is named '$VCT', expected 'data'"
VCTSIZE=$(oc get statefulset t24-db -n "$NS" -o jsonpath='{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}')
[ "$VCTSIZE" = "1Gi" ] || fail "volumeClaimTemplate requests '$VCTSIZE', expected '1Gi'"
VCTMODE=$(oc get statefulset t24-db -n "$NS" -o jsonpath='{.spec.volumeClaimTemplates[0].spec.accessModes[0]}')
[ "$VCTMODE" = "ReadWriteOnce" ] || fail "volumeClaimTemplate accessMode is '$VCTMODE', expected ReadWriteOnce"

# --- both pods ready ---
oc rollout status statefulset/t24-db -n "$NS" --timeout=180s >/dev/null 2>&1 \
  || fail "StatefulSet t24-db did not become ready within 180s"

# --- one PVC per pod, both Bound ---
for i in 0 1; do
  PH=$(oc get pvc "data-t24-db-$i" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$PH" = "Bound" ] || fail "PVC data-t24-db-$i is '$PH', expected Bound (a volumeClaimTemplate creates one PVC per replica)"
done

# --- the actual point: storage is per-pod, not shared ---
for i in 0 1; do
  VAL=$(oc exec -n "$NS" "t24-db-$i" -- cat /data/id.txt 2>/dev/null | tr -d '\r\n')
  [ "$VAL" = "t24-db-$i" ] || fail "/data/id.txt in pod t24-db-$i reads '$VAL', expected 't24-db-$i' — the replicas are not writing to separate volumes"
done

pass "headless Service, StatefulSet with per-replica 1Gi PVCs (data-t24-db-0/1 Bound), each pod's /data holds its own identity"
