#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t08
ns_exists "$NS" || fail "namespace $NS does not exist"
# NOTE: `timeout` is invoked INSIDE the pods (hello-world-nginx ships coreutils), never on the
# grading host — macOS has no timeout(1), so requiring it here would abort grading on a Mac.

for d in frontend backend other; do
  oc get deployment "$d" -n "$NS" >/dev/null 2>&1 || fail "Deployment $d not found in $NS"
done

FRONTEND_POD=$(oc get pod -n "$NS" -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
OTHER_POD=$(oc get pod -n "$NS" -l app=other -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$FRONTEND_POD" ] || fail "no pod found with label app=frontend"
[ -n "$OTHER_POD" ] || fail "no pod found with label app=other"

for POD in "$FRONTEND_POD" "$OTHER_POD"; do
  oc exec -n "$NS" "$POD" -- sh -c 'command -v curl || command -v wget' >/dev/null 2>&1 \
    || fail "pod $POD has neither curl nor wget — cannot verify connectivity (a silent '000' from a missing tool would look identical to 'correctly blocked' and give a false pass on the negative test), use an image that has one of them"
done

test_reach() {
  local pod=$1
  oc exec -n "$NS" "$pod" -- sh -c '
    if command -v curl >/dev/null; then timeout 5 curl -s -o /dev/null -w "%{http_code}" http://backend:8080
    else timeout 5 wget -q -O- http://backend:8080 >/dev/null && echo 200 || echo 000
    fi' 2>/dev/null
}

FRONT_CODE=$(test_reach "$FRONTEND_POD")
[[ "$FRONT_CODE" =~ ^2 ]] || fail "frontend cannot reach backend:8080 (got $FRONT_CODE) — NetworkPolicy too restrictive"

OTHER_CODE=$(test_reach "$OTHER_POD")
[[ "$OTHER_CODE" =~ ^2 ]] && fail "other pod CAN reach backend:8080 (got $OTHER_CODE) — NetworkPolicy not restrictive enough"

pass "frontend can reach backend, other cannot — NetworkPolicy correctly scoped"
