# 37 — Internal TLS: Service Serving Certificates

**Why this is on EX280:** 🔴🔴 confirmed as its own DO280 topic ("Protecting Internal Traffic
with TLS", distinct from the Routes/external-TLS chapter). Purely OpenShift-specific — nothing
like it exists in vanilla Kubernetes or in CKA/CKAD/CKS. Easy to miss because it's overshadowed
by the more famous Routes+TLS topic, but it's testing a genuinely different problem: encrypting
traffic **between two services inside the cluster**, not between a client and the router.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — full pod-to-pod HTTPS call
succeeded with no `-k`/insecure flag, using the auto-injected internal CA bundle.

## Concept

OpenShift runs an internal, cluster-managed CA (the **service-ca** operator). Any Service can
request a TLS certificate signed by that internal CA just by adding one annotation — no manual
`openssl`, no manually created Secret. The cert lands in a Secret you name, mounted into your
pod like any other Secret, and OpenShift **auto-rotates** it before expiry.

This solves a different problem than a Route: a Route's `edge`/`reencrypt` cert is presented to
**external clients**. A service serving certificate is for **pod-to-pod** traffic stayin
encrypted end-to-end inside the cluster (service mesh-adjacent goal, but far lighter-weight —
no Istio/OSSM required for the basic case).

## 1. Request a cert for a Service — one annotation

```yaml
apiVersion: v1
kind: Service
metadata:
  name: internal-tls-app
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: internal-tls-app-cert
spec:
  selector: { app: internal-tls-app }
  ports:
  - port: 8443
    targetPort: 8443
```
```bash
oc apply -f service.yaml
oc get secret internal-tls-app-cert -o yaml   # service-ca operator creates this automatically
```
The Secret appears within a few seconds, of type `kubernetes.io/tls`, containing `tls.crt` +
`tls.key` signed by the cluster's internal CA — **you never see or manage a key yourself**.

## 2. Mount it into the pod that needs to terminate TLS

```yaml
spec:
  template:
    spec:
      containers:
      - name: app
        volumeMounts:
        - { name: tls, mountPath: /etc/tls, readOnly: true }
      volumes:
      - name: tls
        secret:
          secretName: internal-tls-app-cert
```
Point your app's TLS config at `/etc/tls/tls.crt` and `/etc/tls/tls.key` (same idea as the
passthrough-route backend setup in `24-routes-tls/`, just now the CA is OpenShift's own instead
of self-signed).

## 3. Trusting the internal CA from the OTHER side (the calling pod)

Every namespace gets an auto-injected ConfigMap containing the internal CA bundle — request it
via annotation on the ConfigMap, same pattern as the Service annotation:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: trusted-ca-bundle
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
```
```bash
oc apply -f trusted-ca-cm.yaml
oc get configmap trusted-ca-bundle -o jsonpath='{.data.service-ca\.crt}' | head -3
```
Mount `trusted-ca-bundle` into the CALLING pod and point its HTTP client's CA trust store at
`service-ca.crt` from that ConfigMap — now it can validate the internal-tls-app's cert without
`-k`/insecure-skip-verify, because it trusts the cluster's own CA.

## 4. Functional test

```bash
oc exec deploy/caller -- curl --cacert /etc/pki/service-ca.crt \
  https://internal-tls-app.myproj.svc:8443
```
A successful (non `-k`) HTTPS call from one pod to another, both purely using OpenShift's
built-in CA machinery with zero manually generated certs, is the point being tested here.

## Common failure modes
- Expecting the Secret to be named after the Service — it's named whatever you put in
  `serving-cert-secret-name`, which does NOT have to match the Service name.
- Forgetting the annotation must be on the **Service**, not the Deployment/Pod — the service-ca
  operator watches Services, not workloads.
- Trying to curl with `-k` and calling it "done" — the actual point is trusting the internal CA
  properly (via the injected `trusted-ca-bundle` ConfigMap), not just skipping verification.
- Confusing this with Route TLS — a service serving certificate has **nothing to do with**
  external access; it never touches the router.

## Verification checklist
- [ ] `oc get secret <name>` (the one named in the annotation) exists, type `kubernetes.io/tls`
- [ ] `oc get configmap trusted-ca-bundle -o yaml` shows an injected `service-ca.crt` key
- [ ] A pod-to-pod HTTPS call succeeds WITHOUT `-k`/insecure flags, using the injected CA bundle
- [ ] Deleting and re-describing the Secret shows it gets recreated/rotated automatically over time

## Cleanup
```bash
oc delete secret internal-tls-app-cert
oc delete configmap trusted-ca-bundle
```
