# 27 — Jobs vs CronJobs

**Why this is on EX280:** listed as its own objective, distinct from CronJob — the exam
explicitly wants you to know when a one-shot `Job` is the right primitive vs a recurring
`CronJob`, and how to manually trigger a Job from an existing CronJob.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## 1. One-off Job

```bash
oc create job myjob --image=busybox -- echo "hello from job"
oc get jobs
oc get pods -l job-name=myjob
oc logs job/myjob
```
Jobs do **not** clean themselves up — a finished Job's pod sticks around (`Completed`) until
you delete the Job:
```bash
oc delete job myjob
```

## 2. CronJob (recurring)

```bash
oc create cronjob hello --image=busybox --schedule="*/5 * * * *" -- echo hi
oc get cronjob hello
oc get jobs -l cronjob-name=hello       # Jobs the cron has spawned so far
```
Declarative, with history limits (worth setting explicitly — default retention can surprise you):
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello
spec:
  schedule: "*/5 * * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: hello
            image: busybox
            command: ["sh", "-c", "echo hi"]
          restartPolicy: OnFailure
```

## 3. Manually fire a CronJob right now (without waiting for the schedule)

```bash
oc create job hello-manual-1 --from=cronjob/hello
oc logs job/hello-manual-1
```
This is the specific skill the exam is checking for — don't just `oc get cronjob -o yaml`,
copy-paste the podTemplate, and hand-build a Job; use `--from=cronjob/<name>`.

## 4. Suspend / resume a CronJob

```bash
oc patch cronjob hello -p '{"spec":{"suspend":true}}'
oc patch cronjob hello -p '{"spec":{"suspend":false}}'
```

## Common failure modes
- Used `oc run` (creates a bare Pod) when the task asked for a `Job` — different object, no
  restart/backoff semantics, and it won't match a grading check that looks for `kind: Job`.
- Forgot Jobs pile up `Completed` pods — if the task cares about "namespace should be clean
  after job runs", you need `ttlSecondsAfterFinished` on the Job spec or manual cleanup.
- Manually triggering a CronJob by editing its `schedule` to `* * * * *` temporarily instead of
  using `--from=cronjob/` — works but is the wrong tool and easy to forget to revert.

## Verification checklist
- [ ] `oc get job myjob` shows `COMPLETIONS: 1/1`
- [ ] `oc logs job/myjob` shows expected output
- [ ] `oc get cronjob hello` shows correct `SCHEDULE` column
- [ ] `oc create job ... --from=cronjob/hello` produces a new Job that completes successfully

## Cleanup
```bash
oc delete cronjob hello
oc delete job --all -n myproj
```
