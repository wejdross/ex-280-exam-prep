# 42 — ConfigMaps and Secrets

**Why this is on EX280:** 🔴🔴 two separate lines in the official objectives, both under
"Manage Storage for Application Configuration and Data": *"Create and use secrets"* and
*"Create and use configuration maps"*. Also appears under Configure Application Security
(*"Create and apply secrets to manage sensitive information"*). This is the most certain topic
in the whole exam and the easiest to under-practise, because everyone assumes they know it.

**Status:** ✅ verified on a live CRC cluster (2026-09-21) — both the `oc` path and the YAML
path drive `final-exam` task 21 to a PASS.

## Concept

A ConfigMap and a Secret are the same shape — a map of key → value — with three differences:

| | ConfigMap | Secret |
|---|---|---|
| Storage | plaintext in etcd | base64 in the API, encrypted at rest if the cluster is configured for it |
| `oc get -o yaml` | shows `data:` readable | shows `data:` base64-encoded |
| Typed variants | none | `generic`, `docker-registry`, `tls` |

Both are consumed by a pod in exactly two ways: **as environment variables** or **as files in
a mounted volume**. Knowing which one a task wants is most of the work.

## 1. Creating them

```bash
# literals
oc create configmap app-config --from-literal=APP_MODE=production --from-literal=APP_TIER=gold
oc create secret generic app-secret --from-literal=API_KEY=s3cr3t

# from a file — the KEY becomes the FILENAME
oc create configmap app-files --from-file=app.properties
oc create configmap app-files --from-file=custom-key=app.properties   # override the key

# from a whole directory — one key per file
oc create configmap app-files --from-file=./confdir/

# from an env-style file (KEY=VALUE per line) — one key per LINE, not one key for the file
oc create configmap app-config --from-env-file=app.env
```

`--from-file` vs `--from-env-file` is the classic trap. `--from-file=app.env` gives you **one**
key called `app.env` whose value is the whole file. `--from-env-file=app.env` gives you **one
key per line**. Tasks that say "the ConfigMap must have a key `app.properties`" want
`--from-file`.

The two other Secret types:

```bash
oc create secret docker-registry pullsecret \
  --docker-server=quay.io --docker-username=u --docker-password=p --docker-email=e@x.com

oc create secret tls my-tls --cert=tls.crt --key=tls.key
```

## 2. Consuming as environment variables

```bash
# ALL keys of a ConfigMap / Secret, each becoming an env var of the same name
oc set env deployment/myapp --from=configmap/app-config
oc set env deployment/myapp --from=secret/app-secret

# one specific key, renamed
oc set env deployment/myapp --from=secret/app-secret --keys=API_KEY

# prefix every injected name
oc set env deployment/myapp --from=configmap/app-config --prefix=CONF_

# list what a workload currently has
oc set env deployment/myapp --list
```

**Know this difference, it bites people:** `oc set env --from=configmap/x` does **not** write
an `envFrom:` block. It expands into one `env:` entry per key, each with a
`valueFrom.configMapKeyRef`. Both are correct and both work — but if you write the YAML by
hand you'll probably use `envFrom`, and if you then `oc get -o yaml` a deployment you built
with `oc set env`, it will look different. Verified on 4.22:

```yaml
# what `oc set env --from=configmap/app-config` actually produces
env:
- name: APP_MODE
  valueFrom:
    configMapKeyRef: {name: app-config, key: APP_MODE}
- name: APP_TIER
  valueFrom:
    configMapKeyRef: {name: app-config, key: APP_TIER}
```
```yaml
# what you would hand-write — equivalent behaviour
envFrom:
- configMapRef:
    name: app-config
- secretRef:
    name: app-secret
```

The practical consequence: `envFrom` picks up **new keys added later** on the next rollout;
the expanded form only has the keys that existed when you ran the command.

## 3. Consuming as files

```bash
oc set volume deployment/myapp --add \
  -t configmap --configmap-name=app-files \
  --mount-path=/etc/appconfig --name=appconfig

oc set volume deployment/myapp --add \
  -t secret --secret-name=app-secret \
  --mount-path=/etc/appsecret --name=appsecret --read-only=true

oc set volume deployment/myapp --list
oc set volume deployment/myapp --remove --name=appconfig
```

Every key becomes a file under the mount path. Hand-written equivalent:

```yaml
    volumeMounts:
    - name: appconfig
      mountPath: /etc/appconfig
  volumes:
  - name: appconfig
    configMap:
      name: app-files
      # optional: mount only some keys, and/or rename them
      items:
      - key: app.properties
        path: application.properties
```

Mounting a ConfigMap **replaces** the whole directory at `mountPath`. To drop a single file
into an existing directory without hiding its other contents, use `subPath`:

```yaml
    volumeMounts:
    - name: appconfig
      mountPath: /etc/nginx/nginx.conf
      subPath: nginx.conf
```

A `subPath` mount does **not** receive updates when the ConfigMap changes; a normal volume
mount does (eventually, via kubelet sync). Env vars never update without a restart.

## 4. Changing a ConfigMap already in use

```bash
oc set data configmap/app-config --from-literal=APP_TIER=platinum   # 4.x convenience verb
oc edit configmap app-config
oc rollout restart deployment/myapp     # env vars and subPath mounts need this
```

## 5. Making one immutable

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
immutable: true
data:
  APP_MODE: production
```

Immutable ConfigMaps/Secrets cannot be updated, only deleted and recreated. It protects
against accidental change and reduces apiserver watch load.

## Common failure modes

- Using `--from-env-file` when the task wants a file-shaped key (or the reverse).
- Injecting the value as a literal (`--from-literal` straight onto the deployment with
  `oc set env MYVAR=...`) instead of referencing the ConfigMap/Secret. A grader that checks
  for `configMapKeyRef`/`envFrom` will fail you even though the pod has the right value.
- Mounting a ConfigMap over a directory that the image needs (`/etc`, `/etc/nginx`) and
  wondering why the container crash-loops — use `subPath`.
- Expecting env vars to update when the ConfigMap changes. They never do.
- Forgetting `-n <project>` and creating the ConfigMap in the wrong namespace — a ConfigMap is
  namespaced and a pod can only reference one in its **own** namespace.
- Base64-encoding a value by hand into `data:` when you meant `stringData:` (which takes
  plaintext and encodes for you).

## Verification checklist

```bash
oc get configmap app-config -o yaml
oc get secret app-secret -o jsonpath='{.data.API_KEY}' | base64 -d; echo
oc set env deployment/myapp --list
oc set volume deployment/myapp --list
# the only check that really counts:
oc exec deploy/myapp -- printenv APP_MODE
oc exec deploy/myapp -- cat /etc/appconfig/app.properties
```

## Cleanup

```bash
oc delete configmap app-config app-files
oc delete secret app-secret
```
