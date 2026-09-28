# 31 — Kustomize

**Why this is on EX280:** 🔴🔴🔴 explicit objective ("work with resource manifests" domain).
Not OpenShift-specific technology (it's upstream `kubectl`/`oc` built-in), but it wasn't part
of a typical CKA/CKAD study track and is easy to under-practice.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## Concept

`kustomization.yaml` describes how to assemble/patch a set of plain manifests **without
templating** — a `base/` with the common resources, `overlays/<env>/` that reference the base
and apply patches/generators on top. `-k` (kustomize) vs `-f` (plain manifest) — do not mix
them up, `oc apply -f overlays/prod/` will just fail to find a single resource file.

## 1. Directory layout

```
kustomize-demo/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

`base/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
  selector: { matchLabels: { app: app } }
  template:
    metadata: { labels: { app: app } }
    spec:
      containers:
      - name: app
        image: quay.io/redhattraining/hello-world-nginx:latest
```
`base/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata: { name: app }
spec:
  selector: { app: app }
  ports: [{ port: 8080, targetPort: 8080 }]
```
`base/kustomization.yaml`:
```yaml
resources:
- deployment.yaml
- service.yaml
```

## 2. Overlay — patch + generator + image override

`overlays/prod/kustomization.yaml`:
```yaml
resources:
- ../../base
namePrefix: prod-
labels:
- pairs:
    env: prod
  includeSelectors: true
replicas:
- name: app
  count: 3
configMapGenerator:
- name: app-config
  literals:
  - LOG_LEVEL=info
images:
- name: quay.io/redhattraining/hello-world-nginx
  newTag: latest
patches:
- target:
    kind: Deployment
    name: app
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/env
      value:
      - name: ENVIRONMENT
        value: production
```

## 3. Render vs apply

```bash
oc kustomize overlays/prod/          # render only — inspect before applying, catch mistakes early
oc apply -k overlays/prod/           # actually apply
oc get all -l env=prod
```

## 4. Common patch types

- `replicas:` — cleaner than a JSON patch for just changing replica count.
- `patches:` with `target` + inline JSON6902 `patch:` — precise surgical edits.
- `patchesStrategicMerge` (older syntax, still seen) — a full/partial manifest merged in.
- `configMapGenerator`/`secretGenerator` — generates a ConfigMap/Secret with a content-hash
  suffix in its name, and **automatically rewrites references** to it elsewhere in the
  kustomization (e.g. in a Deployment's `envFrom`) — this auto-rewire is the "aha" feature to
  demonstrate if a task specifically asks for a generator.

## 5. Extra practice reps (worth drilling if you rarely touch Kustomize)

The `overlays/prod/` example above already showed one overlay doing several things at once.
Since this is a "use it rarely" skill, drill each mechanism **on its own** in a scratch
directory until you don't need to think about the syntax — muscle memory matters more here
than for things you already do daily.

**Rep 1 — generator auto-rewire.** Confirm you understand this isn't just "a ConfigMap with a
weird name" — the Deployment's `envFrom` reference gets rewritten to match automatically:
```yaml
# overlays/dev/kustomization.yaml
resources: [../../base]
namePrefix: dev-
configMapGenerator:
- name: app-config
  literals: ["LOG_LEVEL=debug"]
```
Render it and confirm BOTH the ConfigMap's hashed name (`dev-app-config-<hash>`) AND the
Deployment's `envFrom.configMapRef.name` show that exact same hashed name — that automatic
match-up is the entire point of using a generator instead of a plain ConfigMap resource.

**Rep 2 — JSON6902 patch adding a field that doesn't exist yet** (`env:` isn't present on the
base container at all):
```yaml
patches:
- target: { kind: Deployment, name: app }
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/env
      value:
      - name: ENVIRONMENT
        value: development
```
`op: add` on a path that doesn't exist yet creates it; `op: replace` would fail with an error
if the path is missing — know which one the situation calls for.

**Rep 3 — recognize (but don't default to) `patchesStrategicMerge`.** Older syntax, still
shows up in existing repos/exam prep material:
```yaml
patchesStrategicMerge:
- replica-patch.yaml
```
where `replica-patch.yaml` is a partial manifest (matching `apiVersion`/`kind`/`metadata.name`)
containing just the fields to override. Functionally equivalent to a `replicas:` transformer
for this specific case — but `patchesStrategicMerge` generalizes to arbitrary field merges,
where the dedicated `replicas:`/`images:` transformers only handle their one job. Current
kustomize emits a deprecation warning for it (prefer `patches:` for new work) but it still
works and you may see it on real clusters/exam docs examples.

Render all three together in one overlay and check the output makes sense as a whole — that
combination (generator + JSON6902 add + strategic-merge) is a realistic "everything at once"
shape for a real task.

## Common failure modes
- `oc apply -f overlays/prod/` instead of `-k` — wrong flag, silently does nothing useful (or
  errors depending on directory contents).
- Relative path in `resources: [../../base]` wrong after moving files around — `oc kustomize`
  fails fast with a clear path error; always render before applying to catch this.
- Expected a ConfigMap named exactly `app-config` after using `configMapGenerator` — the
  generated name has a hash suffix (`app-config-<hash>`); check with `oc get cm` rather than
  assuming the literal name from the generator block.

## Verification checklist
- [ ] `oc kustomize overlays/prod/` renders without error and shows the expected patches applied
- [ ] `oc apply -k overlays/prod/` creates resources named with the expected prefix/labels
- [ ] `oc get deploy prod-app -o jsonpath='{.spec.replicas}'` matches the overlay's `replicas:` override
- [ ] `oc get cm` shows the generated ConfigMap (hashed name) and the Deployment references it correctly

## Cleanup
```bash
oc delete -k overlays/prod/
```
