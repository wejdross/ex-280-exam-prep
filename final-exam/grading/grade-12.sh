#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
need helm
NS=ex280-t12
ns_exists "$NS" || fail "namespace $NS does not exist"

# Filter helm list to the exact release name — `helm list`'s unfiltered first-match would pick
# up an unrelated leftover release in the same namespace if one exists. `helm status -o json`
# doesn't include a flat chart name field, so use `helm list -f` instead, which does.
RELEASE_JSON=$(helm list -n "$NS" -f '^t12-nginx$' -o json 2>/dev/null)
STATUS=$(echo "$RELEASE_JSON" | grep -o '"status":"[a-z]*"' | head -1 | cut -d'"' -f4)
[ "$STATUS" = "deployed" ] || fail "helm release t12-nginx status is '$STATUS', expected 'deployed'"

CHART=$(echo "$RELEASE_JSON" | grep -o '"chart":"[a-zA-Z0-9.-]*"' | cut -d'"' -f4)
echo "$CHART" | grep -qi nginx || fail "t12-nginx release's chart is '$CHART', expected an nginx chart"

POD_COUNT=$(oc get pods -n "$NS" -l app.kubernetes.io/instance=t12-nginx --no-headers 2>/dev/null | grep -c Running || true)
[ "$POD_COUNT" -ge 1 ] || fail "no Running pod found for helm release t12-nginx"

SVC_TYPE=$(oc get svc -n "$NS" -l app.kubernetes.io/instance=t12-nginx -o jsonpath='{.items[0].spec.type}' 2>/dev/null)
[ "$SVC_TYPE" = "ClusterIP" ] || fail "expected Service type ClusterIP for t12-nginx, got '$SVC_TYPE'"

pass "helm release t12-nginx deployed, $POD_COUNT pod(s) Running, Service type ClusterIP"
