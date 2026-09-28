#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t05
ns_exists "$NS" || fail "namespace $NS does not exist"

oc get sa root-runner -n "$NS" >/dev/null 2>&1 || fail "ServiceAccount root-runner not found in $NS"

# The SCC the *pod* ended up with proves little here: you are kubeadmin, who may use every SCC,
# so a hand-created pod runs as root even if the ServiceAccount was never granted anything.
# Check the ServiceAccount's own authorization first — that is what the task asks for.
CAN_ANYUID=$(oc auth can-i use scc/anyuid --as="system:serviceaccount:$NS:root-runner" -n "$NS" 2>/dev/null)
[ "$CAN_ANYUID" = "yes" ] || fail "ServiceAccount root-runner is NOT authorized to use the anyuid SCC (oc auth can-i use scc/anyuid --as=system:serviceaccount:$NS:root-runner => '$CAN_ANYUID'). Your pod may run as root only because kubeadmin itself has every SCC — the grant has to be on the ServiceAccount."

CAN_PRIV=$(oc auth can-i use scc/privileged --as="system:serviceaccount:$NS:root-runner" -n "$NS" 2>/dev/null)
[ "$CAN_PRIV" = "no" ] || fail "ServiceAccount root-runner IS authorized to use the privileged SCC — the task requires least privilege (anyuid is sufficient for UID 0). Review 23-scc-serviceaccounts/README.md."

# Informational: a ClusterRoleBinding grants the SA anyuid in EVERY namespace, which is broader
# than this task needs. Not failed here (the real exam accepts it), but the tidy answer is a
# RoleBinding in ex280-t05 — i.e. `oc adm policy add-scc-to-user anyuid -z root-runner -n ex280-t05`.
CLUSTERWIDE=$(oc get clusterrolebinding -o jsonpath="{range .items[?(@.roleRef.name=='system:openshift:scc:anyuid')]}{range .subjects[?(@.name=='root-runner')]}{.namespace}{'\n'}{end}{end}" 2>/dev/null | grep -c "^$NS$")
[ "${CLUSTERWIDE:-0}" = "0" ] || echo "NOTE: root-runner is granted anyuid via a ClusterRoleBinding (every namespace), not just in $NS — broader than the task needs, but not failed."

PHASE=$(oc get pod root-pod -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$PHASE" = "Running" ] || fail "root-pod is not Running (phase: $PHASE) — check oc describe pod root-pod -n $NS"

SA=$(oc get pod root-pod -n "$NS" -o jsonpath='{.spec.serviceAccountName}')
[ "$SA" = "root-runner" ] || fail "root-pod does not use serviceAccountName root-runner (found: $SA)"

SCC=$(oc get pod root-pod -n "$NS" -o jsonpath='{.metadata.annotations.openshift\.io/scc}')
case "$SCC" in
  anyuid) : ;;
  privileged) fail "root-pod is running under 'privileged' SCC — the task explicitly requires least-privilege (anyuid is sufficient for UID 0), not the broadest available SCC." ;;
  *) fail "unexpected SCC '$SCC' applied to root-pod (expected anyuid)" ;;
esac

UID_ACTUAL=$(oc exec -n "$NS" root-pod -- id -u 2>/dev/null)
[ "$UID_ACTUAL" = "0" ] || fail "process inside root-pod is not running as UID 0 (got: $UID_ACTUAL)"

pass "root-runner may use anyuid (and not privileged); root-pod Running as UID 0 via that ServiceAccount with SCC=$SCC"
