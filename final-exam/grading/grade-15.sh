#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t15
ns_exists "$NS" || fail "namespace $NS does not exist"

SCHEDULE=$(oc get cronjob t15-cron -n "$NS" -o jsonpath='{.spec.schedule}' 2>/dev/null)
[ "$SCHEDULE" = "*/5 * * * *" ] || fail "t15-cron schedule is '$SCHEDULE', expected '*/5 * * * *'"

# The CronJob must be suspended. `oc create job --from=cronjob/X` makes the Job OWNED by the
# CronJob, so successfulJobsHistoryLimit (default 3) garbage-collects t15-manual once three
# scheduled runs have happened. Without suspending, this task silently un-passes after ~15min.
SUSPENDED=$(oc get cronjob t15-cron -n "$NS" -o jsonpath='{.spec.suspend}' 2>/dev/null)
[ "$SUSPENDED" = "true" ] || fail "CronJob t15-cron is not suspended (spec.suspend=$SUSPENDED) — suspend it after the manual trigger, or its schedule will garbage-collect t15-manual"

oc get job t15-manual -n "$NS" >/dev/null 2>&1 \
  || fail "Job t15-manual not found in $NS — trigger the CronJob manually into a Job of that name (do not wait for the schedule)"

OWNER=$(oc get job t15-manual -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].name}')
[ "$OWNER" = "t15-cron" ] \
  || fail "Job t15-manual is not owned by CronJob t15-cron (ownerReference: '${OWNER:-none}') — it must be created FROM the CronJob, not written from scratch"

SPAWNED_SUCCEEDED=$(oc get job t15-manual -n "$NS" -o jsonpath='{.status.succeeded}')
[ "$SPAWNED_SUCCEEDED" = "1" ] || fail "Job t15-manual has not completed successfully (succeeded=$SPAWNED_SUCCEEDED)"
oc logs job/t15-manual -n "$NS" 2>/dev/null | grep -q "hello-ex280" \
  || fail "Job t15-manual's output does not contain the expected 'hello-ex280'"

oc get job t15-oneshot -n "$NS" >/dev/null 2>&1 || fail "standalone Job t15-oneshot not found"
COMPLETIONS=$(oc get job t15-oneshot -n "$NS" -o jsonpath='{.status.succeeded}')
[ "$COMPLETIONS" = "1" ] || fail "t15-oneshot has not completed successfully (succeeded=$COMPLETIONS)"
oc logs job/t15-oneshot -n "$NS" 2>/dev/null | grep -q "standalone" \
  || fail "t15-oneshot's output does not contain the expected 'standalone'"

pass "cronjob t15-cron scheduled correctly, t15-manual triggered from it and completed (output verified), t15-oneshot completed (output verified)"
