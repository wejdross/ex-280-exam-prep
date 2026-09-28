# 25 — Operators (OLM / OperatorHub)

**Why this is on EX280:** 🔴🔴 installing an Operator via CLI/YAML (not just clicking through
the console) is a named objective. The moving parts — `PackageManifest`, `OperatorGroup`,
`Subscription`, `CSV`, `InstallPlan` — are OpenShift/OLM-specific vocabulary.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## Concept — the object chain

```
PackageManifest (what's available, read-only, from CatalogSource)
        │  you write a Subscription referencing it
        ▼
Subscription  ──creates──▶  InstallPlan  ──approved──▶  CSV (ClusterServiceVersion = "installed operator")
        ▲
OperatorGroup (declares which namespace(s) the operator watches — required for namespaced operators)
```

## 1. Find the operator

```bash
oc get packagemanifests -n openshift-marketplace | grep -i <keyword>
oc describe packagemanifest <name> -n openshift-marketplace   # shows available channels
```
Console alternative: **OperatorHub** in the Administrator perspective — often faster to browse,
still counts as a valid install method.

## 2. Create (or reuse) the namespace + OperatorGroup

```bash
oc new-project my-operator-proj
```
```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: my-og
  namespace: my-operator-proj
spec:
  targetNamespaces:
  - my-operator-proj
```
Skip this if the operator is **cluster-wide** (installs into `openshift-operators`, which
already has a global OperatorGroup) — check the packagemanifest's install modes first.

## 3. Subscription

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-operator
  namespace: my-operator-proj
spec:
  channel: stable
  name: <package-name-from-packagemanifest>
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```
```bash
oc apply -f operatorgroup.yaml -f subscription.yaml
```

## 4. Watch it install

```bash
oc get installplan -n my-operator-proj
oc get csv -n my-operator-proj -w        # PHASE should reach "Succeeded"
oc get subscription -n my-operator-proj -o yaml | grep -A5 status
```

## 5. Manual approval (if `installPlanApproval: Manual`)

```bash
oc get installplan -n my-operator-proj
oc patch installplan <ip-name> -n my-operator-proj --type merge -p '{"spec":{"approved":true}}'
```

## Common failure modes
- Missing/wrong `OperatorGroup` for a namespaced operator → Subscription stalls, CSV never
  appears (check `oc describe subscription` events).
- Wrong `sourceNamespace` (almost always `openshift-marketplace` — don't guess).
- Picked the wrong `channel` (task usually specifies one — installing `stable` when the task
  wants `alpha`/a specific version channel silently gets you the wrong operator version).
- Forgot to check `installPlanApproval` — if it's `Manual` and you don't approve the
  InstallPlan, the CSV never installs and it looks "stuck" for no obvious reason.

## Verification checklist
- [ ] `oc get csv -n my-operator-proj` shows `PHASE: Succeeded`
- [ ] `oc get pods -n my-operator-proj` shows the operator's own pod(s) Running
- [ ] Whatever CRD the operator provides is now available: `oc get crd | grep <operator>`
- [ ] If task asked for a specific channel/version, confirm via `oc get subscription -o yaml`

## Cleanup
```bash
oc delete subscription my-operator -n my-operator-proj
oc delete csv -n my-operator-proj --all
oc delete operatorgroup my-og -n my-operator-proj
oc delete project my-operator-proj
```
