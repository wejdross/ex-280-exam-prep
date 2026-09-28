# 28 — Storage: StorageClass / PV / PVC

**Why this is on EX280:** you know PV/PVC/dynamic provisioning cold from CKA — this section is
just the `oc set volume` convenience command and OpenShift's default StorageClass behavior
(CRC ships with one; real exam clusters typically have one preconfigured too).

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## 1. What's available

```bash
oc get sc                          # StorageClasses; look for (default) annotation
oc get sc -o jsonpath='{range .items[*]}{.metadata.name}{" default="}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
```

## 2. Plain PVC (dynamic provisioning — no PV hand-authoring needed if a default SC exists)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mypvc
  namespace: myproj
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
  # storageClassName: <omit to use the default SC>
```
```bash
oc apply -f pvc.yaml
oc get pvc mypvc -n myproj -w      # STATUS should reach Bound
```

## 3. Attach the PVC to a Deployment — the fast way

```bash
oc set volume deploy/app --add --name=data -t pvc \
  --claim-name=mypvc --mount-path=/data -n myproj
oc rollout status deploy/app
oc exec deploy/app -- df -h /data
```
Remove it again: `oc set volume deploy/app --remove --name=data`.

## 4. Explicit (hand-authored) mount, when you need more control (subPath, readOnly, etc.)

```yaml
spec:
  template:
    spec:
      containers:
      - name: app
        volumeMounts:
        - name: data
          mountPath: /data
          # subPath: sub/dir      # only if task asks for a specific subdirectory
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: mypvc
```

## 5. Functional test — data actually persists across pod restart

```bash
oc exec deploy/app -- sh -c 'echo hello > /data/test.txt'
oc delete pod -l app=app -n myproj          # force a new pod
oc exec deploy/app -- cat /data/test.txt    # should still print "hello"
```

## Common failure modes
- PVC stuck `Pending` because no default StorageClass exists and `storageClassName` wasn't set
  — `oc describe pvc` shows the reason in Events.
- Wrong `accessModes` for the StorageClass's backing provisioner (e.g. `ReadWriteMany` on a
  provisioner that only supports `ReadWriteOnce`) — also shows in `oc describe pvc` Events.
- Forgot the PVC must exist **before** the Deployment references it, or the pod sits in
  `ContainerCreating` waiting on the volume.
- Used `oc set volume` `-t emptyDir` by accident instead of `-t pvc` — pod works, but data does
  NOT persist across pod restarts (defeats the point if the task says "persistent").

## Verification checklist
- [ ] `oc get pvc mypvc` → `STATUS: Bound`
- [ ] `oc describe deploy app` shows the volume mount at the right path
- [ ] Data written to the mount survives a pod delete/recreate (see step 5)
- [ ] If task specifies a size/accessMode, `oc get pvc mypvc -o yaml` matches exactly

## Cleanup
```bash
oc set volume deploy/app --remove --name=data -n myproj
oc delete pvc mypvc -n myproj
```
