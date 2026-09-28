#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t21
ns_exists "$NS" || fail "namespace $NS does not exist"

# --- ConfigMap t21-config ---
M=$(oc get configmap t21-config -n "$NS" -o jsonpath='{.data.APP_MODE}' 2>/dev/null)
[ "$M" = "production" ] || fail "configmap t21-config key APP_MODE is '$M', expected 'production'"
T=$(oc get configmap t21-config -n "$NS" -o jsonpath='{.data.APP_TIER}' 2>/dev/null)
[ "$T" = "gold" ] || fail "configmap t21-config key APP_TIER is '$T', expected 'gold'"

# --- ConfigMap t21-files (from assets/task21/app.properties) ---
F=$(oc get configmap t21-files -n "$NS" -o jsonpath='{.data.app\.properties}' 2>/dev/null)
[ -n "$F" ] || fail "configmap t21-files has no key 'app.properties' (create it --from-file so the key is the filename)"
echo "$F" | grep -q "app.name=ex280" \
  || fail "configmap t21-files key app.properties does not contain the provided file's content (expected 'app.name=ex280')"

# --- Secret t21-secret ---
K=$(oc get secret t21-secret -n "$NS" -o jsonpath='{.data.API_KEY}' 2>/dev/null | base64 -d 2>/dev/null)
[ "$K" = "s3cr3t-ex280" ] || fail "secret t21-secret key API_KEY is '$K', expected 's3cr3t-ex280'"

# --- Deployment exists and is ready ---
oc get deployment config-app -n "$NS" >/dev/null 2>&1 || fail "Deployment config-app not found"
oc rollout status deployment/config-app -n "$NS" --timeout=120s >/dev/null 2>&1 \
  || fail "Deployment config-app never became ready"

# --- the env must come FROM the ConfigMap/Secret, not be hardcoded literals.
# Two legitimate shapes, because `oc set env --from=configmap/x` expands to one
# configMapKeyRef per key while a hand-written manifest usually uses envFrom:
#   a) envFrom[].configMapRef.name == t21-config
#   b) env[].valueFrom.configMapKeyRef.name == t21-config for both keys
EF=$(oc get deployment config-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].envFrom[*].configMapRef.name}')
CMREFS=$(oc get deployment config-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.valueFrom.configMapKeyRef.name=="t21-config")].name}')
if ! echo "$EF" | grep -qw "t21-config"; then
  echo "$CMREFS" | grep -qw "APP_MODE" && echo "$CMREFS" | grep -qw "APP_TIER" \
    || fail "container does not take APP_MODE/APP_TIER from ConfigMap t21-config (neither envFrom.configMapRef nor per-key configMapKeyRef found) — hardcoded literal values do not satisfy this task"
fi

SECREF=$(oc get deployment config-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.valueFrom.secretKeyRef.name=="t21-secret")].name}')
SEF=$(oc get deployment config-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].envFrom[*].secretRef.name}')
echo "$SECREF" | grep -qw "API_KEY" || echo "$SEF" | grep -qw "t21-secret" \
  || fail "API_KEY does not come from Secret t21-secret (no secretKeyRef/secretRef on the container) — a hardcoded value does not satisfy this task"

# --- runtime verification, inside the pod ---
POD=$(oc get pod -n "$NS" -l app=config-app -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}')
[ -n "$POD" ] || fail "no Running pod for config-app"

GOT_MODE=$(oc exec -n "$NS" "$POD" -- printenv APP_MODE 2>/dev/null | tr -d '\r')
[ "$GOT_MODE" = "production" ] || fail "env APP_MODE inside the pod is '$GOT_MODE', expected 'production'"

GOT_TIER=$(oc exec -n "$NS" "$POD" -- printenv APP_TIER 2>/dev/null | tr -d '\r')
[ "$GOT_TIER" = "gold" ] || fail "env APP_TIER inside the pod is '$GOT_TIER', expected 'gold'"

GOT_KEY=$(oc exec -n "$NS" "$POD" -- printenv API_KEY 2>/dev/null | tr -d '\r')
[ "$GOT_KEY" = "s3cr3t-ex280" ] || fail "env API_KEY inside the pod is '$GOT_KEY', expected 's3cr3t-ex280'"

GOT_FILE=$(oc exec -n "$NS" "$POD" -- cat /etc/appconfig/app.properties 2>/dev/null)
echo "$GOT_FILE" | grep -q "app.name=ex280" \
  || fail "/etc/appconfig/app.properties is missing or wrong inside the pod (got: '$GOT_FILE')"

pass "t21-config/t21-files/t21-secret correct; config-app sources env from the ConfigMap and Secret and mounts the file, all verified inside the pod"
