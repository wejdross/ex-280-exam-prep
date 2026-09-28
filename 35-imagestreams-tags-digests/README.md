# 35 — ImageStreams, Tags vs Digests

**Why this is on EX280:** ImageStreams are an OpenShift-only abstraction over container
images (no Kubernetes-native equivalent) — a level of indirection that lets Deployments
auto-roll on new pushes and lets you pin exact, immutable image references via digest.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## Concept

An `ImageStream` is a virtual "list of tags", each `ImageStreamTag` pointing at a specific
image digest in some registry (internal or external). `oc new-app`/S2I builds create one
automatically; a Deployment can either reference a plain image string (no ImageStream
involved) or be configured to track an ImageStreamTag so it auto-redeploys on new pushes
(via an `ImageChangeTrigger` — more of a build/CI-adjacent feature, know it exists).

## 1. Inspect ImageStreams

```bash
oc get is -n myproj
oc describe is <name> -n myproj                  # every tag + the digest it currently points at
oc get imagestreamtag <name>:latest -n myproj -o yaml
```

## 2. Import an external image into an ImageStream

```bash
oc import-image my-nginx:latest --from=quay.io/redhattraining/hello-world-nginx --confirm -n myproj
oc tag quay.io/redhattraining/hello-world-nginx:latest myproj/my-nginx:v1
```

## 3. Tag vs digest — the concept the exam is actually testing

```bash
oc describe imagestreamtag my-nginx:latest -n myproj
# Image Name:  quay.io/redhattraining/hello-world-nginx@sha256:abcdef1234...
```
- **Tag** (`image:latest`, `image:v1`) — a **mutable, moving label**. Can point at a different
  digest tomorrow if someone pushes over it.
- **Digest** (`image@sha256:...`) — **immutable**, content-addressed. The only way to guarantee
  "this is bit-for-bit the same image every time", which is why production Deployments should
  reference a digest (or an ImageStreamTag, which resolves to a digest under the hood at
  admission time) rather than a bare mutable tag.

```bash
oc image info quay.io/redhattraining/hello-world-nginx@sha256:<digest>
```

## 4. Point a Deployment at an ImageStreamTag (vs a raw registry string)

```bash
oc set image deploy/app app=image-registry.openshift-image-registry.svc:5000/myproj/my-nginx:v1
```
Or reference the ImageStream directly at creation:
```bash
oc new-app --name=app --image-stream=myproj/my-nginx:v1
```

## Common failure modes
- Assumed `image:latest` always means "the newest build" — it means whatever `latest` was
  last pointed at; if nobody re-tagged it, it can be stale for a long time.
- Confused the **internal registry path**
  (`image-registry.openshift-image-registry.svc:5000/<namespace>/<name>:<tag>`) with the
  external one (`quay.io/...`) when wiring a Deployment to an ImageStream — the internal path
  is required if you want the Deployment to actually resolve through the ImageStream/registry.
- Tried to `oc image info` using a tag instead of a digest when the task specifically asked to
  identify/verify a digest — tags don't uniquely identify a build, which is the whole point
  being tested.

## Verification checklist
- [ ] `oc get is` shows the ImageStream with the expected tag(s)
- [ ] `oc describe imagestreamtag <name>:<tag>` shows a concrete `sha256:` digest, not another tag
- [ ] `oc image info <image>@sha256:...` returns valid image metadata (arch, layers, created date)
- [ ] A Deployment referencing the ImageStream pulls successfully (`oc describe pod` shows correct image, no `ImagePullBackOff`)

## Cleanup
```bash
oc delete is my-nginx -n myproj
```
