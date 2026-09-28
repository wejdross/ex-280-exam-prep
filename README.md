# EX280 exam prep: Red Hat Certified OpenShift Administrator

Study notes, 27 hands-on topic walkthroughs and a self-grading 28-task mock exam for
**EX280**, all runnable on a laptop with OpenShift Local (CRC).

I passed the exam with this material. Verification:
**<https://rhtapps.redhat.com/verify?certId=260-131-719>**

## How this was made

Most of the content in this repository was generated with [Claude](https://claude.ai)
(Claude Code) while I was preparing. I then edited the files by hand so that the topics,
the mock-exam tasks and the grading scripts match what the real exam actually asks for.
Every walkthrough and every mock task was run against a live CRC cluster; the status is
noted in each file's header.

## What the real exam asked me to do

Without reproducing exam content, these are the areas I had to cover during my sitting.
Every one of them has a matching topic directory and mock-exam task below.

| Area | What I had to do | Topic dir | Mock task |
|---|---|---|---|
| Authentication | create and manage an **htpasswd** file, build the Secret, wire the HTPasswd identity provider into `oauth/cluster`, add and remove users later | `21-htpasswd-auth` | 01, 23 |
| Authorization | everything **`oc adm policy`** offers: `add-role-to-user`, `add-cluster-role-to-user`, `add-role-to-group`, `remove-cluster-role-from-group`, `add-scc-to-user` | `22-rbac-oc-adm-policy`, `23-scc-serviceaccounts` | 02, 03, 05 |
| Groups | create **groups**, add users to them, bind roles to **groups and users** | `22-rbac-oc-adm-policy` | 23 |
| Self-service | configure the **project request template** (LimitRange, NetworkPolicy defaults for new projects) | `46-project-template-clusterquota` | 26 |
| Network security | **NetworkPolicy** for namespace and pod isolation | `38-networkpolicy` | 08 |
| Routes | an **edge TLS route** with a supplied certificate and key | `24-routes-tls` | 06 |
| Operators | **install an operator** from OperatorHub via OLM (OperatorGroup + Subscription) | `25-operators-olm` | 14 |
| Scheduling | create a **CronJob** | `27-jobs-cronjobs` | 15 |

The rest of the objectives (quota, storage, probes, Kustomize, Helm, templates, image
digests, non-HTTP exposure, troubleshooting) are covered too, they just were not the tasks
that stood out on my exam day.

## Layout

```
00_ex280-plan.md              exam facts, gap analysis vs CKA/CKAD/CKS, lab-environment notes (Polish)
01_openshift-cheatsheet.md    OpenShift-only commands you will not know from Kubernetes (Polish headings)
99_ex280_drill.txt            command flashcards: cue | answer | rule
20-..46-*/README.md           one walkthrough per topic: create the files, run the commands, verify
final-exam/                   28-task mock exam with functional grading (see its README)
practice-scratch/             hand-written manifests from drilling sessions
project-request.yaml          the bootstrap project template as a starting point
```

Walkthroughs, mock tasks, solutions and grading scripts are in English. The plan,
cheatsheet and drill file are in Polish; the commands inside them are what matters.

### Topic directories

| Dir | Topic |
|---|---|
| 20 | login, `oc new-app`, projects |
| 21 | HTPasswd identity provider |
| 22 | RBAC with `oc adm policy`, groups, project templates |
| 23 | SCC and ServiceAccounts |
| 24 | Routes: edge, passthrough, re-encrypt |
| 25 | Operators and OLM |
| 26 | ResourceQuota and LimitRange |
| 27 | Jobs and CronJobs |
| 28 | PV/PVC storage |
| 29 | probes, rollouts, env |
| 30 | cluster ops: cordon, drain, `oc adm top`, upgrades |
| 31 | Kustomize |
| 32 | Templates and Helm |
| 33 | exposing non-HTTP services |
| 34 | labels, selectors, jsonpath |
| 35 | ImageStreams, tags, digests |
| 36 | events, alerts, monitoring |
| 37 | internal TLS with service serving certs |
| 38 | NetworkPolicy |
| 39 | application access to the Kubernetes API |
| 40 | detecting deprecated API usage |
| 41 | Multus secondary networks |
| 42 | ConfigMaps and Secrets |
| 43 | scaling and HPA |
| 44 | StatefulSet storage |
| 45 | image triggers |
| 46 | project template and ClusterResourceQuota |

## Lab environment: CRC (OpenShift Local)

Everything was tested on CRC on macOS. `final-exam/Taskfile.yaml` wraps the cluster
lifecycle:

```bash
brew install crc go-task            # plus oc, helm, curl, openssl on PATH
cd final-exam
task cluster:setup                  # crc setup + enable cluster monitoring (one time, ~6 GB bundle)
task cluster:up                     # crc start + oc login as kubeadmin
task cluster:status                 # crc status + oc get co
task cluster:down                   # crc stop
```

Settings that made the difference on my machine, from the notes in `00_ex280-plan.md`:

| Setting | Why |
|---|---|
| `crc config set disk-size 80` | default 31 GiB hits `DiskPressure` after a few topics |
| `crc config set memory 16384`, `crc config set cpus 6` | 20 projects at once, monitoring stack |
| `crc config set enable-cluster-monitoring true` | needed for `oc adm top` and the alerting topic |
| use `~/.crc/bin/oc/oc`, not an old `oc` on PATH | client and server must be within one minor version |

CRC on macOS has no wildcard DNS for `*.apps-crc.testing`; the mock exam's grading pins
route hostnames with `curl --resolve`, see `final-exam/README.md` for adding them to
`/etc/hosts` by hand.

## Mock exam

```bash
cd final-exam
task exam:start        # start the clock
# solve tasks/01.md .. tasks/28.md against your cluster
task grade:05          # check one task any time
task grade:all         # full score, pass mark is 70%
task exam:reset        # wipe the ex280-t* projects and start over
```

The grading is functional: each script inspects cluster state, not how you got there.
Solutions with both the `oc` and the YAML path are in `final-exam/solutions/`. The
certificates, keys and htpasswd file under `final-exam/assets/` are pre-generated
throwaways for CRC hostnames so that you never have to leave the exam flow to run
`openssl` or `htpasswd`.

## Disclaimer

This is personal study material, not official Red Hat content. Task wording is my own and
does not reproduce exam items. EX280 targets OCP 4.18 while CRC ships a newer release, so a
few commands differ in detail. Check with `oc <cmd> --help` and `oc explain`.

## License

Public domain under [The Unlicense](LICENSE). Do whatever you want with it.
