# 34 — Labels, Selectors, Query/Format/Filter

**Why this is on EX280:** listed explicitly under "resource queries" in the official objectives
— fast, precise `oc get`/`jsonpath`/`custom-columns` usage saves real time across every other
task, and is exactly the kind of thing that's easy to fumble live even though you "know" it.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — every command in this walkthrough was actually run end-to-end via the final-exam tasks.

## 1. Labels — add / remove / view

```bash
oc label pod mypod env=prod                 # add or overwrite
oc label pod mypod env=staging --overwrite  # explicit overwrite (needed if key already set... actually not required, but be aware some contexts require it)
oc label pod mypod env-                     # remove (trailing '-' on the KEY)
oc get pods --show-labels
oc get pods -L env,tier                     # show specific label columns
```

## 2. Selectors — filter by label

```bash
oc get pods -l env=prod
oc get pods -l 'env in (prod,staging)'
oc get pods -l 'env notin (dev)'
oc get pods -l env!=dev
oc get pods -l 'app,!env'                    # has label app, does NOT have label env
```

## 3. Matching Deployment ↔ Pod selectors (a real debugging skill, not just syntax trivia)

```bash
oc get deploy app -o yaml | grep -A3 "^  selector:"
oc get pods -l app=app --show-labels
```
`Deployment.spec.selector.matchLabels` must be a subset of
`.spec.template.metadata.labels` — if they diverge (usually from a bad `oc patch`/manual edit),
the Deployment stops seeing its own pods and can appear to "not scale" or spawn duplicates.
This mismatch is immutable after creation — you cannot `oc edit` a Deployment's selector once
created; you'd need to recreate the Deployment.

## 4. jsonpath — the format the exam rewards knowing cold

```bash
oc get pods -o jsonpath='{.items[*].metadata.name}{"\n"}'
oc get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'
oc get deploy app -o jsonpath='{.spec.replicas}{"\n"}'
oc get route app -o jsonpath='{.spec.host}{"\n"}'
oc get secret mysecret -o jsonpath='{.data.password}' | base64 -d
oc get nodes -o jsonpath='{.items[?(@.status.conditions[-1].type=="Ready")].metadata.name}'
```

## 5. custom-columns — quick tabular output without full jsonpath verbosity

```bash
oc get pods -o custom-columns=NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName
oc get pods -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready
```

## 6. Other everyday filters

```bash
oc get pods -o wide
oc get pods --field-selector=status.phase=Running
oc get events --field-selector involvedObject.name=mypod
oc get all -l app=app                      # every resource type tagged with a label at once
```

## Common failure modes
- Missing `{"\n"}` at the end of a jsonpath expression — output runs into your next shell
  prompt with no newline, easy to misread as an error.
- Used `-l key=value` when the task wanted set-based (`in (...)`) matching against multiple
  values — quote the whole selector so the shell doesn't split it (`'env in (prod,staging)'`).
- Forgot label removal syntax is a **trailing** dash on the key (`env-`), not `--remove` or a
  separate subcommand.
- Assumed you could patch a Deployment's `spec.selector` to fix a mismatch — it's immutable;
  the actual fix is aligning `template.metadata.labels`, or recreating the Deployment.

## Verification checklist
- [ ] `oc get pods --show-labels` reflects label add/remove exactly as intended
- [ ] A jsonpath query returns the precise single value expected (no extra brackets/quotes in output)
- [ ] `oc get deploy -o yaml` selector matches pod template labels (no orphaned pods from a mismatch)
- [ ] `custom-columns` output has the right column headers and values line up per row

## Cleanup
```bash
oc label pod mypod env-
```
