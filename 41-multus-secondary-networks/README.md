# 41 — Multus Secondary Networks (NAD / UDN / CUDN)

**Why this is on EX280:** 🔴🔴 confirmed as its own DO280 section, under the same objective
domain as "Expose non-HTTP/SNI Applications" (LoadBalancer Services, `33-expose-nonhttp/`).
Purely OpenShift/Multus-specific — attaching a pod to an **additional** network beyond the
default cluster pod network, for performance isolation, security segmentation, or connecting to
an existing network outside the cluster.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — the `bridge`-type NAD in section 1
works fully on single-node CRC: the pod came up with a genuine second interface (`net1`,
`10.99.0.2` from the NAD's subnet) confirmed via the `network-status` annotation. The one thing
CRC genuinely can't demonstrate is `host-device`/`macvlan` types that need a spare physical NIC
on the node — know that YAML shape and reasoning, but don't expect to test it hands-on here.
UDN/CUDN (sections 4-5) are documented but not independently re-verified in this pass.

## Concept

Kubernetes gives every pod exactly one network interface by default (the cluster pod network).
**Multus** is the CNI meta-plugin that lets a pod have *additional* interfaces, each governed
by its own network definition. As of recent OpenShift versions there are three ways to define
one:

| Mechanism | Who creates it | Scope |
|---|---|---|
| `NetworkAttachmentDefinition` (NAD) | anyone with namespace access | namespaced, most flexible (bridge/macvlan/ipvlan/host-device) |
| `UserDefinedNetwork` (UDN) | namespace user | namespaced, simpler config, can be the pod's **primary** interface |
| `ClusterUserDefinedNetwork` (CUDN) | cluster-admin only | spans multiple namespaces via a label selector |

## 1. Define a NetworkAttachmentDefinition (bridge type — works on a single node)

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: secondary-bridge
  namespace: myproj
spec:
  config: |-
    {
      "cniVersion": "0.3.1",
      "name": "secondary-bridge",
      "type": "bridge",
      "bridge": "second-net-br0",
      "isGateway": true,
      "ipam": {
        "type": "host-local",
        "subnet": "10.99.0.0/24"
      }
    }
```
```bash
oc apply -f nad-bridge.yaml
oc get network-attachment-definitions -n myproj
```

## 2. Attach a pod to it via annotation

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: multi-net-app, namespace: myproj }
spec:
  replicas: 1
  selector: { matchLabels: { app: multi-net-app } }
  template:
    metadata:
      labels: { app: multi-net-app }
      annotations:
        k8s.v1.cni.cncf.io/networks: secondary-bridge
    spec:
      containers:
      - name: main
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["sleep", "3600"]
```

## 3. Verify the second interface actually exists

```bash
oc get pod -l app=multi-net-app -n myproj \
  -o jsonpath='{.items[0].metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | head -c 500
oc exec deploy/multi-net-app -n myproj -- ls /sys/class/net   # ubi-minimal has no `ip` binary by default; this needs none
```
Look for a `net1` interface in addition to the default `eth0` — that's Multus's naming
convention for additional attached interfaces, and the `network-status` annotation confirms
which NAD provided it and what IP it got.

## 4. UserDefinedNetwork, if the task wants a simpler/primary-network setup

Requires the namespace to carry a specific label at creation time (cannot be added after the
fact):
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: udn-project
  labels:
    k8s.ovn.org/primary-user-defined-network: ""
```
```yaml
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata: { name: my-udn, namespace: udn-project }
spec:
  topology: Layer2
  layer2:
    role: Primary
    subnets: ["10.200.0.0/16"]
  ipam:
    lifecycle: Persistent
```
```bash
oc get userdefinednetwork my-udn -n udn-project -o yaml   # check status.conditions
```
**Important:** once the namespace carries that label, pods CANNOT schedule until the UDN itself
exists — order matters (namespace with label → UDN → then workloads), unlike a plain NAD which
has no such chicken-and-egg constraint.

## 5. ClusterUserDefinedNetwork (cluster-admin only, spans namespaces)

```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata: { name: shared-udn }
spec:
  namespaceSelector:
    matchLabels: { environment: development }
  network:
    topology: Layer2
    layer2:
      role: Primary
      subnets: ["10.201.0.0/16"]
    ipam:
      lifecycle: Persistent
```
Every namespace matching `environment: development` joins the same network — useful for
tenant-style isolation across several namespaces without repeating the config per-namespace.

## Common failure modes
- Forgetting the NAD is **namespaced** — a pod in a different namespace can't reference it by
  name even if it "looks the same."
- Labeling an EXISTING namespace with the UDN primary-network label expecting it to take effect
  — it doesn't; the label must be present at namespace **creation** time.
- Creating the UDN-labeled namespace but forgetting to actually create the `UserDefinedNetwork`
  resource inside it — every pod creation in that namespace fails until the UDN exists.
- Expecting a `host-device`/`macvlan` NAD to work in a constrained/single-node lab environment
  with no spare physical interface — that's an infrastructure limitation, not a config mistake;
  know the YAML shape and reasoning, but recognize when your lab genuinely can't demonstrate it.

## Verification checklist
- [ ] `oc get network-attachment-definitions -n myproj` shows the NAD
- [ ] The pod's `k8s.v1.cni.cncf.io/network-status` annotation lists the secondary network and an assigned IP
- [ ] `oc exec ... -- ls /sys/class/net` shows a `net1` (or higher) interface beyond the default `eth0`
- [ ] For UDN: `oc get userdefinednetwork -o yaml` shows `NetworkCreated`/`NetworkAllocationSucceeded` conditions as `True`

## Cleanup
```bash
oc delete deployment multi-net-app -n myproj
oc delete network-attachment-definition secondary-bridge -n myproj
```
