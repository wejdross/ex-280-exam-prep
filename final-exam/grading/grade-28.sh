#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t28
ns_exists "$NS" || fail "namespace $NS does not exist"

oc get sa api-reader -n "$NS" >/dev/null 2>&1 || fail "ServiceAccount api-reader not found in $NS"

SA="system:serviceaccount:${NS}:api-reader"

# --- RBAC shape: can read pods here, nothing more, nothing elsewhere ---
for verb in get list watch; do
  R=$(oc auth can-i "$verb" pods -n "$NS" --as="$SA" 2>/dev/null)
  [ "$R" = "yes" ] || fail "ServiceAccount cannot '$verb' pods in $NS (expected yes)"
done
R=$(oc auth can-i list secrets -n "$NS" --as="$SA" 2>/dev/null)
[ "$R" = "no" ] || fail "ServiceAccount can list secrets in $NS — permission is too broad"
R=$(oc auth can-i delete pods -n "$NS" --as="$SA" 2>/dev/null)
[ "$R" = "no" ] || fail "ServiceAccount can delete pods in $NS — only get/list/watch were asked for"
R=$(oc auth can-i list pods -n default --as="$SA" 2>/dev/null)
[ "$R" = "no" ] || fail "ServiceAccount can list pods in the 'default' namespace — the grant must be project-scoped"

# --- the pod ---
oc get pod api-client -n "$NS" >/dev/null 2>&1 || fail "Pod api-client not found"
PSA=$(oc get pod api-client -n "$NS" -o jsonpath='{.spec.serviceAccountName}')
[ "$PSA" = "api-reader" ] || fail "Pod api-client runs as ServiceAccount '$PSA', expected 'api-reader'"
PHASE=$(oc get pod api-client -n "$NS" -o jsonpath='{.status.phase}')
[ "$PHASE" = "Running" ] || fail "Pod api-client is '$PHASE', expected Running"

# --- functional: call the API from inside the pod with its own projected token ---
CMD='TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); \
     CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt; \
     curl -s -o /tmp/body -w "%{http_code}" --cacert $CA -H "Authorization: Bearer $TOKEN" \
       https://kubernetes.default.svc/api/v1/namespaces/'"$NS"'/pods'
CODE=$(oc exec -n "$NS" api-client -- sh -c "$CMD" 2>/dev/null | tail -1)
[ "$CODE" = "200" ] || fail "the pod's own token could not list pods in $NS via the API: HTTP $CODE (expected 200)"

# the API pretty-prints, so tolerate whitespace after the colon
KIND=$(oc exec -n "$NS" api-client -- sh -c 'grep -oE "\"kind\"[[:space:]]*:[[:space:]]*\"PodList\"" /tmp/body | head -1' 2>/dev/null | tr -d '\r')
[ -n "$KIND" ] || fail "the API responded 200 but the body is not a PodList"

# --- and must be refused elsewhere ---
CMD2='TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); \
      CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt; \
      curl -s -o /dev/null -w "%{http_code}" --cacert $CA -H "Authorization: Bearer $TOKEN" \
        https://kubernetes.default.svc/api/v1/namespaces/default/pods'
CODE2=$(oc exec -n "$NS" api-client -- sh -c "$CMD2" 2>/dev/null | tail -1)
[ "$CODE2" = "403" ] || fail "listing pods in the 'default' namespace returned HTTP $CODE2, expected 403 — the grant is not project-scoped"

pass "api-reader scoped to get/list/watch pods in $NS; api-client lists pods with its own token (200) and is refused in 'default' (403)"
