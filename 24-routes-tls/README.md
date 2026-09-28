# 24 — Routes + TLS (edge / passthrough / reencrypt)

**Why this is on EX280:** 🔴🔴🔴 the single most commonly cited "I failed because of this"
topic. Routes are OpenShift's HTTP(S)/SNI ingress (no Ingress-object-only workflow here — the
native primitive is `Route`, backed by the HAProxy router). Three TLS termination modes, each
with different certificate requirements — mixing them up is the #1 killer.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## The three modes, in one sentence each

| Mode | TLS ends at | Router needs a cert? | Backend must speak TLS? |
|---|---|---|---|
| **edge** | the router | yes (server cert+key) | no — plain HTTP to the pod |
| **passthrough** | the pod | no | yes — pod does its own TLS end-to-end |
| **reencrypt** | router, then re-encrypted to pod | yes (server cert+key) + dest CA | yes — but router doesn't need to trust a public CA, just the one you give it |

Rule of thumb for reading a task: *"terminate TLS at the edge"* → edge. *"the application
must handle its own certificate"* / *"end-to-end encryption"* → passthrough. *"re-encrypt to
the backend"* / *"backend already has TLS, router still needs its own public cert"* → reencrypt.

## 0. Generate a throwaway self-signed cert (exam gives you real ones — this is just for practice)

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=hello-edge.apps-crc.testing" \
  -addext "subjectAltName=DNS:hello-edge.apps-crc.testing"
```

## 1. Plain HTTP route (baseline, no TLS)

```bash
oc expose service/hello
oc get route hello
```

## 2. Edge route

```bash
oc create route edge hello-edge --service=hello \
  --cert=tls.crt --key=tls.key \
  --hostname=hello-edge.apps-crc.testing
curl -sk https://hello-edge.apps-crc.testing
```
Equivalent declarative form (prefer this on the exam — survives reboot, reviewable):
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: hello-edge
spec:
  host: hello-edge.apps-crc.testing
  to: { kind: Service, name: hello }
  tls:
    termination: edge
    certificate: |
      <contents of tls.crt>
    key: |
      <contents of tls.key>
```

## 3. Passthrough route

Requires the **pod itself** to terminate TLS on the port the Service points at — the route
just carries the encrypted bytes through based on SNI hostname, so `--cert/--key` are NOT
passed to `oc create route` here (there's nothing for the router to decrypt). `--service`
requires the named Service to **already exist** — `oc create route` looks it up to find the
target port, it isn't just a label on the Route object. `hello-tls` below is a TLS-terminating
backend built for this section specifically (the plain `hello` Service from earlier sections is
HTTP-only and can't back a passthrough/reencrypt route).

Build the TLS backend — a stock `nginx` image configured to terminate TLS on 8443 itself:
```bash
oc create secret tls hello-tls-secret --cert=tls.crt --key=tls.key
```
```yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: hello-tls-conf }
data:
  nginx.conf: |
    events {}
    http {
      server {
        listen 8443 ssl;
        ssl_certificate /etc/tls/tls.crt;
        ssl_certificate_key /etc/tls/tls.key;
        location / { return 200 'hello-tls ok'; }
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: hello-tls }
spec:
  replicas: 1
  selector: { matchLabels: { app: hello-tls } }
  template:
    metadata: { labels: { app: hello-tls } }
    spec:
      containers:
      - name: main
        image: docker.io/library/nginx:latest
        ports: [{ containerPort: 8443 }]
        volumeMounts:
        - { name: conf, mountPath: /etc/nginx/nginx.conf, subPath: nginx.conf }
        - { name: tls, mountPath: /etc/tls, readOnly: true }
        - { name: cache, mountPath: /var/cache/nginx }   # restricted-v2 SCC blocks nginx's
        - { name: run, mountPath: /var/run }              # default cache/pid dirs otherwise
      volumes:
      - name: conf
        configMap: { name: hello-tls-conf }
      - name: tls
        secret: { secretName: hello-tls-secret }
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata: { name: hello-tls }
spec:
  selector: { app: hello-tls }
  ports: [{ port: 8443, targetPort: 8443 }]
```
```bash
oc apply -f hello-tls.yaml
```
Now the passthrough route can actually target it:
```bash
oc create route passthrough hello-pt --service=hello-tls --hostname=hello-pt.apps-crc.testing
curl -sk https://hello-pt.apps-crc.testing   # TLS handshake terminates at the pod, not the router
```

## 4. Reencrypt route

Reuses the same `hello-tls` backend from section 3 — reencrypt just adds a second,
router-facing cert on top of a backend that already does its own TLS:
```bash
oc create route reencrypt hello-re --service=hello-tls \
  --cert=tls.crt --key=tls.key --dest-ca-cert=tls.crt \
  --hostname=hello-re.apps-crc.testing
curl -sk https://hello-re.apps-crc.testing
```
`--dest-ca-cert` = the CA that signed the **backend's** cert, so the router can validate it
when re-encrypting. Since `hello-tls` is using a self-signed cert, that same cert file (`tls.crt`)
doubles as its own "CA" here — hand the router the backend's actual cert file for
`--dest-ca-cert`, not a separately-generated one.

## 5. Other route flags worth knowing

```bash
oc create route edge hello-edge --service=hello --hostname=... \
  --insecure-policy=Redirect          # http auto-redirects to https
oc annotate route hello-edge haproxy.router.openshift.io/balance=roundrobin
oc patch route hello-edge -p '{"spec":{"wildcardPolicy":"Subdomain"}}'
```

## Common failure modes
- Passed `--cert`/`--key` to a **passthrough** route (invalid — passthrough takes no cert flags).
- Forgot `--dest-ca-cert` on **reencrypt** (route created, but backend TLS verification fails).
- Hostname doesn't match the `CN`/SAN in the cert → browser/curl TLS error even though the
  route "exists" — always `curl -k` first to isolate route-plumbing from cert-content issues,
  then re-check without `-k`.
- Used `oc expose` (always plain HTTP) when the task wanted TLS from the start, then tried to
  "upgrade" it by editing instead of `oc create route`/patching `spec.tls` properly.
- Forgot that on the real exam, the routes subdomain is `apps.<cluster-domain>`, not
  `apps-crc.testing` — always confirm with `oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'`.

## Verification checklist
- [ ] `oc get route <name> -o wide` shows the right `TERMINATION` column (edge/passthrough/reencrypt)
- [ ] `curl -sk https://<host>` returns expected response for edge/reencrypt
- [ ] For reencrypt: `curl -sk` succeeds AND removing `-k`/trusting the CA also succeeds (cert chain is genuinely valid, not just "route exists")
- [ ] `oc describe route <name>` shows no `Rejected` conditions at the bottom

## Cleanup
```bash
oc delete route hello hello-edge hello-pt hello-re
oc delete deployment,service,configmap hello-tls
oc delete secret hello-tls-secret
rm -f tls.key tls.crt
```
