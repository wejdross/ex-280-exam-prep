# 38 — NetworkPolicy (OpenShift-specific nuances)

**Why this is on EX280:** the `NetworkPolicy` object itself is pure Kubernetes (you know it
from CKA/CKAD) — but it's explicitly named as its own DO280 section ("Configuring Network
Policies"), and OpenShift's default network plugin (OVN-Kubernetes) has a couple of
behaviors/defaults worth knowing that don't apply the same way on every Kubernetes distro.

**Status:** ✅ verified on a live CRC cluster (2026-07-17), including a real surprise: the
Routes-vs-deny-all behavior in section 3 was tested live and corrected from what older material
claims. Also exercised via `final-exam/tasks/08.md`.

## 0. The one thing that's different from "generic Kubernetes knowledge"

By default, **all pods in a project can talk to all other pods in that project** (and, on
older OpenShift multitenant-plugin setups, sometimes across projects too) — there is no
default-deny. If a task says "isolate this project" or "deny all traffic except X", you must
add an explicit **default-deny** NetworkPolicy yourself; it does not exist out of the box.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}        # empty selector = applies to every pod in the namespace
  policyTypes: ["Ingress"]
  # no ingress rules = nothing is allowed in
```

## 1. Allow specific traffic (additive on top of a deny-all)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels: { app: backend }
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - podSelector:
        matchLabels: { app: frontend }
    ports:
    - protocol: TCP
      port: 8080
```
NetworkPolicies are **additive** — multiple policies selecting the same pod combine with OR
logic on the allow side. You don't need one giant policy; several small, single-purpose
policies are easier to reason about and match how tasks are usually worded ("allow X to reach
Y" as one requirement, "block Z" as another).

## 2. Allow traffic from another namespace

```yaml
spec:
  podSelector:
    matchLabels: { app: backend }
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: other-project
      podSelector:
        matchLabels: { app: caller }
```
`namespaceSelector` + `podSelector` **together in the same `from` entry** = "pods matching this
label, in namespaces matching that label" (AND). Listed as two separate entries in the `from`
list = OR ("either this pod selector anywhere, or any pod in that namespace") — this is one of
the most common NetworkPolicy authoring mistakes, and worth being deliberate about.

## 3. Routes vs a deny-all NetworkPolicy — verified, and it's not what older guidance says

**Verified on this cluster (OVN-Kubernetes, the current default network plugin):** applying a
bare `deny-all` ingress NetworkPolicy on a project **did not** break an existing Route to a pod
in that project — the router still reached the backend and served `200` throughout, while a
plain pod-to-pod call from another pod in the same namespace was correctly blocked by the same
policy. Checking `oc get pods -n openshift-ingress -o wide` explains why: the router pod runs
with **host networking**, on the node's own IP, not a pod-network IP — so its traffic to
backend pods isn't going through the same pod-to-pod path standard `NetworkPolicy` ingress
rules match against the same way peer-pod traffic does.

Older material (and older OpenShift-SDN-plugin clusters) says you must add an explicit
namespaceSelector allow for `openshift-ingress` to keep a Route working after a deny-all — that
was true for the legacy `openshift-sdn` plugin. On a modern OVN-Kubernetes cluster, don't
assume a deny-all silently breaks your Routes; **test it** rather than pre-emptively adding an
`openshift-ingress` allow rule "just in case" — if the task's actual requirement is "block
external Route access too," a namespaced `NetworkPolicy` alone is not the right tool for that
on OVN-Kubernetes (look at `AdminNetworkPolicy`/`EgressFirewall`-adjacent cluster-level controls
instead, or restrict at the Route/Ingress Controller level).

## 4. Egress policies (less common on the exam, know the shape)

```yaml
spec:
  podSelector:
    matchLabels: { app: backend }
  policyTypes: ["Egress"]
  egress:
  - to:
    - podSelector:
        matchLabels: { app: database }
    ports:
    - protocol: TCP
      port: 5432
  - to:            # allow DNS — almost always needed alongside any egress restriction
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
```
Forgetting the DNS-egress rule after adding an egress deny-all is the #1 "my app can't resolve
anything now" trap — DNS traffic needs its own explicit allow if you restrict egress at all.

## Common failure modes
- Assumed pods were isolated by default — they aren't; deny-all must be explicit.
- Put `namespaceSelector` and `podSelector` in separate `from:` list entries when the intent was
  AND (both must be true), producing an accidentally broader OR rule.
- Assumed (from older openshift-sdn-era material) that deny-all breaks Routes unless you
  explicitly allow `openshift-ingress` — verified false on current OVN-Kubernetes; don't add
  that rule reflexively, test the actual behavior on your cluster instead.
- Restricted egress without an explicit DNS-egress allow — everything downstream that depends
  on name resolution breaks.

## Verification checklist
- [ ] With deny-all applied, an unrelated pod (no matching allow rule) genuinely cannot connect
- [ ] The specifically-allowed pod/namespace CAN connect on the specified port
- [ ] If fronted by a Route, external access through the Route still works after policies are applied
- [ ] `oc describe networkpolicy <name>` shows the exact selectors/ports you intended

## Cleanup
```bash
oc delete networkpolicy --all
```
