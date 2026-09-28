# 26 — ResourceQuota + LimitRange

**Why this is on EX280:** you know the Kubernetes objects from CKAD — the OpenShift-specific
part is the `oc create quota` convenience command and where this fits into the "project admin"
storyline (quota/limits are frequently the thing you set up right after creating a project for
a team).

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## 1. ResourceQuota — caps totals for a whole project

```bash
oc create quota myquota --hard=cpu=4,memory=8Gi,pods=10 -n myproj
oc get quota -n myproj
oc describe quota myquota -n myproj    # shows USED vs HARD
```
Declarative equivalent (prefer for the exam):
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: myquota
  namespace: myproj
spec:
  hard:
    cpu: "4"
    memory: 8Gi
    pods: "10"
```

## 2. LimitRange — sets defaults/min/max **per pod/container**

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: mylimits
  namespace: myproj
spec:
  limits:
  - type: Container
    default:         { cpu: "500m", memory: "256Mi" }   # applied if container omits limits
    defaultRequest:   { cpu: "250m", memory: "128Mi" }   # applied if container omits requests
    max:             { cpu: "2",    memory: "1Gi" }
    min:             { cpu: "100m", memory: "64Mi" }
```
```bash
oc apply -f limitrange.yaml
oc describe limits mylimits -n myproj
```

## 3. Why both matter together

ResourceQuota with `cpu`/`memory` hard limits **requires every pod to specify requests/limits**
— without a LimitRange supplying defaults, pods that don't set them get rejected outright:
```
Error from server (Forbidden): pods "app" is forbidden: failed quota: myquota: must specify limits.cpu,limits.memory,requests.cpu,requests.memory
```
This is the exam trap: task says "set a quota", you do, then an earlier task's Deployment
(with no resources set) starts failing to schedule new pods. Add a LimitRange in the same
project to supply defaults, or fix the Deployment's `resources:` block directly.

## 4. Functional test — actually breach the quota

```bash
oc create quota tinyquota --hard=pods=1 -n myproj
oc run p1 --image=busybox -n myproj -- sleep 3600
oc run p2 --image=busybox -n myproj -- sleep 3600   # expect: Forbidden, exceeded quota
```

## Common failure modes
- Set a `cpu`/`memory` quota without a LimitRange → previously-fine Deployments start failing
  to create new pods (rollout stuck), and it's not obvious why unless you `oc describe rs`.
- Confused `limits` (max a container can use) with `requests` (what's reserved for scheduling)
  in a LimitRange — task usually cares about a specific one.
- Object-count quotas (`pods`, `services`, `secrets`, `persistentvolumeclaims`) forgotten —
  quota isn't just CPU/memory.

## Verification checklist
- [ ] `oc describe quota myquota -n myproj` shows correct `HARD` values
- [ ] `oc describe limits mylimits -n myproj` shows correct default/min/max
- [ ] Deliberately exceeding a quota (extra pod/PVC) is rejected with `Forbidden ... exceeded quota`
- [ ] A Deployment with no explicit resources still schedules (LimitRange defaults kick in)

## Cleanup
```bash
oc delete quota myquota tinyquota -n myproj
oc delete limitrange mylimits -n myproj
```
