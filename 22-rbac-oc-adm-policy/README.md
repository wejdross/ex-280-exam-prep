# 22 — RBAC via `oc adm policy`

**Why this is on EX280:** 🔴🔴🔴 you know Role/RoleBinding YAML from CKA — the OpenShift-specific
part is the `oc adm policy` convenience commands that do the create-Role-and-bind-it dance in
one line, plus OpenShift's built-in ClusterRoles (`admin`, `edit`, `view`, `cluster-admin`,
`basic-user`, `self-provisioner`...).

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## Built-in ClusterRoles you need to know cold

| Role | Grants |
|---|---|
| `view` | read-only, most objects, no secrets content |
| `edit` | create/modify most objects in a project, **not** RBAC/quota |
| `admin` | `edit` + manage RBAC/quota/limits **within a project** |
| `cluster-admin` | god mode, cluster-wide |
| `basic-user` | default authenticated-user baseline (see own projects etc.) |
| `self-provisioner` | allowed to `oc new-project` (bound to `system:authenticated:oauth` by default) |

## 1. Namespaced role binding (project-scoped)

```bash
oc adm policy add-role-to-user edit alice -n myproj
oc adm policy add-role-to-group view devs -n myproj
oc adm policy remove-role-from-user edit alice -n myproj
```
Prerequisite: `myproj` and the group must already exist (`oc new-project myproj`,
`oc adm groups new devs`, `oc adm groups add-users devs alice`).

## 2. Cluster-wide role binding

```bash
oc adm policy add-cluster-role-to-user cluster-admin alice
oc adm policy add-cluster-role-to-group view devs
oc adm policy remove-cluster-role-from-user cluster-admin alice
```

## 3. A very common exam pattern: lock down self-service project creation

```bash
oc adm policy remove-cluster-role-from-group self-provisioner system:authenticated:oauth
```
Verify:
```bash
oc login -u alice -p redhatB1
oc new-project alice-test    # should now be FORBIDDEN
oc login -u kubeadmin -p <pass>
```
To re-allow it: `oc adm policy add-cluster-role-to-group self-provisioner system:authenticated:oauth`.

## 3b. Project request template + default nodeSelector (developer self-service admin config)

When self-provisioning is left ON, admins often still want every self-created project to start
with certain defaults (a quota, a label, a default node selector) instead of the bare-bones
built-in template. This is a distinct, easy-to-forget objective ("developer self-service").

```bash
# dump the built-in template as a starting point, into openshift-config
oc adm create-bootstrap-project-template -o yaml > project-template.yaml
```
Edit `project-template.yaml` — the dumped template's `objects:` list already has a `Project`
entry (verified: `apiVersion: project.openshift.io/v1`, `kind: Project`, NOT `Namespace`) —
add your default annotation to that existing object, don't create a new one:
```yaml
objects:
- apiVersion: project.openshift.io/v1
  kind: Project
  metadata:
    annotations:
      openshift.io/description: ${PROJECT_DESCRIPTION}
      openshift.io/display-name: ${PROJECT_DISPLAYNAME}
      openshift.io/requester: ${PROJECT_REQUESTING_USER}
      openshift.io/node-selector: "region=west"   # <- your addition: default nodeSelector for pods in this project
    name: ${PROJECT_NAME}
```
```bash
oc create -f project-template.yaml -n openshift-config
```
Point the cluster at it (this is the step people forget — creating the template alone does nothing):
```bash
oc edit project.config.openshift.io/cluster
```
```yaml
spec:
  projectRequestTemplate:
    name: project-request      # must match metadata.name in project-template.yaml
```
This config change rolls out the `openshift-apiserver` ClusterOperator — **verified this takes
roughly 2 minutes** on a CRC cluster. Wait for `oc get co openshift-apiserver` to show
`AVAILABLE=True PROGRESSING=False` again before testing, the same gotcha as the auth operator
in `21-htpasswd-auth/`: test too early and you'll get an unrelated `ServiceUnavailable` error
(or a project created without your annotation, since the old template was still active) and
mistake it for a config mistake.

Test as a normal user: `oc new-project selftest` should now come with the annotation/defaults
already applied — check with `oc get project selftest -o yaml`.

Revert: `oc patch project.config.openshift.io/cluster --type=merge -p '{"spec":{"projectRequestTemplate":null}}'`.

## 4. Groups

```bash
oc adm groups new devs
oc adm groups add-users devs alice bob
oc adm groups remove-users devs bob
oc get groups
```

## 5. Custom Role (when a built-in role is too broad/narrow)

Sometimes the task wants a role that can only, say, list/get pods — a built-in role won't do:

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
```
```bash
oc apply -f pod-reader-role.yaml
oc adm policy add-role-to-user pod-reader alice -n myproj
```
This is plain Kubernetes RBAC — `oc adm policy` is just a shortcut for the common cases; for a
bespoke role you still hand-write the `Role`/`ClusterRole`, then bind it the normal way (either
`oc adm policy add-role-to-user <custom-role> ...` also works for custom roles, not just
built-ins).

## 6. Checking what a user can actually do

```bash
oc auth can-i create pods -n myproj --as=alice
oc auth can-i --list -n myproj --as=alice
oc describe rolebinding -n myproj
oc describe clusterrolebinding | grep -B5 alice
```

## Common failure modes
- Confusing `add-role-to-user` (namespaced, needs `-n`) with `add-cluster-role-to-user`
  (cluster-wide, no `-n` — but you CAN still scope a cluster-role to one namespace via
  `add-role-to-user <cluster-role-name> user -n proj`, since any ClusterRole can be bound
  namespace-locally too).
- Forgetting `-z` is for ServiceAccounts, not users/groups — that's `oc adm policy` for SCC,
  not RBAC roles, but the two get mixed up under exam pressure (see `23-scc-serviceaccounts/`).
- Removing `self-provisioner` from the wrong group name (`system:authenticated:oauth` vs
  `system:authenticated` — the former is specifically OAuth-authenticated users, the default
  binding target on real clusters).

## Verification checklist
- [ ] `oc auth can-i create pods -n myproj --as=alice` → `yes` after granting `edit`
- [ ] `oc auth can-i delete namespaces --as=alice` → `no` (edit doesn't grant this)
- [ ] After `self-provisioner` removal: `oc new-project` as a normal user is `Forbidden`
- [ ] `oc describe clusterrolebinding` shows alice under `cluster-admin` when granted
- [ ] After setting a project request template: a fresh `oc new-project` as a normal user shows the expected annotation/defaults in `oc get project <name> -o yaml`

## Cleanup
```bash
oc adm policy remove-cluster-role-from-user cluster-admin alice
oc adm policy add-cluster-role-to-group self-provisioner system:authenticated:oauth
oc delete group devs
oc patch project.config.openshift.io/cluster --type=merge -p '{"spec":{"projectRequestTemplate":null}}'
oc delete template project-request -n openshift-config
```
