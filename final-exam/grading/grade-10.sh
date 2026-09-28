#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t10
ns_exists "$NS" || fail "namespace $NS does not exist"

PVC_STATUS=$(oc get pvc t10-data -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$PVC_STATUS" = "Bound" ] || fail "PVC t10-data is not Bound (status: $PVC_STATUS)"

# Check the REQUESTED size (spec, fully controlled by the candidate) rather than granted
# capacity (status) — some provisioners (e.g. CRC's hostpath-provisioner) grant a size that
# has nothing to do with what was requested, and a naive string/lexicographic size comparison
# on that granted value is unreliable either way (e.g. "500Mi" > "1Gi" lexicographically).
REQ_SIZE=$(oc get pvc t10-data -n "$NS" -o jsonpath='{.spec.resources.requests.storage}')
[ "$REQ_SIZE" = "1Gi" ] || fail "PVC requested size is '$REQ_SIZE', expected 1Gi"

ACCESS_MODE=$(oc get pvc t10-data -n "$NS" -o jsonpath='{.spec.accessModes[0]}')
[ "$ACCESS_MODE" = "ReadWriteOnce" ] || fail "PVC accessMode is '$ACCESS_MODE', expected ReadWriteOnce"

oc get deployment storage-app -n "$NS" >/dev/null 2>&1 || fail "Deployment storage-app not found"
MOUNT=$(oc get deployment storage-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=="/data")].name}')
[ -n "$MOUNT" ] || fail "no volume mounted at /data on storage-app"

CLAIM=$(oc get deployment storage-app -n "$NS" -o jsonpath="{.spec.template.spec.volumes[?(@.name==\"$MOUNT\")].persistentVolumeClaim.claimName}")
[ "$CLAIM" = "t10-data" ] || fail "volume '$MOUNT' is not backed by PVC t10-data (found: $CLAIM)"

oc exec -n "$NS" deploy/storage-app -- sh -c 'echo ex280-persist-check > /data/.grade10-check' >/dev/null 2>&1 \
  || fail "could not write test file into /data"

# Delete every pod in the namespace rather than relying on a specific label (the task doesn't
# mandate one) — safe here since this namespace is task-scoped to exactly this one workload.
oc delete pod --all -n "$NS" >/dev/null 2>&1
oc rollout status deployment/storage-app -n "$NS" --timeout=90s >/dev/null 2>&1 \
  || fail "storage-app did not become ready again after pod restart"

CONTENT=$(oc exec -n "$NS" deploy/storage-app -- cat /data/.grade10-check 2>/dev/null)
[ "$CONTENT" = "ex280-persist-check" ] || fail "test file did not survive pod restart — storage is not actually persistent"

pass "PVC bound, mounted at /data, data survives pod restart"
