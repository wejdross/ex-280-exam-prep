# 32 — OpenShift Templates + Helm

**Why this is on EX280:** 🔴🔴🔴 explicit objective ("deploy applications" domain names both).
Templates are OpenShift-native (pre-Helm parametrized YAML); Helm is the general Kubernetes
package manager, also fully supported via `oc`/`helm` CLI and the web console's Developer
catalog.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## Part A — OpenShift Templates

### 1. Browse built-in templates

```bash
oc get templates -n openshift
oc describe template <name> -n openshift    # shows PARAMETERS + what objects it creates
```

### 2. Author a simple template

```yaml
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: hello-template
  namespace: openshift          # or your project, for a project-local template
parameters:
- name: APP_NAME
  value: hello
  required: true
- name: REPLICAS
  value: "1"
objects:
- apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: ${APP_NAME}
  spec:
    replicas: ${{REPLICAS}}      # {{ }} = keep as integer, not string
    selector: { matchLabels: { app: ${APP_NAME} } }
    template:
      metadata: { labels: { app: ${APP_NAME} } }
      spec:
        containers:
        - name: app
          image: quay.io/redhattraining/hello-world-nginx:latest
```
```bash
oc create -f hello-template.yaml -n openshift    # add to the catalog
```

### 3. Process + apply

```bash
oc process -f hello-template.yaml -p APP_NAME=demo -p REPLICAS=2 | oc apply -f -
# or, since the pipe-to-file quoting can bite you with special chars, prefer process substitution:
oc apply -f <(oc process -f hello-template.yaml -p APP_NAME=demo -p REPLICAS=2)
# or straight from the catalog by name, no local file needed:
oc new-app --template=hello-template -p APP_NAME=demo -p REPLICAS=2
```

## Part B — Helm

### 1. Repo + search

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo nginx
```

### 2. Inspect before installing (know what you're about to get)

```bash
helm show values bitnami/nginx
helm show chart bitnami/nginx
```

### 3. Install / upgrade / rollback / uninstall

```bash
helm install my-nginx bitnami/nginx -n myproj --set service.type=ClusterIP
helm list -n myproj
helm status my-nginx -n myproj
helm upgrade my-nginx bitnami/nginx -n myproj --set replicaCount=2
helm rollback my-nginx 1 -n myproj
helm uninstall my-nginx -n myproj
```

### 4. Web console alternative (also a valid method on the exam)

Developer perspective → **+Add → Helm Chart** (or **Catalog**, filter by Helm) → fill in
values via form or YAML → Install. Functionally identical to the CLI path; use whichever is
faster for the specific task.

## Templates vs Helm — the distinction to state if asked
| | Template | Helm |
|---|---|---|
| Native to | OpenShift only | Kubernetes (any distro) |
| Packaging | single YAML, `${PARAM}` substitution | chart = directory tree, Go templating |
| Versioning/rollback | none built-in | `helm rollback` to any prior release revision |
| Where it lives | `Template` object in a namespace | a chart repo (local or remote) |

## Common failure modes
- Piped `oc process ... | oc apply -f -` where a parameter value contained a character the
  shell mangled — use process substitution `oc apply -f <(oc process ...)` instead.
- `${{REPLICAS}}` vs `${REPLICAS}` confusion — double-brace keeps the JSON/YAML type (integer),
  single-brace always substitutes as a string (fails on fields expecting `int`).
- Forgot `-n <namespace>` on `helm install` — chart lands in whatever namespace your kube
  context defaults to, not necessarily the project you meant.
- Didn't `helm repo update` after `helm repo add` — installs a stale/missing chart version.

## Verification checklist
- [ ] `oc get template hello-template -n openshift` exists with correct parameters
- [ ] `oc process ... | oc apply` / `oc new-app --template=` produces a Deployment with the parameterized name/replica count
- [ ] `helm list -n myproj` shows `STATUS: deployed` for the release
- [ ] `helm rollback` actually reverts the running resources (check `oc get deploy -o yaml` after)

## Cleanup
```bash
oc delete template hello-template -n openshift
oc delete -f <(oc process -f hello-template.yaml -p APP_NAME=demo)
helm uninstall my-nginx -n myproj
```
