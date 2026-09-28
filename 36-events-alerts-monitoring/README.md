# 36 — Cluster Events & Alerts Monitoring

**Why this is on EX280:** listed under "manage OpenShift Container Platform" (monitoring/
troubleshooting) — the exam expects `oc get events` + built-in Prometheus/Alertmanager
awareness as your first-line debugging reflex, before diving into logs.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — `oc get events`, `oc get co`,
`oc adm top`, and the `openshift-monitoring` pods/Alertmanager route all confirmed present and
working. Same caveat as `30-cluster-ops/`: CRC ships with monitoring disabled by default —
`final-exam/Taskfile.yaml`'s `cluster:setup` now enables it for you, but if you set up CRC
independently of this repo's Taskfile, run `crc config set enable-cluster-monitoring true`
yourself before `crc start` (or `crc stop` + `crc start` again if the cluster's already up).

## 1. Events — always the first thing to check on any "why isn't this working" task

```bash
oc get events -n myproj --sort-by=.lastTimestamp
oc get events -A --sort-by=.lastTimestamp | tail -30
oc get events --field-selector involvedObject.name=mypod -n myproj
oc describe pod mypod -n myproj              # Events section at the bottom — fastest single command
```
Events are namespaced and **expire** (short retention, ~1h by default) — if you wait too long
after a failure to look, they're gone; check early.

## 2. Built-in monitoring stack

```bash
oc get pods -n openshift-monitoring
oc get co monitoring                          # ClusterOperator health for the stack itself
```
Web console → **Administrator perspective → Observe**:
- **Observe → Dashboards** — cluster-level CPU/memory/network graphs
- **Observe → Metrics** — ad-hoc PromQL query box
- **Observe → Alerting** — firing alerts, silences, alerting rules

## 3. Querying Prometheus metrics from the CLI (when console access is inconvenient)

```bash
TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring 2>/dev/null || oc whoami -t)
HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://$HOST/api/v1/query?query=up" | head -c 500
```
On the real exam, the web console **Observe → Metrics** query box is almost always faster and
less fiddly than hand-building a curl+token call — default to it unless a task specifically
demands CLI output.

## 4. Alerts — read state, understand severity

```bash
oc get prometheusrules -A | grep -i <alert-name>
```
Console: **Observe → Alerting → Alerts** — filter by state (Firing/Pending/Silenced) and
severity (Critical/Warning/Info). Silencing: **Alerting → Silences → Create Silence**.

## 5. Quick cluster-wide sanity check sequence (memorize this order)

```bash
oc get co                       # 1. is the control plane itself healthy?
oc get nodes                    # 2. are all nodes Ready?
oc adm top nodes                # 3. any resource pressure?
oc get events -A --sort-by=.lastTimestamp | tail -20   # 4. anything recent and abnormal?
oc get pods -A | grep -v Running | grep -v Completed   # 5. anything not in a good state?
```

## Common failure modes
- Went straight to `oc logs` before checking `oc describe pod`'s Events section — Events often
  show the actual scheduling/pull/mount failure reason in one line, saving a log deep-dive.
- Assumed a `PROGRESSING=True` ClusterOperator is broken — it's often mid-rollout after a
  legitimate config change; check `Degraded` specifically, and re-check after a minute.
- Looked for alerts only in `oc get events` — Alertmanager-fired alerts are a **separate**
  system (Prometheus rules, not core API events) surfaced under Observe → Alerting, not `oc get events`.

## Verification checklist
- [ ] `oc get events -n myproj --sort-by=.lastTimestamp` surfaces the expected recent event
- [ ] `oc get co` — all `Degraded=False` before calling any cluster-config task "done"
- [ ] Console **Observe → Alerting** loads and shows the cluster's current alert state
- [ ] `oc adm top nodes`/`oc adm top pods` return real numbers (monitoring stack is functional)

## Cleanup
No persistent state created by this topic — read-only exploration.
