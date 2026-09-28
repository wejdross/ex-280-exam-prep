#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

NS=openshift-operators
PKG=rh-service-binding-operator
CSV_PREFIX=service-binding-operator

csv_phase() {
  oc get csv -n "$NS" --no-headers 2>/dev/null | awk -v p="^$CSV_PREFIX" '$1 ~ p {print $NF}' | head -1
}

# Real OLM installs commonly take 1-5 minutes (InstallPlan approval, CSV rollout) — a Subscription
# created moments before grading runs is very likely still "Installing", not yet "Succeeded".
PHASE=$(csv_phase)
WAITED=0
while [ "$PHASE" != "Succeeded" ] && [ "$WAITED" -lt 240 ]; do
  sleep 15
  WAITED=$((WAITED + 15))
  PHASE=$(csv_phase)
done

if [ "$PHASE" != "Succeeded" ]; then
  SUB=$(oc get subscription "$PKG" -n "$NS" -o jsonpath='{.spec.channel}/{.spec.source}' 2>/dev/null)
  fail "no ${CSV_PREFIX}.* CSV in Succeeded phase in $NS after ${WAITED}s (current phase: '${PHASE:-none}', subscription: '${SUB:-missing}') — check 'oc get subscription,installplan,csv -n $NS'"
fi

CHANNEL=$(oc get subscription "$PKG" -n "$NS" -o jsonpath='{.spec.channel}' 2>/dev/null)
[ "$CHANNEL" = "stable" ] || fail "CSV is Succeeded but the Subscription '$PKG' in $NS is on channel '$CHANNEL', expected 'stable'"

pass "$(oc get csv -n "$NS" --no-headers | awk -v p="^$CSV_PREFIX" '$1 ~ p {print $1}' | head -1) in Succeeded phase in $NS (channel $CHANNEL)"
