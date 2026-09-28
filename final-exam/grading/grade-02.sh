#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t02
ns_exists "$NS" || fail "namespace $NS does not exist"

check() { # verb resource user expect(yes/no)
  local verb=$1 res=$2 user=$3 expect=$4
  local got
  got=$(oc auth can-i "$verb" "$res" -n "$NS" --as="$user" 2>/dev/null)
  [ "$got" = "$expect" ] || fail "expected 'oc auth can-i $verb $res -n $NS --as=$user' = $expect, got $got"
}

check create pods alice yes
check delete deployments alice yes
check create rolebindings alice no
check create roles alice no
check update resourcequotas alice no

check get pods bob yes
check create pods bob no
check delete pods bob no
check update pods bob no

# neither should have special access outside the project
OUT_ALICE=$(oc auth can-i create pods -n default --as=alice 2>/dev/null)
[ "$OUT_ALICE" = "no" ] || fail "alice can create pods outside ex280-t02 (in 'default') — access too broad"
OUT_BOB=$(oc auth can-i get pods -n default --as=bob 2>/dev/null)
[ "$OUT_BOB" = "no" ] || fail "bob can read pods outside ex280-t02 — access too broad"

pass "alice has edit-level, bob has view-only, both scoped correctly to ex280-t02"
