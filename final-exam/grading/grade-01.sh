#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

PROVIDER=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[?(@.name=="htpasswd_ex280")].type}' 2>/dev/null)
[ "$PROVIDER" = "HTPasswd" ] || fail "no identityProviders entry named 'htpasswd_ex280' of type HTPasswd on oauth/cluster"

DEV_PROVIDER=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[?(@.name=="developer")].type}' 2>/dev/null)
[ "$DEV_PROVIDER" = "HTPasswd" ] || fail "the pre-existing 'developer' identity provider is gone from oauth/cluster — task 01 requires appending, not replacing, identityProviders"

SERVER=$(oc whoami --show-server)

for u in alice bob; do
  if ! oc login -u "$u" -p redhatB1 "$SERVER" --insecure-skip-tls-verify=true >/tmp/grade01-"$u".log 2>&1; then
    fail "login as $u with password redhatB1 did not succeed (see /tmp/grade01-$u.log)"
  fi
  WHO=$(oc whoami)
  [ "$WHO" = "$u" ] || fail "logged in but oc whoami returned '$WHO' instead of '$u'"
done

pass "htpasswd_ex280 provider present, alice and bob both authenticate successfully"
