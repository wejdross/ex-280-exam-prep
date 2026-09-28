#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
need curl
need openssl
NS=ex280-t06
ns_exists "$NS" || fail "namespace $NS does not exist"

TERM=$(oc get route edge-app -n "$NS" -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
[ "$TERM" = "edge" ] || fail "route edge-app termination is '$TERM', expected 'edge'"

EXPECTED_HOST="edge-app.apps-crc.testing"
HOST=$(oc get route edge-app -n "$NS" -o jsonpath='{.spec.host}')
[ "$HOST" = "$EXPECTED_HOST" ] || fail "route edge-app host is '$HOST', expected exactly $EXPECTED_HOST"

POLICY=$(oc get route edge-app -n "$NS" -o jsonpath='{.spec.tls.insecureEdgeTerminationPolicy}')
[ "$POLICY" = "Redirect" ] || fail "route edge-app insecureEdgeTerminationPolicy is '$POLICY', expected 'Redirect'"

CERT=$(oc get route edge-app -n "$NS" -o jsonpath='{.spec.tls.certificate}')
[ -n "$CERT" ] || fail "route edge-app has no custom certificate set (spec.tls.certificate is empty) — task requires a self-signed cert you generate yourself, not the router's default wildcard cert"

# --resolve pins the hostname to the router without relying on name resolution: on macOS, crc
# provides NO wildcard DNS for *.apps-crc.testing (only the handful of hostnames it writes into
# /etc/hosts), so a plain curl to your own route hostname fails with "Could not resolve host"
# even when the route is perfectly configured. Add it to /etc/hosts if you want to test by hand.
RESOLVE=(--resolve "$HOST:443:127.0.0.1" --resolve "$HOST:80:127.0.0.1")

# The router also needs a few seconds to pick up a freshly created/changed route; a single-shot
# curl right after applying it returns 503 and would false-fail a correct solution.
CODE=000
for _ in 1 2 3 4 5 6 7 8 9 10; do
  CODE=$(curl -sk "${RESOLVE[@]}" -o /dev/null -w '%{http_code}' --max-time 10 "https://$HOST" 2>/dev/null)
  CODE=${CODE:-000}
  [[ "$CODE" =~ ^(2|3) ]] && break
  sleep 3
done
[[ "$CODE" =~ ^(2|3) ]] || fail "https://$HOST returned HTTP $CODE (expected 2xx/3xx) after retrying for ~30s"

SUBJECT=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$HOST" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
echo "$SUBJECT" | grep -q "$EXPECTED_HOST" \
  || fail "certificate served for $HOST has subject '$SUBJECT' — expected CN=$EXPECTED_HOST. A wildcard (*.apps-crc.testing) subject means the router's default cert is being served, not the one you generated."

HTTP_CODE=000
for _ in 1 2 3 4 5 6 7 8 9 10; do
  HTTP_CODE=$(curl -s "${RESOLVE[@]}" -o /dev/null -w '%{http_code}' --max-time 10 "http://$HOST" 2>/dev/null)
  HTTP_CODE=${HTTP_CODE:-000}
  [[ "$HTTP_CODE" =~ ^3 ]] && break
  sleep 3
done
[[ "$HTTP_CODE" =~ ^3 ]] || fail "plain http://$HOST returned HTTP $HTTP_CODE, expected a 3xx redirect (insecureEdgeTerminationPolicy: Redirect)"

pass "edge route $HOST: edge termination with your own cert ($SUBJECT), HTTPS $CODE, HTTP $HTTP_CODE redirect"
