# 29 — Probes, Rollouts, Env (day-2 app management)

**Why this is on EX280:** all Kubernetes-native concepts from CKAD — listed here as the
OpenShift-idiomatic `oc set` command family, which is faster than hand-editing YAML for these
specific day-2 changes and is what the exam objectives explicitly name.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## 1. Probes

```bash
oc set probe deploy/app --readiness --get-url=http://:8080/healthz --initial-delay-seconds=5
oc set probe deploy/app --liveness  --open-tcp=8080
oc set probe deploy/app --startup   --get-url=http://:8080/healthz --failure-threshold=30 --period-seconds=5
oc set probe deploy/app --remove --readiness
```
Verify what actually landed:
```bash
oc get deploy app -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}{"\n"}'
```

## 2. Env vars — literal, ConfigMap, Secret

```bash
oc set env deploy/app KEY=value
oc set env deploy/app --from=configmap/mycm
oc set env deploy/app --from=secret/mysecret
oc set env deploy/app --list                 # show current env
oc set env deploy/app KEY-                   # remove a var (trailing '-')
```
A pod does **not** pick up ConfigMap/Secret content changes automatically unless it's
restarted (env vars are injected at container start, not live-reloaded) — after
`oc set data configmap/mycm ...`, you still need `oc rollout restart deploy/app`.

## 3. Image updates / rollout / rollback

```bash
oc set image deploy/app app=quay.io/org/image:2.0
oc rollout status deploy/app
oc rollout history deploy/app
oc rollout undo deploy/app                    # back to previous revision
oc rollout undo deploy/app --to-revision=2    # back to a specific one
oc rollout restart deploy/app                 # force new pods, same image (pick up config changes)
oc rollout pause deploy/app ; oc rollout resume deploy/app
```

## 4. Scaling

```bash
oc scale deploy/app --replicas=3
oc autoscale deploy/app --min=2 --max=6 --cpu-percent=80
```

## Common failure modes
- Changed a ConfigMap and expected the running pod to see it without a `rollout restart` — env
  vars are injected once at container start.
- Used a bare port number without the leading `:` in `--get-url=http://:8080/...` (the `:` before
  the port is required syntax for `oc set probe` — it means "current pod IP").
- `oc rollout undo` after already applying more image changes than expected — check
  `oc rollout history` first so you undo to the intended revision, not just "one back".

## Verification checklist
- [ ] `oc get deploy app -o yaml` shows the expected probe(s) under the right container
- [ ] `oc rollout status deploy/app` completes successfully after every change
- [ ] `oc exec deploy/app -- env | grep KEY` shows the expected value
- [ ] `oc rollout history deploy/app` shows the revisions you expect, in order

## Cleanup
```bash
oc scale deploy/app --replicas=1
oc set env deploy/app KEY-
```
