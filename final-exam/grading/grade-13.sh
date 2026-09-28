#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t13
ns_exists "$NS" || fail "namespace $NS does not exist"

oc get template t13-template -n "$NS" >/dev/null 2>&1 || fail "Template t13-template not found in $NS"

REQUIRED=$(oc get template t13-template -n "$NS" -o jsonpath='{.parameters[?(@.name=="APP_NAME")].required}')
[ "$REQUIRED" = "true" ] || fail "parameter APP_NAME is not marked required"

REPLICAS_DEFAULT=$(oc get template t13-template -n "$NS" -o jsonpath='{.parameters[?(@.name=="REPLICAS")].value}')
[ "$REPLICAS_DEFAULT" = "1" ] || fail "parameter REPLICAS default is '$REPLICAS_DEFAULT', expected 1"

oc get deployment fromtemplate -n "$NS" >/dev/null 2>&1 || fail "Deployment fromtemplate not found — did you process+apply with APP_NAME=fromtemplate?"
REPLICAS=$(oc get deployment fromtemplate -n "$NS" -o jsonpath='{.spec.replicas}')
[ "$REPLICAS" = "2" ] || fail "expected 2 replicas (REPLICAS=2 was requested), got $REPLICAS"

IMAGE=$(oc get deployment fromtemplate -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')
[ "$IMAGE" = "quay.io/redhattraining/hello-world-nginx:latest" ] || fail "fromtemplate image is '$IMAGE', expected quay.io/redhattraining/hello-world-nginx:latest as defined in the template"

pass "template t13-template correctly parameterized, processed into fromtemplate with 2 replicas"
