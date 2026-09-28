# 23 — Security Context Constraints (SCC) + ServiceAccounts

**Why this is on EX280:** 🔴🔴🔴 classic exam killer. CKS teaches PodSecurity admission
(Kubernetes-native); OpenShift additionally (and by default, more strictly) enforces **SCC**.
A pod that would run fine on vanilla Kubernetes can sit in `CreateContainerError` /
`Forbidden` on OpenShift purely because its ServiceAccount lacks the right SCC.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## Concept

Every pod runs under a ServiceAccount (SA). Every SA is allowed to use some set of SCCs
(similar shape to PodSecurityPolicy, but admission-controller-driven and OpenShift-specific).
Default SA (`default`) in a fresh project can only use `restricted-v2` (default since OCP
4.11) — no root, no extra capabilities, UID from a per-namespace allocated range.

```bash
oc get scc
oc describe scc restricted-v2
oc describe scc anyuid
oc describe scc nonroot-v2
```

Key SCCs to recognize by name:
| SCC | Effect |
|---|---|
| `restricted-v2` | default; no root, drops ALL capabilities, random UID from namespace range |
| `nonroot-v2` | any non-zero UID allowed (image can request its own UID, just not 0) |
| `anyuid` | any UID including 0 (root) allowed |
| `privileged` | everything allowed — avoid unless task explicitly demands it |
| `hostnetwork`/`hostmount-anyuid` | node-level access — rare, only if task needs host network/paths |

## 1. Diagnose the symptom first

```bash
oc get pods -n myproj
oc describe pod <pod> -n myproj | tail -20     # Events section: "unable to validate against any security context constraint"
oc get pod <pod> -o jsonpath='{.spec.serviceAccountName}{"\n"}'
```

## 2. Create a dedicated ServiceAccount (don't just grant SCC to `default` unless asked)

```bash
oc create sa mysa -n myproj
```

## 3. Grant the SCC — `-z`, not a bare username

```bash
oc adm policy add-scc-to-user anyuid  -z mysa -n myproj
oc adm policy add-scc-to-user nonroot-v2 -z mysa -n myproj
oc adm policy remove-scc-from-user anyuid -z mysa -n myproj
```
`-z <name>` = shorthand for `system:serviceaccount:<current-project>:<name>` — this is the
single most-forgotten flag on the exam. Without `-z` you're granting the SCC to a *user* named
`mysa`, which does nothing for the pod.

## 4. Point the workload at that ServiceAccount

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: needs-root
  namespace: myproj
spec:
  replicas: 1
  selector: { matchLabels: { app: needs-root } }
  template:
    metadata: { labels: { app: needs-root } }
    spec:
      serviceAccountName: mysa
      containers:
      - name: app
        image: quay.io/redhattraining/hello-world-nginx:latest
```
```bash
oc apply -f needs-root-deploy.yaml
oc rollout status deploy/needs-root
```
Or on an existing Deployment: `oc set serviceaccount deploy/needs-root mysa`.

## 5. Confirm which SCC a running pod actually landed on

```bash
oc get pod <pod> -o jsonpath='{.metadata.annotations.openshift\.io/scc}{"\n"}'
```

## Common failure modes
- Granted the SCC to the wrong SA, or to a user instead of `-z serviceaccount` — pod still fails.
- Granted SCC in the wrong namespace (`-n` matters — SA identity includes the namespace).
- Deployment still references `serviceAccountName: default` after creating `mysa` — SCC grant
  alone does nothing if the pod spec doesn't use that SA.
- Reached for `privileged` when `anyuid` or `nonroot-v2` would have satisfied the task — on the
  real exam, overshooting privilege can cost points if the rubric checks for least-privilege.
- Forgot pods must be **recreated** (rollout / delete pod) after changing `serviceAccountName`
  or SCC grants — existing running pods don't retroactively re-validate.

## Verification checklist
- [ ] `oc get sa mysa -n myproj` exists
- [ ] `oc describe scc anyuid` shows `mysa` (fully qualified) under Users
- [ ] Pod using `serviceAccountName: mysa` reaches `Running`/`1/1`, no SCC error in `describe pod`
- [ ] `oc get pod <pod> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'` prints the expected SCC name

## Cleanup
```bash
oc adm policy remove-scc-from-user anyuid -z mysa -n myproj
oc delete sa mysa -n myproj
oc delete deploy needs-root -n myproj
```
