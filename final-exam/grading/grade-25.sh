#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t25
ns_exists "$NS" || fail "namespace $NS does not exist"

# --- ImageStream imported ---
oc get imagestream t25-app -n "$NS" >/dev/null 2>&1 || fail "ImageStream t25-app not found in $NS"
DIGEST=$(oc get istag t25-app:latest -n "$NS" -o jsonpath='{.image.metadata.name}' 2>/dev/null)
[ -n "$DIGEST" ] || fail "ImageStreamTag t25-app:latest has no resolved image — was the import successful?"

# --- Deployment exists and is ready ---
oc get deployment trigger-app -n "$NS" >/dev/null 2>&1 || fail "Deployment trigger-app not found"
oc rollout status deployment/trigger-app -n "$NS" --timeout=150s >/dev/null 2>&1 \
  || fail "Deployment trigger-app never became ready"

# --- the trigger annotation ---
ANN=$(oc get deployment trigger-app -n "$NS" -o jsonpath='{.metadata.annotations.image\.openshift\.io/triggers}' 2>/dev/null)
[ -n "$ANN" ] || fail "Deployment trigger-app has no 'image.openshift.io/triggers' annotation — the image is not driven by the ImageStream"

echo "$ANN" | grep -q '"kind":"ImageStreamTag"' \
  || fail "triggers annotation does not reference an ImageStreamTag (got: $ANN)"
echo "$ANN" | grep -q 't25-app:latest' \
  || fail "triggers annotation does not reference t25-app:latest (got: $ANN)"
echo "$ANN" | grep -q '"paused":true' \
  && fail "the image trigger is paused — it must be active (pause: false)"

# the fieldPath must select the deployment's own container by name. The annotation stores it
# JSON-escaped (containers[?(@.name==\"foo\")].image), so match the pieces, not the raw string.
CNAME=$(oc get deployment trigger-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].name}')
echo "$ANN" | grep -q 'fieldPath' \
  || fail "triggers annotation has no fieldPath (got: $ANN)"
echo "$ANN" | grep -q "containers" && echo "$ANN" | grep -qF "$CNAME" \
  || fail "triggers annotation fieldPath does not point at container '$CNAME' (got: $ANN)"

# --- proof the trigger actually fired: the image was rewritten to a DIGEST pull spec
# carrying the tag's current digest. Which registry host appears depends on the tag's
# referencePolicy (Source -> quay.io@sha256:..., Local -> image-registry...svc:5000/...),
# so only the digest itself is checked.
IMAGE=$(oc get deployment trigger-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "$IMAGE" | grep -q "@sha256:" \
  || fail "container image is '$IMAGE' — still a mutable tag reference, so the trigger never fired"
echo "$IMAGE" | grep -q "$DIGEST" \
  || fail "container image '$IMAGE' does not carry the current t25-app:latest digest ($DIGEST)"

pass "t25-app imported, trigger-app driven by an active ImageStreamTag trigger, image resolved to digest $DIGEST"
