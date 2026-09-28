# 40 — Detecting Deprecated Kubernetes API Usage

**Why this is on EX280:** 🔴 confirmed as its own DO280 section under "OpenShift Updates" —
before upgrading a cluster, you're expected to know how to check whether anything currently
running depends on an API version that the target release removes. This is a specific,
nameable OpenShift feature (`APIRequestCount`), not something you'd stumble into from
Kubernetes-general knowledge.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — commands run correctly. Note: on
this freshly-installed 4.22 CRC cluster, `oc get apirequestcounts` legitimately returns **no
resources found** — every default component's API usage is already fully current, so there is
nothing deprecated being tracked. That is itself the correct, healthy answer, not a broken
command — don't expect to see example output here without a cluster that's actually calling
something deprecated (older workloads, older client libraries, etc.).

## Concept

The API server tracks, over a rolling window, which API versions are actually being called and
by whom — surfaced as `APIRequestCount` cluster-scoped resources, one per deprecated/removed
API. This is how you answer "if I upgrade, will anything break because it still calls a
removed API?" **before** actually upgrading, instead of finding out the hard way afterward.

## 1. List all tracked (deprecated/removed) API usages

```bash
oc get apirequestcounts
```
Each entry's name is the API group/version/resource being tracked (e.g.
`podsecuritypolicies.v1beta1.policy` for a long-since-removed API — the list changes release to
release, so don't memorize specific names, know the workflow).

## 2. Drill into one to see who's actually calling it

```bash
oc get apirequestcounts <name> -o yaml
```
Look under `status.currentHour`/`status.last24h` → `byNode` → `byUser` — this tells you exactly
which ServiceAccount/user, on which node, is making calls to the deprecated API, so you know
what to go fix (or who to go ask) before upgrading.

## 3. A quick "is anything about to break" sweep

```bash
oc get apirequestcounts -o jsonpath='{range .items[*]}{.metadata.name}{" removedInRelease="}{.status.removedInRelease}{"\n"}{end}' \
  | grep -v 'removedInRelease=$'
```
Anything printed here has a concrete `removedInRelease` version — if your target upgrade
version is at or past that, whatever's still calling it will break post-upgrade unless fixed
first.

## 4. Where this fits in the actual upgrade workflow

```bash
oc adm upgrade                      # shows current version + available channel updates
oc get apirequestcounts             # check for anything that'll break BEFORE upgrading
# ... fix/migrate anything at risk ...
oc adm upgrade --to=<version>        # only then proceed
```
This is the "why check this at all" answer if asked: skipping this step is how clusters end up
with broken workloads immediately after an otherwise-successful control-plane upgrade.

## Common failure modes
- Checking `oc get co`/`oc adm upgrade` for "cluster health" and assuming that's sufficient —
  ClusterOperator health says nothing about whether **your workloads'** API usage is about to
  break; that's what `APIRequestCount` is for specifically.
- Ignoring entries with no `removedInRelease` set — those are informational (deprecated but not
  yet scheduled for removal), lower priority than ones with a concrete removal version.
- Not checking `byUser`/`byNode` detail and therefore not knowing WHICH workload to actually go
  fix — the top-level list only tells you *that* something's calling a deprecated API, not
  *what*.

## Verification checklist
- [ ] `oc get apirequestcounts` runs without error (an empty list is a valid, healthy result)
- [ ] You can identify, for at least one entry, which specific ServiceAccount/user is generating the calls
- [ ] You can distinguish an entry with a concrete `removedInRelease` version from one that's merely deprecated
- [ ] You understand where this check fits relative to `oc adm upgrade` in the actual workflow

## Cleanup
No persistent state created by this topic — read-only exploration.
