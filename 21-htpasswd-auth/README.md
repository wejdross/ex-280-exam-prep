# 21 — HTPasswd Identity Provider

**Why this is on EX280:** 🔴🔴🔴 the #1 "pure OpenShift" topic — nothing like it exists in
CKA/CKAD/CKS. You almost certainly need this early in the exam because later tasks ("as user
alice, deploy...") depend on alice being able to log in at all.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## Concept

OpenShift auth = **OAuth server** (built into the control plane) + one or more **Identity
Providers** (IdP) configured on the cluster-scoped `OAuth` resource named `cluster`. HTPasswd
is the simplest IdP: a flat file of `user:bcrypt-hash` lines, stored as a `Secret` in
`openshift-config`, referenced from `oauth/cluster`.

Flow: **htpasswd file → Secret (openshift-config) → identityProvider entry on `oauth/cluster`**.

## 1. Create the htpasswd file

```bash
# -c creates the file — ONLY for the very first user, never again (overwrites!)
htpasswd -c -B -b users.htpasswd alice redhatB1
# every subsequent user: no -c
htpasswd -B -b users.htpasswd bob redhatB1
cat users.htpasswd        # sanity check: two lines, bcrypt hashes ($2y$...)
```
`-B` = bcrypt (required — OpenShift rejects weaker hash schemes). `-b` = password on the
command line (non-interactive, scriptable).

## 2. Create the Secret in `openshift-config`

```bash
oc create secret generic htpasswd-secret \
  --from-file=htpasswd=users.htpasswd \
  -n openshift-config
```
The key inside the secret **must be named `htpasswd`** — that's what the OAuth CR's
`fileData.name` references (the secret name is your choice; the *key* name is not).

## 3. Wire it into `oauth/cluster`

Declarative — don't `oc edit` blind, patch/apply so it survives review & reboot:

```bash
oc get oauth cluster -o yaml > oauth-cluster.yaml   # inspect first — don't clobber other IdPs
```

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd-secret
```

```bash
oc apply -f oauth-cluster.yaml
```
If `oauth/cluster` already has `identityProviders` from a previous task, **append** to the
list — replacing it wholesale locks out other IdPs (and can be graded wrong even if your new
one works).

`mappingMethod: claim` = default, fine for exam purposes (maps identity straight to a User of
the same name). Only worry about `add`/`lookup`/`generate` if the task explicitly says so.

## 4. Wait for the auth operator to roll out

```bash
oc get co authentication
# STATUS should go PROGRESSING=True briefly, then AVAILABLE=True / PROGRESSING=False again
oc get pods -n openshift-authentication -w
```
This takes ~30-90s. Don't try to log in as alice before this settles — you'll get
"invalid login credentials" even with the right password and think you made a typo.

## 5. Functional test — actually log in as the new user

```bash
oc login -u alice -p redhatB1 https://api.crc.testing:6443
oc whoami        # should print "alice"
oc login -u kubeadmin -p <kubeadmin-pass>   # switch back to admin for the next task
```
A `User` and `Identity` object get auto-created on first successful login:
```bash
oc get users
oc get identities
```

## 6. Adding / updating users later (secret already exists)

```bash
oc extract secret/htpasswd-secret -n openshift-config --to=- --keys=htpasswd > users.htpasswd
htpasswd -B -b users.htpasswd carol redhatB1
oc set data secret/htpasswd-secret --from-file=htpasswd=users.htpasswd -n openshift-config
```
`oc set data` replaces the secret's data in place — no need to delete/recreate, and no need to
touch `oauth/cluster` again (it already points at this secret).

## Common failure modes (why people lose points here)
- Forgot `-B` on `htpasswd` → cluster rejects the file format silently-ish (auth operator degrades).
- Wrong secret **key** name (must be `htpasswd`, not `users.htpasswd` or the filename).
- Replaced `identityProviders: [...]` instead of appending → wiped out an existing IdP from an earlier task.
- Tested login before the `authentication` ClusterOperator finished rolling out → false "it doesn't work".
- Created the secret in the wrong namespace (must be `openshift-config`, not `openshift-config-managed`).

## Verification checklist
- [ ] `oc get secret htpasswd-secret -n openshift-config` exists, key is `htpasswd`
- [ ] `oc get oauth cluster -o yaml` shows the HTPasswd provider referencing that secret
- [ ] `oc get co authentication` → `AVAILABLE=True`, not `PROGRESSING=True`
- [ ] `oc login -u alice -p ...` succeeds, `oc whoami` prints `alice`
- [ ] `oc get users` lists `alice`

## Cleanup
```bash
oc login -u kubeadmin -p <kubeadmin-pass>
oc delete secret htpasswd-secret -n openshift-config
# then oc edit oauth cluster and remove the identityProviders entry
```
