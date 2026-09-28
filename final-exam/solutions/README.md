# Solutions — every task, the `oc` way and the YAML way

One file per task. Each shows:

- **`oc` path** — the fastest route, what you should reach for under time pressure
- **YAML path** — the manifest, for when a task demands a field `oc` can't set, or when you
  want to read the object's real shape
- **Verify** — what to run before moving on

Every command here was executed against a live CRC 4.22.7 cluster on 2026-09-21 and drove its
grader to PASS (full suite: 420/420). Manifests referenced as `solutions/yaml/*.yaml` are the
exact files that were applied.

## The general rule

Almost everything on this exam is faster imperatively. The `oc create ... --dry-run=client -o
yaml` trick gets you a manifest skeleton without typing one:

```bash
oc create deployment app --image=IMG --replicas=2 --dry-run=client -o yaml > app.yaml
```

Objects with **no generator** — you write or crib these:

| Object | How to start it |
|---|---|
| StatefulSet | `oc explain statefulset.spec.volumeClaimTemplates`, or copy task 24 |
| NetworkPolicy | copy task 08 |
| Template | `oc adm create-bootstrap-project-template -o yaml` for project requests; else hand-write |
| PVC | `oc set volume --claim-size` creates one for you |
| SCC | `oc get scc restricted-v2 -o yaml` and edit |
| LimitRange | hand-write |

## Things that cost people points

- `oc run pod -n ns --command -- sleep 3600` — **`-n` must come before `--`**, or it becomes an
  argument to `sleep` and the pod crash-loops.
- `oc set env --from=configmap/x` produces per-key `configMapKeyRef`, not `envFrom`.
- `oc auth can-i --as=<user>` does **not** resolve OpenShift Group membership. Group-granted
  access only shows up on a real login.
- `--cpu-percent` on `oc autoscale` is deprecated on 4.22; use `--cpu=70%`.
- Patching `project.config.openshift.io/cluster` restarts the openshift-apiserver. Templates
  are unreachable for minutes afterwards. Budget for it.
- `${PARAM}` in a Template is always a string. Use `${{PARAM}}` for ints like `replicas`.
