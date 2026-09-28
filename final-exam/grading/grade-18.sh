#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t18
ns_exists "$NS" || fail "namespace $NS does not exist"

oc get imagestream t18-image -n "$NS" >/dev/null 2>&1 || fail "ImageStream t18-image not found in $NS"

ACTUAL_DIGEST=$(oc get imagestreamtag t18-image:latest -n "$NS" -o jsonpath='{.image.metadata.name}' 2>/dev/null)
[ -n "$ACTUAL_DIGEST" ] || fail "could not read digest from imagestreamtag t18-image:latest"

FILE="$WORKDIR/task18/digest.txt"
[ -f "$FILE" ] || fail "$FILE not found"
RECORDED=$(tr -d '[:space:]' < "$FILE")
[ "$RECORDED" = "$ACTUAL_DIGEST" ] || fail "recorded digest ($RECORDED) does not match actual ImageStreamTag digest ($ACTUAL_DIGEST)"

oc get deployment digest-app -n "$NS" >/dev/null 2>&1 || fail "Deployment digest-app not found"
REPLICAS=$(oc get deployment digest-app -n "$NS" -o jsonpath='{.spec.replicas}')
[ "$REPLICAS" = "1" ] || fail "digest-app replicas is '$REPLICAS', expected 1"
IMAGE=$(oc get deployment digest-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "$IMAGE" | grep -q "$ACTUAL_DIGEST" || fail "digest-app's image ('$IMAGE') does not reference the digest $ACTUAL_DIGEST"
echo "$IMAGE" | grep -q "image-registry.openshift-image-registry.svc" || fail "digest-app's image does not use the internal registry path (found: $IMAGE)"

pass "digest recorded correctly ($ACTUAL_DIGEST), digest-app pinned to it via internal registry"
