#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t17
ns_exists "$NS" || fail "namespace $NS does not exist"

for p in q1 q2 q3 q4; do
  oc get pod "$p" -n "$NS" >/dev/null 2>&1 || fail "pod $p not found in $NS"
done

for p in q1 q2; do
  T=$(oc get pod "$p" -n "$NS" -o jsonpath='{.metadata.labels.tier}')
  [ "$T" = "frontend" ] || fail "pod $p does not have label tier=frontend (got '$T')"
done
for p in q3 q4; do
  T=$(oc get pod "$p" -n "$NS" -o jsonpath='{.metadata.labels.tier}')
  [ "$T" = "backend" ] || fail "pod $p does not have label tier=backend (got '$T')"
done

CMDFILE="$WORKDIR/task17/command.txt"
[ -s "$CMDFILE" ] || fail "$CMDFILE missing or empty — record the exact oc get command you used to produce frontend-names.txt"
grep -qE 'oc get .*(jsonpath|custom-columns)' "$CMDFILE" \
  || fail "$CMDFILE doesn't look like an 'oc get ... -o jsonpath=...'/'-o custom-columns=...' command, as the task requires"

FILE="$WORKDIR/task17/frontend-names.txt"
[ -f "$FILE" ] || fail "$FILE not found"
EXPECTED="q1 q2"
ACTUAL=$(tr -s '[:space:]' ' ' < "$FILE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
[ "$ACTUAL" = "$EXPECTED" ] || fail "frontend-names.txt content is '$ACTUAL', expected '$EXPECTED'"

pass "labels correct, command.txt records a jsonpath/custom-columns query, frontend-names.txt matches expected output ($ACTUAL)"
