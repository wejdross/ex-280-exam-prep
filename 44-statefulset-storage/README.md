# 44 — StatefulSets and Non-Shared Storage

**Why this is on EX280:** 🔴🔴 *"Manage non-shared storage with StatefulSets"* is a named
objective under "Manage Storage for Application Configuration and Data", listed right beside
*"Provision Persistent Storage volumes for block and file-based data"* and *"Use storage
classes"*. It is the one workload controller other than Deployment that the exam names.

**Status:** ✅ verified on a live CRC cluster (2026-09-21) — two replicas, two independently
Bound PVCs from `crc-csi-hostpath-provisioner`, each pod holding its own data. Drives
`final-exam` task 24 to a PASS.

## Concept

A Deployment's pods are interchangeable: random names, and if they mount a PVC they all mount
**the same** one. A StatefulSet's pods are not:

| | Deployment | StatefulSet |
|---|---|---|
| Pod names | `app-5f7c-xk2p9` random | `app-0`, `app-1` — stable, ordinal |
| DNS | via the Service VIP only | `app-0.app.ns.svc` per pod, via a headless Service |
| Storage | one PVC shared by all replicas | **one PVC per pod**, via `volumeClaimTemplates` |
| Startup/shutdown | all at once | ordered, 0 then 1 then 2 |
| Scale down | pod deleted, PVC untouched | pod deleted, **PVC deliberately kept** |

"Non-shared storage" in the objective is precisely that third row. It's what databases,
message brokers and anything with a local write-ahead log need — each replica owns its data
directory and must get the *same* one back after a restart.

## 1. The headless Service

A StatefulSet needs a Service with `clusterIP: None` to provide per-pod DNS. It is not
optional plumbing — `spec.serviceName` must name it.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mydb
spec:
  clusterIP: None          # <- this is what "headless" means
  selector:
    app: mydb
  ports:
  - port: 8080
    name: db
```

Headless means no virtual IP and no load balancing; a DNS lookup of `mydb` returns the pod IPs
directly, and each pod also gets `mydb-0.mydb.<ns>.svc.cluster.local`.

```bash
oc create service clusterip mydb --clusterip=None --tcp=8080:8080
```

## 2. The StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mydb
spec:
  serviceName: mydb        # must match the headless Service name
  replicas: 2
  selector:
    matchLabels:
      app: mydb
  template:
    metadata:
      labels:
        app: mydb
    spec:
      containers:
      - name: db
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["sh","-c","echo $HOSTNAME > /data/id.txt; sleep 3600"]
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:    # NOT under template.spec — a sibling of it
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
      # storageClassName: crc-csi-hostpath-provisioner   # omit to use the default
```

There is **no `oc create statefulset`** generator — this one you write by hand, or crib from
`oc explain statefulset.spec.volumeClaimTemplates`. That's a legitimate use of the docs during
the exam.

The PVCs it produces are named `<volumeClaimTemplate>-<statefulset>-<ordinal>`:

```bash
oc get pvc
# data-mydb-0   Bound   ...
# data-mydb-1   Bound   ...
```

## 3. Proving the storage is really per-pod

```bash
oc exec mydb-0 -- cat /data/id.txt      # mydb-0
oc exec mydb-1 -- cat /data/id.txt      # mydb-1
```

Different values = separate volumes. If both said the same thing you'd have built a shared
mount, which is the mistake this objective exists to catch.

Identity survives rescheduling:

```bash
oc delete pod mydb-0
oc wait --for=condition=Ready pod/mydb-0 --timeout=120s
oc exec mydb-0 -- cat /data/id.txt      # still mydb-0, same PVC reattached
```

## 4. Storage classes and volume modes

```bash
oc get storageclass                      # (default) marker matters
oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}{"\n"}'
```

Omitting `storageClassName` uses the default class. Setting it to `""` (empty string)
explicitly means "no dynamic provisioning — bind to a pre-created PV only". Those are
different, and the empty-string form is a favourite exam distinction.

`volumeMode` picks block vs filesystem — the *"block and file-based data"* half of the
objective:

```yaml
      volumeMode: Filesystem   # default: formatted, mounted at mountPath
      volumeMode: Block        # raw device, consumed via volumeDevices/devicePath instead
```

Note `crc-csi-hostpath-provisioner` on CRC serves `Filesystem` only, so `Block` is a
read-the-concept item here, not something you can exercise locally.

`WaitForFirstConsumer` (the CRC default) means the PVC stays `Pending` until a pod actually
schedules — that is correct behaviour, not a fault.

## 5. Scaling and deletion semantics

```bash
oc scale statefulset/mydb --replicas=3    # creates mydb-2 AND data-mydb-2
oc scale statefulset/mydb --replicas=2    # deletes pod mydb-2; data-mydb-2 SURVIVES
oc delete statefulset mydb                # deletes pods; PVCs SURVIVE
oc delete pvc -l app=mydb                 # you clean those up deliberately
```

Keeping the PVCs is intentional: scaling down a database and losing its data on a typo would
be indefensible. It also means a re-created StatefulSet re-adopts the old volumes.

`oc delete statefulset mydb --cascade=orphan` leaves the pods running — occasionally useful
for a controller swap, and a nice thing to know exists.

## Common failure modes

- `volumeClaimTemplates` indented under `spec.template.spec` instead of under `spec`. Very
  common; the error message is unhelpful.
- `serviceName` not matching a real headless Service → pods start but per-pod DNS never works.
- Forgetting `clusterIP: None` — it becomes a normal Service and you have load balancing where
  you wanted stable identity.
- Expecting `oc delete statefulset` to reclaim storage. It never does.
- Trying to change `volumeClaimTemplates` on an existing StatefulSet. That field is immutable;
  you delete (with `--cascade=orphan` if you want the pods to survive) and recreate.
- Assuming ordered startup is optional — pod 1 will not start until pod 0 is Ready, so a
  crash-looping pod 0 blocks the whole set. `podManagementPolicy: Parallel` opts out.

## Verification checklist

```bash
oc get svc mydb -o jsonpath='{.spec.clusterIP}{"\n"}'          # None
oc get statefulset mydb -o jsonpath='{.spec.serviceName} {.spec.replicas}{"\n"}'
oc get pvc | grep data-mydb
oc get pvc data-mydb-0 -o jsonpath='{.status.phase}{"\n"}'     # Bound
oc exec mydb-0 -- cat /data/id.txt
oc exec mydb-1 -- cat /data/id.txt                             # must differ
oc rollout status statefulset/mydb
```

## Cleanup

```bash
oc delete statefulset mydb
oc delete svc mydb
oc delete pvc data-mydb-0 data-mydb-1
```
