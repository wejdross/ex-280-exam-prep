#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t23
ns_exists "$NS" || fail "namespace $NS does not exist"

# --- carol must authenticate against the htpasswd_ex280 provider ---
PROVIDER=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[?(@.name=="htpasswd_ex280")].type}' 2>/dev/null)
[ "$PROVIDER" = "HTPasswd" ] || fail "identity provider 'htpasswd_ex280' is missing (task 01 must be done first)"

SERVER=$(oc whoami --show-server)
for u in alice bob carol; do
  if ! oc login -u "$u" -p redhatB1 "$SERVER" --insecure-skip-tls-verify=true >/tmp/grade23-"$u".log 2>&1; then
    fail "login as $u with password redhatB1 did not succeed (see /tmp/grade23-$u.log) — adding carol must not break alice or bob"
  fi
done
restore_context

# --- group membership: exactly alice and carol ---
oc get group ex280-ops >/dev/null 2>&1 || fail "group ex280-ops not found"
MEMBERS=$(oc get group ex280-ops -o jsonpath='{.users[*]}' | tr ' ' '\n' | sort | tr '\n' ',' | sed 's/,$//')
[ "$MEMBERS" = "alice,carol" ] || fail "group ex280-ops members are '$MEMBERS', expected exactly 'alice,carol'"

# --- the RoleBinding must target the GROUP, not the users ---
FOUND=""
for rb in $(oc get rolebinding -n "$NS" -o jsonpath='{.items[*].metadata.name}'); do
  ROLE=$(oc get rolebinding "$rb" -n "$NS" -o jsonpath='{.roleRef.name}')
  KIND=$(oc get rolebinding "$rb" -n "$NS" -o jsonpath='{.subjects[?(@.kind=="Group")].name}')
  if [ "$ROLE" = "view" ] && echo "$KIND" | grep -qw "ex280-ops"; then FOUND="$rb"; fi
done
[ -n "$FOUND" ] || fail "no RoleBinding in $NS binding ClusterRole 'view' to Group 'ex280-ops' (binding the users individually does not satisfy this task)"

# --- effective access, tested by REAL LOGIN.
# `oc auth can-i --as=<user>` does NOT resolve OpenShift Group membership (impersonation only
# carries the username unless --as-group is also passed), so a group-granted permission looks
# like "no" under --as. Logging in for real is the only faithful check here.
as_user_can() { # user verb resource -> prints yes/no
  local u=$1 verb=$2 res=$3 out
  oc login -u "$u" -p redhatB1 "$SERVER" --insecure-skip-tls-verify=true >/dev/null 2>&1 || { echo "loginfail"; return; }
  out=$(oc auth can-i "$verb" "$res" -n "$NS" 2>/dev/null)
  echo "$out"
}

A=$(as_user_can alice get pods)
[ "$A" = "yes" ] || fail "alice cannot read pods in $NS (got '$A', expected yes via group membership)"
C=$(as_user_can carol get pods)
[ "$C" = "yes" ] || fail "carol cannot read pods in $NS (got '$C', expected yes via group membership)"
B=$(as_user_can bob get pods)
[ "$B" = "no" ] || fail "bob CAN read pods in $NS (got '$B', expected no — he is not in ex280-ops)"
AW=$(as_user_can alice create pods)
[ "$AW" = "no" ] || fail "alice can create pods in $NS (got '$AW') — 'view' should be read-only"
restore_context

pass "carol authenticates, group ex280-ops = {alice,carol}, view bound to the group, bob correctly excluded"
