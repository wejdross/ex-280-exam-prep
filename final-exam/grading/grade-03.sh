#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

SERVER=$(oc whoami --show-server)

# Guarantee a clean slate as admin BEFORE testing — otherwise a project orphaned by a
# previous failed run causes "AlreadyExists" on the next attempt, which looks identical
# to "correctly Forbidden" and would false-PASS an un-fixed task on a simple re-run.
oc delete project ex280-t03-bob-should-fail --ignore-not-found=true >/dev/null 2>&1
oc delete project ex280-t03-alice-should-work --ignore-not-found=true >/dev/null 2>&1

BOB_CREATED=unknown
if oc login -u bob -p redhatB1 "$SERVER" --insecure-skip-tls-verify=true >/tmp/grade03-bob.log 2>&1; then
  if oc new-project ex280-t03-bob-should-fail >/tmp/grade03-bob-newproj.log 2>&1; then
    BOB_CREATED=yes
  else
    BOB_CREATED=no
  fi
else
  fail "could not log in as bob (password redhatB1) — needed to verify this task, is task 01 done?"
fi

# Switch back to admin (not bob — bob can't --as=system:admin) before cleaning up.
restore_context
oc delete project ex280-t03-bob-should-fail --ignore-not-found=true >/dev/null 2>&1

[ "$BOB_CREATED" = "no" ] || fail "bob was able to create a new project — self-provisioning was not restricted"

ALICE_CREATED=unknown
if oc login -u alice -p redhatB1 "$SERVER" --insecure-skip-tls-verify=true >/tmp/grade03-alice.log 2>&1; then
  if oc new-project ex280-t03-alice-should-work >/tmp/grade03-alice-newproj.log 2>&1; then
    ALICE_CREATED=yes
  else
    ALICE_CREATED=no
  fi
else
  fail "could not log in as alice — is task 01 done?"
fi

restore_context
oc delete project ex280-t03-alice-should-work --ignore-not-found=true >/dev/null 2>&1

[ "$ALICE_CREATED" = "yes" ] || fail "alice was NOT able to create a new project, but the task requires she still can (see /tmp/grade03-alice-newproj.log)"

pass "self-provisioning restricted for bob, still allowed for alice"
