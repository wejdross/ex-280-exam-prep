# 46 — Project Request Template and ClusterResourceQuota

**Why this is on EX280:** 🔴🔴 the "Enable Developer Self-Service" objective lists
*"Configure project templates"* and *"Configure cluster resource quotas"* as separate items
from the per-project quota work in topic 26. Both are cluster-scoped, both are pure OpenShift,
and both are easy to skip because `26-quota-limitrange` feels like it already covered quotas.
It didn't — that one is `ResourceQuota` (namespaced); this one is `ClusterResourceQuota`.

**Status:** ✅ verified on a live CRC cluster (2026-09-21) — template in effect, a newly
created project received the injected LimitRange, CRQ selector matched. Drives `final-exam`
task 26 to a PASS.

## Part A — Project request template

### Concept

When a user runs `oc new-project`, the apiserver processes a **Template** to decide what the
new project contains. By default that template creates the Project and a couple of
RoleBindings. Replace it, and every future project is born with whatever you put in it — a
LimitRange, a default NetworkPolicy, a quota, a nodeSelector.

This is the supported way to enforce "every project must have X" without a mutating webhook.

### 1. Dump the built-in template as a starting point

```bash
oc adm create-bootstrap-project-template -o yaml > project-request.yaml
```

Never write this from scratch — the built-in one contains the RoleBindings that make a project
usable, and omitting them breaks self-service in a way that is annoying to debug.

### 2. Add what you want injected

Append to `objects:`. `${PROJECT_NAME}` is the parameter the apiserver fills in:

```yaml
- apiVersion: v1
  kind: LimitRange
  metadata:
    name: default-limits
    namespace: ${PROJECT_NAME}
  spec:
    limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      default:
        cpu: 500m
        memory: 512Mi
```

Name the template itself something stable:

```yaml
metadata:
  name: project-request
```

### 3. Install it and point the cluster at it

```bash
oc apply -f project-request.yaml -n openshift-config

oc patch project.config.openshift.io/cluster --type=merge \
  -p '{"spec":{"projectRequestTemplate":{"name":"project-request"}}}'
```

The template **must** live in `openshift-config`. The config object is
`project.config.openshift.io/cluster` — not to be confused with a `Project` object.

### 4. Wait for the rollout — this is the part that wastes exam time

Patching that config restarts the **openshift-apiserver**. For a few minutes:

- `oc get template` fails with `the server doesn't have a resource type "template"`
- new projects still use the *old* template

```bash
oc get co openshift-apiserver            # wait for Available=True, Progressing=False
oc get templates.template.openshift.io -n openshift-config   # real readiness test
```

Verified on CRC: the operator briefly reports settled *before* the rollout begins, so check
twice, a minute apart, before concluding anything. Budget ~3–5 minutes.

### 5. Prove it works

```bash
oc new-project template-probe
oc get limitrange -n template-probe        # default-limits must be here
oc delete project template-probe
```

### Reverting

```bash
oc patch project.config.openshift.io/cluster --type=merge \
  -p '{"spec":{"projectRequestTemplate":null}}'
oc delete template project-request -n openshift-config
```

### Related: disabling self-service entirely

Covered in `22-rbac-oc-adm-policy`, but the pair comes up together:

```bash
oc adm policy remove-cluster-role-from-group self-provisioner system:authenticated:oauth
oc adm policy add-cluster-role-to-user self-provisioner alice
```

## Part B — ClusterResourceQuota

### Concept

A `ResourceQuota` caps one project. A `ClusterResourceQuota` (CRQ) caps an **aggregate across
many projects**, selected by label or by annotation. The canonical use: "this user's projects
may consume 10 pods total, however many projects they create."

It is an OpenShift-only object — `quota.openshift.io/v1`.

### 1. Select by requester annotation

Every project created via `oc new-project` gets `openshift.io/requester: <username>`.

```bash
oc create clusterresourcequota ex280-crq \
  --project-annotation-selector=openshift.io/requester=alice \
  --hard=pods=10 --hard=memory=4Gi
```

```yaml
apiVersion: quota.openshift.io/v1
kind: ClusterResourceQuota
metadata:
  name: ex280-crq
spec:
  selector:
    annotations:
      openshift.io/requester: alice
  quota:
    hard:
      pods: "10"
      memory: 4Gi
```

### 2. Or select by project label

```bash
oc create clusterresourcequota team-crq \
  --project-label-selector=team=platform \
  --hard=pods=50 --hard=requests.cpu=20
```

```yaml
spec:
  selector:
    labels:
      matchLabels:
        team: platform
```

Use one or the other. Both set at once means a project must match **both**.

### 3. Watching consumption

```bash
oc describe clusterresourcequota ex280-crq
oc get clusterresourcequota ex280-crq -o jsonpath='{.status.total.used}{"\n"}'
oc get appliedclusterresourcequota -n <project>    # the view from inside a project
```

`status.namespaces[]` lists every project currently matched and its share — the quickest way
to confirm the selector actually matches something.

### Quota field names that matter

| Field | Caps |
|---|---|
| `pods` | pod count |
| `requests.cpu` / `requests.memory` | sum of requests |
| `limits.cpu` / `limits.memory` | sum of limits |
| `memory` | alias for `requests.memory` |
| `persistentvolumeclaims` | PVC count |
| `count/deployments.apps` | object counts of any kind |

## Common failure modes

- Putting the project request template anywhere other than `openshift-config`.
- Writing the template from scratch and losing the default RoleBindings — new projects are
  created but their owner can't use them.
- Grading or testing immediately after the patch, before the apiserver rollout finishes, and
  concluding the template is wrong when it is merely not live yet.
- Confusing `ResourceQuota` (namespaced, topic 26) with `ClusterResourceQuota` (cluster-scoped,
  selector-based). The exam objectives list them separately on purpose.
- A CRQ whose selector matches nothing — it will happily exist and enforce nothing. Always
  check `status.namespaces`.
- Forgetting that `openshift.io/requester` is only set on projects created *by a user* via
  `new-project`; a project created by `oc create ns` as admin has no requester annotation.

## Verification checklist

```bash
oc get project.config.openshift.io/cluster -o jsonpath='{.spec.projectRequestTemplate.name}{"\n"}'
oc get templates.template.openshift.io project-request -n openshift-config
oc new-project probe-$$ && oc get limitrange -n probe-$$ && oc delete project probe-$$

oc get clusterresourcequota ex280-crq -o jsonpath='{.spec.selector}{"\n"}'
oc get clusterresourcequota ex280-crq -o jsonpath='{.spec.quota.hard}{"\n"}'
oc describe clusterresourcequota ex280-crq | sed -n '/Namespaces/,$p'
```

## Cleanup

```bash
oc patch project.config.openshift.io/cluster --type=merge -p '{"spec":{"projectRequestTemplate":null}}'
oc delete template project-request -n openshift-config
oc delete clusterresourcequota ex280-crq
```
