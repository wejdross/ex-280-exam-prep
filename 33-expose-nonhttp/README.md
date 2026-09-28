# 33 — Exposing non-HTTP / SNI applications

**Why this is on EX280:** 🔴🔴🔴 its own named objective domain — Routes (HAProxy) only speak
HTTP/HTTPS/TLS-with-SNI. Anything else (raw TCP database protocol, UDP, a custom binary
protocol) cannot go through a Route at all — the exam wants you to recognize this and reach
for a `LoadBalancer` or `NodePort` Service instead.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — the NodePort path was proven
end-to-end (raw TCP client connected through the node's NodePort from outside the pod network)
via the final-exam tasks. As expected, CRC has no cloud LB provider — a `LoadBalancer` Service
sits with `EXTERNAL-IP: <pending>` forever unless MetalLB or similar is installed; on CRC, treat
the `LoadBalancer` YAML/command as "know it, understand it needs a provider" rather than
something you can watch resolve to a real IP here.

## Recognizing the trap in a task's wording
- "Expose the app over HTTP" → **Route** (see `24-routes-tls/`).
- "Expose the database on port 5432" / "raw TCP" / "clients connect directly, not via HTTP" →
  **Service type LoadBalancer or NodePort — NOT a Route.**

## 1. LoadBalancer Service

```bash
oc create service loadbalancer app-db --tcp=5432:5432
# or convert an existing ClusterIP service:
oc patch svc/app-db -p '{"spec":{"type":"LoadBalancer"}}'
oc get svc app-db          # EXTERNAL-IP: <pending> on CRC/bare-metal without MetalLB — expected
```
Declarative:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-db
spec:
  type: LoadBalancer
  selector: { app: app-db }
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
```

## 2. NodePort Service (works everywhere, no cloud provider needed)

```bash
oc create service nodeport app-db --tcp=5432:5432
oc get svc app-db -o jsonpath='{.spec.ports[0].nodePort}{"\n"}'
```
Functional test — reach it from outside the cluster network via any node's IP:
```bash
NODE_IP=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(oc get svc app-db -o jsonpath='{.spec.ports[0].nodePort}')
nc -zv $NODE_IP $NODE_PORT   # or a protocol-appropriate client
```

## 3. Ingress with SNI passthrough (rarer, but same underlying idea as a passthrough Route)

For TLS-based non-HTTP protocols that still carry SNI, a passthrough `Route` may still be
usable — the distinguishing factor is SNI presence, not "is it HTTP". No-SNI raw TCP/UDP is
where Route is fundamentally the wrong primitive, no workaround.

## Common failure modes
- Tried `oc expose service/app-db` (always creates a **Route**, HTTP-shaped) for a database
  port — the Route gets created but is functionally useless for a raw TCP client.
- Expected `LoadBalancer` `EXTERNAL-IP` to populate on a bare/CRC cluster with no LB provider —
  don't burn exam time waiting on this; the real exam infra almost certainly has one, know the
  command and move on if the practice cluster can't demonstrate the pending→ready transition.
- Forgot `--tcp=<port>:<targetPort>` syntax — first number is the Service port, second is the
  pod's container port; mixing them up still "works" but only by accident if they match.

## Verification checklist
- [ ] `oc get svc app-db -o jsonpath='{.spec.type}'` → `LoadBalancer` or `NodePort` as required
- [ ] For NodePort: a raw TCP client from outside the pod network reaches the app via `<node-ip>:<nodeport>`
- [ ] `oc describe svc app-db` shows correct selector matching the backing pod's labels
- [ ] No `Route` object was created for this — confirm with `oc get route | grep app-db` (expect nothing)

## Cleanup
```bash
oc delete svc app-db
```
