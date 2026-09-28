#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
need curl
need openssl
NS=ex280-t19
ns_exists "$NS" || fail "namespace $NS does not exist"

TERM=$(oc get route tls-app -n "$NS" -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
[ "$TERM" = "passthrough" ] || fail "route tls-app termination is '$TERM', expected 'passthrough'"

EXPECTED_HOST="tls-app.apps-crc.testing"
HOST=$(oc get route tls-app -n "$NS" -o jsonpath='{.spec.host}')
[ "$HOST" = "$EXPECTED_HOST" ] || fail "route tls-app host is '$HOST', expected exactly $EXPECTED_HOST"

BACKEND_SVC=$(oc get route tls-app -n "$NS" -o jsonpath='{.spec.to.name}')
SVC_PORT=$(oc get svc "$BACKEND_SVC" -n "$NS" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
[ "$SVC_PORT" = "8443" ] || fail "route tls-app's backing Service ($BACKEND_SVC) port is '$SVC_PORT', expected 8443"

# --resolve pins the hostname to the router: on macOS, crc provides no wildcard DNS for
# *.apps-crc.testing, so a plain curl would fail to resolve your route hostname even when the
# route is correct. A completed TLS handshake counts as success even with an untrusted cert (-k);
# retry while the router picks up a freshly created route.
RESOLVE=(--resolve "$HOST:443:127.0.0.1")
CODE=000
for _ in 1 2 3 4 5 6 7 8 9 10; do
  CODE=$(curl -sk "${RESOLVE[@]}" --max-time 10 -o /dev/null -w '%{http_code}' "https://$HOST" 2>/dev/null)
  CODE=${CODE:-000}
  [ "$CODE" != "000" ] && break
  sleep 3
done
[ "$CODE" != "000" ] || fail "TLS handshake to https://$HOST failed entirely (curl could not connect) after retrying for ~30s"

SUBJECT=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$HOST" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
echo "$SUBJECT" | grep -q "$EXPECTED_HOST" \
  || fail "certificate served for $HOST has subject '$SUBJECT' — expected CN=$EXPECTED_HOST from the pod itself. A wildcard (*.apps-crc.testing) subject means the router terminated TLS, so this is not really passthrough."

pass "passthrough route tls-app reachable (http_code=$CODE), backend's own cert presented ($SUBJECT)"
