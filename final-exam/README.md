# Final Exam — EX280 Mock

A 28-task, 420-point mock exam (pass = 294/420, matching the real EX280's 70% bar). No
walkthroughs here — every task is phrased the way a real performance-based exam item reads:
requirements + how it will be verified, nothing about *how* to do it. If you need the "how,"
you skipped a step — go drill the matching numbered topic directory first.

Tasks deliberately mix pure OpenShift-specific skills with a few Kubernetes-native ones
(NetworkPolicy, rollouts, resource queries) so the simulation feels like the real thing, where
you don't get told in advance which parts are "OpenShift-only."

Tasks 01–20 are the original set. Tasks **21–28** were added 2026-09-21 to close gaps against
the published objectives: ConfigMaps/Secrets, scaling+HPA, groups, StatefulSet storage, image
triggers, project templates + ClusterResourceQuota, internal TLS + re-encrypt, and application
access to the Kubernetes API. Coverage went from roughly 57% to ~85% of the objective list.

## Directories

| Path | What |
|---|---|
| `tasks/` | the 28 task statements |
| `grading/` | one `grade-NN.sh` per task, plus `lib.sh` |
| `assets/` | **pre-generated** certs, keys and htpasswd — you never run `openssl` or `htpasswd` |
| `solutions/` | per-task walkthrough: the `oc` path AND the YAML path |
| `solutions/yaml/` | the exact manifests that were applied during verification |
| `work/` | your scratch space; `exam:reset` clears it |

All 28 tasks were solved end to end on a fresh CRC 4.22.7 cluster on 2026-09-21 and the full
suite scored **420/420**. Every command in `solutions/` is one that actually ran.

## Assets — nothing to generate

| File | Used by | Contents |
|---|---|---|
| `assets/htpasswd_ex280` | tasks 01, 23 | alice, bob, carol — all password `redhatB1` |
| `assets/edge-app/tls.{crt,key}` | task 06 | `CN=edge-app.apps-crc.testing`, valid to 2036 |
| `assets/tls-app/tls.{crt,key}` | task 19 | `CN=tls-app.apps-crc.testing`, valid to 2036 |
| `assets/task21/app.properties` | task 21 | sample config file |

Task 27 needs no assets at all — the cluster's service-CA issues that certificate itself.

## Prerequisites

- `crc` installed and working (`crc version`)
- `oc`, `helm`, `curl`, `openssl` and [`task`](https://taskfile.dev) on your `PATH`
  (macOS ships no `timeout(1)`; nothing here needs it on the host)
- This directory as your working directory when running `task ...`

### Route hostnames on macOS

`crc` does **not** provide wildcard DNS for `*.apps-crc.testing` — only the handful of hostnames
it writes into `/etc/hosts`. Your own route hostnames (tasks 06 and 19) therefore do not resolve
from the Mac by default. Grading does not care: `grade-06`/`grade-19` pin the hostname to the
router with `curl --resolve` / `openssl -servername`. If you want to test a route by hand
(browser or plain `curl`), add the hostname yourself:

```bash
sudo sed -i '' -e '$a\
127.0.0.1 edge-app.apps-crc.testing tls-app.apps-crc.testing' /etc/hosts
```

## Running the mock exam

```bash
task cluster:setup      # one-time: crc setup (downloads/extracts the OCP bundle, ~6GB)
task cluster:up         # crc start + oc login as kubeadmin; prints the kubeadmin password
task exam:start         # starts your 180-minute clock
```

Then open `tasks/01.md` through `tasks/20.md` (in this directory's `tasks/` subfolder) and
solve them for real, against your own CRC cluster — exactly like the actual exam. Some tasks
build on earlier ones (task 02/03 need the identity provider from task 01; task 20 needs a
project to exist first, which it creates for you on first run) — solving them roughly in order
is easiest, though the real exam doesn't strictly require that either.

```bash
task exam:time           # check remaining time against the 180-minute budget
task grade:05             # self-check a single task any time — no need to wait until the end
task grade:all            # grade everything, get your score out of 300 and BESTANDEN/NICHT BESTANDEN
```

When you're done (pass or fail) and want to try again from scratch:

```bash
task exam:reset          # deletes every ex280-t* project; keeps the cluster running
```

`exam:reset` does **not** revert the identity-provider (task 01) or self-provisioner (task 03)
changes on `oauth/cluster` / cluster RBAC — those are cluster-wide, not per-namespace, so
resetting them every time would make task 01/03 pointless to redo. If you want a fully clean
cluster, either `crc delete && crc setup && crc start` (slow, full rebuild) or manually revert
using the cleanup commands at the bottom of `21-htpasswd-auth/README.md` and
`22-rbac-oc-adm-policy/README.md`.

## Grading is a functional test, not a style check

Every `grade:NN` script inspects the actual cluster state — it does not care whether you used
the CLI, a YAML file, or the web console, only whether the end result matches what the task
asked for. A few scripts (01, 03) briefly log in as `alice`/`bob` to prove authentication
actually works, then automatically restore your `kubeadmin` session on exit — you don't need to
do anything to recover your session even if a grading script is interrupted mid-way.

## Scoring model vs the real exam

The real EX280 grades each task on a rubric with partial credit for some sub-requirements. This
mock keeps it binary per task (pass = full 15 points, anything else = 0) for simplicity — treat
a "fail" here as "go re-check every bullet in that task's requirements," not "you get zero
insight into what's wrong." Read the grading script's FAIL message; it names the specific
mismatch.

## Directory layout

```
final-exam/
├── Taskfile.yaml     # task cluster:*, exam:*, grade:* — see `task --list-all`
├── tasks/01.md..20.md    # the exam items themselves — no hints
├── grading/lib.sh + grade-01.sh..grade-20.sh   # functional verification per task
└── work/              # files three tasks ask you to produce:
                        #   task11/  kustomize base + overlay
                        #   task17/  frontend-names.txt + command.txt
                        #   task18/  digest.txt
                        # `task exam:reset` wipes work/task* so stale files can't false-pass
```
