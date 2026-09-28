#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

# ---------- A: project request template ----------
TPLNAME=$(oc get project.config.openshift.io/cluster -o jsonpath='{.spec.projectRequestTemplate.name}' 2>/dev/null)
[ "$TPLNAME" = "project-request" ] \
  || fail "project.config.openshift.io/cluster .spec.projectRequestTemplate.name is '$TPLNAME', expected 'project-request'"

oc get template project-request -n openshift-config >/dev/null 2>&1 \
  || fail "Template 'project-request' not found in namespace openshift-config"

# the template must carry a LimitRange named default-limits with the required defaults
LR=$(oc get template project-request -n openshift-config -o json 2>/dev/null \
      | python3 -c '
import json,sys
t=json.load(sys.stdin)
for o in t.get("objects",[]):
    if o.get("kind")=="LimitRange" and o.get("metadata",{}).get("name")=="default-limits":
        print(json.dumps(o)); break
' 2>/dev/null)
[ -n "$LR" ] || fail "Template project-request contains no LimitRange named 'default-limits'"

echo "$LR" | grep -q '"cpu": *"100m"' || fail "default-limits LimitRange: defaultRequest cpu 100m not found"
echo "$LR" | grep -q '"memory": *"128Mi"' || fail "default-limits LimitRange: defaultRequest memory 128Mi not found"
echo "$LR" | grep -q '"cpu": *"500m"' || fail "default-limits LimitRange: default (limit) cpu 500m not found"
echo "$LR" | grep -q '"memory": *"512Mi"' || fail "default-limits LimitRange: default (limit) memory 512Mi not found"

# functional test: a brand new project must actually receive the LimitRange.
# The openshift-apiserver has to roll out after the template is set, so retry for a while.
PROBE="ex280-t26-probe-$$"
GOT_LR=""
for _ in $(seq 1 24); do
  oc delete project "$PROBE" --ignore-not-found=true >/dev/null 2>&1
  # wait for the terminating project to disappear before recreating
  for _ in $(seq 1 30); do oc get project "$PROBE" >/dev/null 2>&1 || break; sleep 2; done
  if oc new-project "$PROBE" >/dev/null 2>&1; then
    sleep 3
    GOT_LR=$(oc get limitrange default-limits -n "$PROBE" -o jsonpath='{.metadata.name}' 2>/dev/null)
    [ -n "$GOT_LR" ] && break
  fi
  sleep 10
done
oc project default >/dev/null 2>&1
oc delete project "$PROBE" --ignore-not-found=true >/dev/null 2>&1
[ -n "$GOT_LR" ] \
  || fail "a newly created project did not receive the 'default-limits' LimitRange — the template is configured but not in effect (the openshift-apiserver rollout can take a few minutes; re-run grading once 'oc get co openshift-apiserver' stops Progressing)"

# ---------- B: ClusterResourceQuota ----------
oc get clusterresourcequota ex280-crq >/dev/null 2>&1 \
  || fail "ClusterResourceQuota 'ex280-crq' not found"

REQ=$(oc get clusterresourcequota ex280-crq -o jsonpath='{.spec.selector.annotations.openshift\.io/requester}' 2>/dev/null)
[ "$REQ" = "alice" ] \
  || fail "ClusterResourceQuota selector annotation openshift.io/requester is '$REQ', expected 'alice'"

PODS=$(oc get clusterresourcequota ex280-crq -o jsonpath='{.spec.quota.hard.pods}' 2>/dev/null)
[ "$PODS" = "10" ] || fail "ClusterResourceQuota hard.pods is '$PODS', expected 10"

MEM=$(oc get clusterresourcequota ex280-crq -o jsonpath='{.spec.quota.hard.memory}' 2>/dev/null)
[ -n "$MEM" ] || MEM=$(oc get clusterresourcequota ex280-crq -o jsonpath='{.spec.quota.hard.requests\.memory}' 2>/dev/null)
[ "$MEM" = "4Gi" ] || fail "ClusterResourceQuota memory limit is '$MEM', expected 4Gi (as 'memory' or 'requests.memory')"

pass "project-request template in effect (new projects get default-limits), ClusterResourceQuota ex280-crq scoped to requester=alice with pods=10, memory=4Gi"
