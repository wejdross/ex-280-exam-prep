# 30 — Cluster Operations: cordon/drain, top, upgrade, ClusterOperators

**Why this is on EX280:** the `oc adm` cluster-ops subcommands and OpenShift's
`ClusterOperator`/`ClusterVersion` health model are OCP-specific — CKA teaches
`kubectl cordon/drain`, which map 1:1, but the health-check vocabulary (`oc get co`,
`oc get clusterversion`) does not exist on vanilla Kubernetes.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — `oc get co`, `oc get clusterversion`,
and `oc adm top nodes/pods` all confirmed working (requires `enable-cluster-monitoring true` in
`crc config`, which `final-exam/Taskfile.yaml`'s `cluster:setup` now sets automatically — CRC
ships with monitoring OFF by default, and `oc adm top` errors with "Metrics API not available"
until it's on and the cluster has been restarted after enabling it). Cordon/drain themselves
were **not** exercised against the only node — deliberately, since that would evict every pod
including the router/API-adjacent components on a single-node lab; know the commands, but don't
expect to safely rehearse them here the way you could on a real multi-node exam cluster.

## 1. Node maintenance: cordon + drain

```bash
oc get nodes
oc adm cordon <node>                      # mark unschedulable, doesn't touch running pods
oc adm drain <node> --ignore-daemonsets --delete-emptydir-data
oc adm uncordon <node>                    # bring it back into scheduling
```
`--ignore-daemonsets` is required (DaemonSet pods aren't meant to be evicted); on a real
multi-node cluster `--delete-emptydir-data` is needed if any pod uses an `emptyDir` volume,
which drain otherwise refuses to touch.

## 2. Resource usage

```bash
oc adm top nodes
oc adm top pods -A
oc adm top pods -n myproj --sort-by=cpu
```
Requires the `metrics-server`/monitoring stack to be up — on a fresh cluster this can 404 for
the first few minutes.

## 3. Cluster health — ClusterOperators + ClusterVersion

```bash
oc get co                      # every core component: AVAILABLE / PROGRESSING / DEGRADED
oc get co | grep -v "True.*False.*False"   # quick "what's NOT healthy" filter
oc get clusterversion
oc describe clusterversion version
```
A healthy cluster: every ClusterOperator shows `AVAILABLE=True PROGRESSING=False DEGRADED=False`.

## 4. Upgrade

```bash
oc adm upgrade                              # shows current version + available channel updates
oc adm upgrade channel <channel-name>        # switch update channel
oc adm upgrade --to=<version>                # trigger an upgrade (needs a real update service; typically not exercised hands-on in a CRC lab)
oc adm upgrade --to-latest=true
```
On the real exam this is more likely to be a "read the state, answer/report on it" task than
"actually upgrade a live cluster in 3 hours" — know the read commands (`oc adm upgrade`,
`oc get clusterversion -o yaml`) cold even if you never trigger a real upgrade in practice.

## 5. Node details / troubleshooting entrypoints

```bash
oc describe node <node>              # capacity, allocatable, conditions, running pods
oc adm node-logs <node> -u kubelet
oc get events -A --sort-by=.lastTimestamp | tail -30
```

## Common failure modes
- Drained a node without `--ignore-daemonsets` → command errors out, nothing happens, looks
  "stuck" if you don't read the error message.
- Forgot to `oc adm uncordon` after maintenance — node stays `SchedulingDisabled` forever,
  breaks later tasks that need pods to (re)schedule.
- Read `oc get co` too literally as pass/fail — a `PROGRESSING=True` operator right after a
  config change is often normal and transient; give it a minute before treating it as broken.

## Verification checklist
- [ ] `oc get nodes` shows `SchedulingDisabled` immediately after cordon, gone after uncordon
- [ ] `oc get co` — all operators `Available=True`, `Degraded=False` before considering a task "done"
- [ ] `oc adm top nodes` returns numbers, not an error (monitoring stack is up)
- [ ] `oc get clusterversion` shows the expected version/channel

## Cleanup
```bash
oc adm uncordon <node>
```
