#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t22
ns_exists "$NS" || fail "namespace $NS does not exist"

oc get deployment scale-app -n "$NS" >/dev/null 2>&1 || fail "Deployment scale-app not found"

# --- CPU request: without it an HPA can never compute utilisation ---
CPUREQ=$(oc get deployment scale-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
[ -n "$CPUREQ" ] || fail "scale-app's container has no CPU request — a CPU-utilisation HPA cannot work without one"
[ "$CPUREQ" = "50m" ] || fail "scale-app CPU request is '$CPUREQ', expected '50m'"

MEMREQ=$(oc get deployment scale-app -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')
[ "$MEMREQ" = "64Mi" ] || fail "scale-app memory request is '$MEMREQ', expected '64Mi'"

# --- scaled to 3 and actually ready ---
oc rollout status deployment/scale-app -n "$NS" --timeout=120s >/dev/null 2>&1 \
  || fail "Deployment scale-app never became ready"
READY=$(oc get deployment scale-app -n "$NS" -o jsonpath='{.status.readyReplicas}')
[ "$READY" = "3" ] || fail "scale-app has readyReplicas=$READY, expected 3"

# --- HPA ---
oc get hpa scale-app -n "$NS" >/dev/null 2>&1 || fail "HorizontalPodAutoscaler scale-app not found"

REF_KIND=$(oc get hpa scale-app -n "$NS" -o jsonpath='{.spec.scaleTargetRef.kind}')
REF_NAME=$(oc get hpa scale-app -n "$NS" -o jsonpath='{.spec.scaleTargetRef.name}')
[ "$REF_KIND" = "Deployment" ] || fail "HPA scaleTargetRef.kind is '$REF_KIND', expected Deployment"
[ "$REF_NAME" = "scale-app" ] || fail "HPA scaleTargetRef.name is '$REF_NAME', expected scale-app"

MIN=$(oc get hpa scale-app -n "$NS" -o jsonpath='{.spec.minReplicas}')
MAX=$(oc get hpa scale-app -n "$NS" -o jsonpath='{.spec.maxReplicas}')
[ "$MIN" = "3" ] || fail "HPA minReplicas is '$MIN', expected 3"
[ "$MAX" = "6" ] || fail "HPA maxReplicas is '$MAX', expected 6"

# autoscaling/v2 stores the target under metrics[]; autoscaling/v1 under
# targetCPUUtilizationPercentage. `oc autoscale` writes v2 on 4.x, but accept either so a
# hand-authored v1 manifest is not punished for being an older (still valid) API version.
TARGET=$(oc get hpa scale-app -n "$NS" -o jsonpath='{.spec.metrics[?(@.type=="Resource")].resource.target.averageUtilization}' 2>/dev/null)
[ -n "$TARGET" ] || TARGET=$(oc get hpa.v1.autoscaling scale-app -n "$NS" -o jsonpath='{.spec.targetCPUUtilizationPercentage}' 2>/dev/null)
[ "$TARGET" = "70" ] || fail "HPA CPU utilisation target is '$TARGET', expected 70"

pass "scale-app has a 50m CPU request, 3/3 ready, and an HPA targeting it (min 3, max 6, 70% CPU)"
