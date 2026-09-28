#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
NS=ex280-t07
ns_exists "$NS" || fail "namespace $NS does not exist"

PHASE=$(oc get pod raw-tcp -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$PHASE" = "Running" ] || fail "pod raw-tcp is not Running (phase: $PHASE)"

oc get svc raw-tcp -n "$NS" >/dev/null 2>&1 \
  || fail "Service raw-tcp not found in $NS (found: $(oc get svc -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}={.spec.type}{" "}{end}'))"

TYPE=$(oc get svc raw-tcp -n "$NS" -o jsonpath='{.spec.type}')
[ "$TYPE" = "NodePort" ] || fail "Service raw-tcp is of type '$TYPE', expected NodePort"

PORT=$(oc get svc raw-tcp -n "$NS" -o jsonpath='{.spec.ports[?(@.port==9000)].port}')
[ "$PORT" = "9000" ] || fail "Service raw-tcp has no port 9000 entry"

NODEPORT=$(oc get svc raw-tcp -n "$NS" -o jsonpath='{.spec.ports[?(@.port==9000)].nodePort}')
[ "$NODEPORT" = "30900" ] || fail "Service raw-tcp nodePort is '$NODEPORT', expected 30900"

ENDPOINTS=$(oc get endpoints raw-tcp -n "$NS" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
[ -n "$ENDPOINTS" ] || fail "Service raw-tcp has no endpoints — its selector does not match the raw-tcp pod's labels (pod needs app=raw-tcp)"

# Functional test from INSIDE the cluster: on macOS, crc does not forward node ports to the
# host, so a host-side connect would fail even for a correct answer. The raw-tcp pod itself has
# python3, so use it as the TCP client against the node's own IP:nodePort.
NODEIP=$(oc get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
[ -n "$NODEIP" ] || fail "could not determine the node's InternalIP"

ECHOED=$(oc exec -n "$NS" raw-tcp -- python3 -c "
import socket
s = socket.create_connection(('$NODEIP', 30900), 10)
s.sendall(b'grade07\n')
print(s.recv(64).decode().strip())" 2>/dev/null)
[ "$ECHOED" = "grade07" ] \
  || fail "raw TCP round-trip to $NODEIP:30900 failed (got '$ECHOED', expected 'grade07') — the NodePort does not reach a working echo listener"

pass "raw-tcp pod Running, NodePort Service raw-tcp 9000:30900, raw TCP echo through $NODEIP:30900 verified"
