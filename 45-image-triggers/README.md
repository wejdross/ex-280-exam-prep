# 45 — Image Triggers

**Why this is on EX280:** 🔴🔴 *"Use triggers to manage images"* is a named objective under
"Manage Application Updates", alongside *"Identify images using tags and digests"* and
*"Manage image streams"*. Purely OpenShift — vanilla Kubernetes has no equivalent, which is
exactly the kind of thing this exam likes.

**Status:** ✅ verified on a live CRC cluster (2026-09-21) — trigger fired and rewrote the
container image to a digest within seconds. Drives `final-exam` task 25 to a PASS.

## Concept

An ImageStream tracks an image. A **trigger** connects a workload to an ImageStreamTag so that
when the tag resolves to a new digest, OpenShift **patches the workload's image field** and a
rollout happens automatically. You never edit the Deployment.

The mechanism differs by workload type, and knowing which is which matters:

| Workload | Mechanism |
|---|---|
| Deployment / DaemonSet / StatefulSet / CronJob | `image.openshift.io/triggers` **annotation** |
| DeploymentConfig (legacy) | `spec.triggers` with `type: ImageChange` |
| BuildConfig | `spec.triggers` with `type: ImageChange` |

Deployments are plain Kubernetes objects, so OpenShift can't add fields to them — hence the
annotation, which a controller watches and acts on.

## 1. Set up the ImageStream

```bash
oc import-image myapp:latest \
  --from=quay.io/redhattraining/hello-world-nginx:latest --confirm

oc get istag myapp:latest -o jsonpath='{.image.metadata.name}{"\n"}'   # the digest
```

## 2. Attach the trigger

```bash
oc create deployment trigger-app --image=quay.io/redhattraining/hello-world-nginx:latest

# the container name must be named explicitly
CNAME=$(oc get deploy trigger-app -o jsonpath='{.spec.template.spec.containers[0].name}')
oc set triggers deployment/trigger-app --from-image=myapp:latest -c "$CNAME"

oc set triggers deployment/trigger-app          # list what's attached
```

What that writes:

```yaml
metadata:
  annotations:
    image.openshift.io/triggers: |
      [{"from":{"kind":"ImageStreamTag","name":"myapp:latest"},
        "fieldPath":"spec.template.spec.containers[?(@.name==\"hello-world-nginx\")].image"}]
```

`fieldPath` is a JSONPath selecting *which field to rewrite*. That is why the container name is
required — the controller has to know which container's image to patch.

## 3. Confirming it fired

```bash
oc get deploy trigger-app -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Before: `quay.io/redhattraining/hello-world-nginx:latest`
After:  `quay.io/redhattraining/hello-world-nginx@sha256:7f99ece5...`

**The tag becomes a digest.** That rewrite *is* the proof the trigger worked. If the image is
still a `:tag`, the trigger never fired.

### Which registry hostname appears

This surprises people. It depends on the tag's **reference policy**:

```bash
oc get istag myapp:latest -o jsonpath='{.tag.referencePolicy.type}{"\n"}'
```

| Policy | Resolved image becomes |
|---|---|
| `Source` (default) | `quay.io/redhattraining/hello-world-nginx@sha256:...` |
| `Local` | `image-registry.openshift-image-registry.svc:5000/<ns>/myapp@sha256:...` |

Set it with `oc import-image ... --reference-policy=local` or
`oc tag src dest --reference-policy=local`. `Local` forces pulls through the internal registry
(pullthrough), which is what you want when the external registry needs credentials the nodes
don't have. Either way the **digest is the same** — that's the part to verify.

## 4. Pausing and removing

```bash
oc set triggers deployment/trigger-app --from-image=myapp:latest -c app --remove
oc set triggers deployment/trigger-app --manual        # pause all image triggers
oc set triggers deployment/trigger-app --auto          # resume
```

A paused trigger shows `"paused":true` in the annotation. Manual mode is how you stage an
update and release it deliberately.

## 5. Making a new image actually arrive

```bash
oc import-image myapp:latest --from=<newer image> --confirm   # re-import, digest changes
oc tag other-ns/other-is:v2 myapp:latest                      # or re-point the tag
oc rollout status deployment/trigger-app
```

Scheduled re-import (so the tag polls upstream by itself):

```bash
oc import-image myapp:latest --from=quay.io/... --confirm --scheduled=true
oc get is myapp -o jsonpath='{.spec.tags[0].importPolicy}{"\n"}'
```

## 6. The DeploymentConfig form, for contrast

```yaml
spec:
  triggers:
  - type: ImageChange
    imageChangeParams:
      automatic: true
      containerNames: [app]
      from:
        kind: ImageStreamTag
        name: myapp:latest
```

```bash
oc set triggers dc/myapp --from-image=myapp:latest -c app
oc rollout latest dc/myapp     # force a redeploy; Deployments have no equivalent
```

## Common failure modes

- Omitting `-c <container>` → `oc set triggers` cannot build a `fieldPath` and the trigger
  does nothing useful.
- Using the *image name* instead of the *ImageStreamTag name* in `--from-image`. It wants
  `myapp:latest`, not `quay.io/.../hello-world-nginx:latest`.
- The ImageStreamTag is in a different namespace — then it must be `ns/is:tag`, and the
  workload's SA needs `system:image-puller` there.
- Expecting the trigger to fire when nothing changed. Re-importing an identical image produces
  the same digest, so there is no patch and no rollout. That is correct.
- Grading (or debugging) by looking for the internal registry hostname when the tag's
  reference policy is `Source`. Check the **digest**, not the host.
- Leaving a trigger attached while also managing the image in Git. The controller and your
  pipeline will fight over `spec.template.spec.containers[].image`.

## Verification checklist

```bash
oc get istag myapp:latest -o jsonpath='{.image.metadata.name}{"\n"}'
oc get deploy trigger-app -o jsonpath='{.metadata.annotations.image\.openshift\.io/triggers}{"\n"}'
oc get deploy trigger-app -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'  # must contain @sha256:
oc set triggers deployment/trigger-app
oc rollout status deployment/trigger-app
```

## Cleanup

```bash
oc delete deployment trigger-app
oc delete is myapp
```
