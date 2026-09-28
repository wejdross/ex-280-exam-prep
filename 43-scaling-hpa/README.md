# 43 — Scaling and Autoscaling

**Why this is on EX280:** 🔴🔴 *"Scale applications to meet increased demand"* is a named
objective under "Configure Applications for Reliability". Manual scaling is trivial; the HPA
half has one hard prerequisite that fails silently, which is exactly why it makes a good exam
item.

**Status:** ✅ verified on a live CRC cluster (2026-09-21) — `metrics.k8s.io/v1beta1` is served
on CRC out of the box, `oc adm top nodes` returns data, and the HPA path drives `final-exam`
task 22 to a PASS.

## Concept

Three different things get called "scaling":

| | What it does | Object |
|---|---|---|
| Manual | you set the replica count | `spec.replicas` |
| Horizontal autoscaling | controller sets replicas from a metric | `HorizontalPodAutoscaler` |
| Cluster autoscaling | adds/removes **nodes** | `MachineAutoscaler` (not on CRC — single node) |

EX280 cares about the first two.

## 1. Manual scaling

```bash
oc scale deployment/myapp --replicas=3
oc scale statefulset/mydb --replicas=2

# conditional — only scale if it's currently at 3 (avoids racing another change)
oc scale deployment/myapp --current-replicas=3 --replicas=5

oc get deployment myapp -o jsonpath='{.status.readyReplicas}/{.spec.replicas}{"\n"}'
```

## 2. The prerequisite everyone forgets

**An HPA targeting CPU *utilisation* cannot work unless the container has a CPU `request`.**
Utilisation is defined as `actual CPU / requested CPU`. With no request there is no
denominator, the HPA reports `<unknown>`, and it never scales. Nothing errors — it just
quietly does nothing.

```bash
oc set resources deployment/myapp --requests=cpu=50m,memory=64Mi
```

```yaml
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
```

Check the cluster can actually serve metrics before you blame your HPA:

```bash
oc get --raw /apis/metrics.k8s.io/v1beta1 >/dev/null && echo "metrics API up"
oc adm top nodes
oc adm top pods
```

## 3. Creating the HPA

```bash
# NOTE: --cpu-percent is DEPRECATED on oc 4.22 — it still works but warns.
oc autoscale deployment/myapp --min=3 --max=6 --cpu-percent=70     # old form
oc autoscale deployment/myapp --min=3 --max=6 --cpu=70%            # current form
```

`oc autoscale` writes an `autoscaling/v2` object on OCP 4.x. Hand-written equivalent:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 3
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

The v1 shape you may still see in older material — same meaning, different field:

```yaml
apiVersion: autoscaling/v1
spec:
  targetCPUUtilizationPercentage: 70
```

Memory works the same way, `name: memory`. `type: AverageValue` targets an absolute amount
(`averageValue: 100m`) rather than a percentage of the request, and does **not** need a
request set — useful to know as the escape hatch.

## 4. Watching it

```bash
oc get hpa
# NAME    REFERENCE             TARGETS              MINPODS  MAXPODS  REPLICAS
# myapp   Deployment/myapp      cpu: <unknown>/70%   3        6        0

oc describe hpa myapp        # the Events + Conditions here explain any refusal to scale
```

`<unknown>` for the first minute or two after creation is **normal** — metrics-server needs a
couple of scrape intervals. `<unknown>` that never resolves means no CPU request, or the
metrics API is down.

Useful conditions in `oc describe hpa`:

- `AbleToScale` — can it act at all
- `ScalingActive` — is it getting metrics (False + `FailedGetResourceMetric` is the no-request case)
- `ScalingLimited` — it wants to scale further but hit min/max

## 5. Interaction with `oc scale` and with GitOps

Once an HPA exists it owns `spec.replicas`. `oc scale` still works but the HPA will move it
back on its next cycle. Leaving a hardcoded `replicas:` in a manifest that an HPA also manages
is a genuine production footgun — under Argo CD it causes a permanent sync loop, which is why
`replicas` is a standard `ignoreDifferences` entry.

## Common failure modes

- No CPU request on the container → `TARGETS` stuck at `<unknown>` forever. **The #1 cause.**
- Targeting the wrong kind (`--as=replicaset`, or a Deployment name that doesn't exist) —
  `oc describe hpa` says `FailedGetScale`.
- Setting `minReplicas` above the Deployment's current replicas and then being confused when
  the HPA immediately scales *up*: min is a floor, it is enforced regardless of load.
- Expecting the HPA to scale down instantly. There is a stabilisation window (5 minutes by
  default) on scale-down.
- Using `--cpu-percent` and reading the deprecation warning as an error.

## Verification checklist

```bash
oc get deployment myapp -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}{"\n"}'
oc get hpa myapp -o jsonpath='{.spec.minReplicas}/{.spec.maxReplicas} target={.spec.metrics[0].resource.target.averageUtilization}{"\n"}'
oc get deployment myapp -o jsonpath='{.status.readyReplicas}{"\n"}'
oc describe hpa myapp | sed -n '/Conditions/,/Events/p'
```

## Cleanup

```bash
oc delete hpa myapp
oc delete deployment myapp
```
