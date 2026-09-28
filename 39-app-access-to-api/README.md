# 39 — Allowing Application Access to the Kubernetes/OpenShift API

**Why this is on EX280:** 🔴 confirmed as its own DO280 section ("Allowing Application Access
to Kubernetes APIs"), distinct from SCC. This is about an app **inside** a pod calling the
cluster API itself (e.g. a controller/operator-style workload that lists/watches other pods, or
a sidecar that needs to read its own pod's labels) — a different problem than "what can this
pod's container do on the host" (that's SCC's job).

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — API call from inside a pod
succeeded (200) with the RoleBinding in place, and correctly returned 403 after removing it.

## Concept

Every pod is automatically given a token for its ServiceAccount, mountable at
`/var/run/secrets/kubernetes.io/serviceaccount/token`. That token authenticates **as the
ServiceAccount** against the API server — what it's actually allowed to do is governed by
ordinary RBAC (Role/RoleBinding), same as any user. "Can my app call the API" is really just
"does this SA have a Role bound that grants the verbs/resources it needs" — SCC never enters
into it.

## 1. Confirm the token is there (it is, by default, unless explicitly disabled)

```bash
oc exec deploy/myapp -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | cut -c1-20
oc exec deploy/myapp -- cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
```
To explicitly opt OUT (rare, only if a task says "the app must not have API access"):
```yaml
spec:
  automountServiceAccountToken: false
```

## 2. Give the ServiceAccount just the RBAC it needs

Example: an app that needs to list Pods in its own namespace (a common "operator-ish" pattern):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: myproj
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: myapp-pod-reader
  namespace: myproj
subjects:
- kind: ServiceAccount
  name: myapp-sa
  namespace: myproj
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```
```bash
oc create sa myapp-sa -n myproj
oc apply -f pod-reader-role.yaml -f myapp-pod-reader-binding.yaml
oc set serviceaccount deploy/myapp myapp-sa -n myproj
```
This is the exact same RBAC mechanics as `22-rbac-oc-adm-policy/` — the only thing new here is
the subject is a `ServiceAccount` (a workload) instead of a `User`/`Group` (a person).

## 3. Functional test — call the API from inside the pod using its own token

```bash
oc exec deploy/myapp -n myproj -- sh -c '
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  curl -sk -H "Authorization: Bearer $TOKEN" \
    https://kubernetes.default.svc/api/v1/namespaces/myproj/pods | head -c 200
'
```
A successful JSON response (not a `403 Forbidden`) confirms both the token exists and the RBAC
binding actually grants access.

## 4. `oc create token` — short-lived tokens for testing (not for baking into pod specs)

```bash
oc create token myapp-sa -n myproj --duration=10m
```
Useful for manually testing from your own terminal (e.g. with `curl`) without waiting for a
pod to exist — a real running pod always gets its own bound token automatically, you never
need to inject one manually via a Secret in modern OpenShift/Kubernetes versions.

## Common failure modes
- Granting SCC instead of RBAC when the task is about API access — SCC governs container
  runtime privileges (UID, capabilities, host access), completely separate from "can this
  ServiceAccount call the Kubernetes API."
- Binding the Role to a `User` named the same as the ServiceAccount instead of
  `kind: ServiceAccount` — silently grants nothing to the actual running pod.
- Forgetting `oc set serviceaccount` (or `serviceAccountName:` in the pod spec) — creating the
  SA and RBAC binding does nothing if the pod is still running as `default`.
- Assuming the token needs to be manually created/mounted as a Secret — the projected
  ServiceAccount token is automatic; manual token Secrets are a legacy pattern.

## Verification checklist
- [ ] `oc get sa myapp-sa -n myproj` exists and is referenced by the Deployment's `serviceAccountName`
- [ ] `oc auth can-i list pods -n myproj --as=system:serviceaccount:myproj:myapp-sa` → `yes`
- [ ] A live `curl` from inside the pod against the API server succeeds (not 403/401)
- [ ] Removing the RoleBinding causes the same call to fail with `403 Forbidden`

## Cleanup
```bash
oc delete role pod-reader -n myproj
oc delete rolebinding myapp-pod-reader -n myproj
oc delete sa myapp-sa -n myproj
```
