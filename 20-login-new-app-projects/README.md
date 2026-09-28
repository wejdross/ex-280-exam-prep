# 20 — Login, Projects, `oc new-app`

**Why this is on EX280:** every task starts with logging in as the right user and being in
the right project. `oc new-app` is the OpenShift-native shortcut for "get something running"
— faster than hand-writing Deployment YAML when the task doesn't require a specific manifest.

**Status:** ✅ verified on a live CRC cluster (2026-07-17) — login, project create/switch, and
`oc new-app` from an image all confirmed working end-to-end (ImageStream + Deployment +
Service created automatically, pod reached Ready).

## 1. Login

```bash
oc login -u kubeadmin -p <password> https://api.crc.testing:6443
# or, once logged in once, switch users quickly:
oc login -u developer -p developer
oc whoami
oc whoami --show-console          # URL of the web console
oc whoami --show-server           # API server URL
```

On the real exam you'll be handed credentials for one or more users — get in the habit of
running `oc whoami` after every `oc login` so a typo doesn't silently leave you as the wrong
user for the next 10 minutes.

## 2. Projects (OpenShift's namespaces)

```bash
oc new-project myproj --description="EX280 practice" --display-name="My Project"
oc project myproj                 # switch current project
oc projects                       # list all projects you can see
oc get project myproj -o yaml     # a Project is just a namespace + annotations
```

`oc new-project` == `oc create namespace` + OpenShift project annotations (requester, display
name). If a task says "create a namespace", plain `oc create namespace foo` is fine too — but
`oc new-project` also switches your context to it, which `oc create namespace` does NOT.

Delete when done practicing:

```bash
oc delete project myproj
```

## 3. `oc new-app` — three flavors

```bash
# a) from an existing container image
oc new-app --name=hello quay.io/redhattraining/hello-world-nginx:latest

# b) from source (S2I build — OpenShift builds the image for you)
oc new-app --name=hello-src https://github.com/sclorg/nginx-container --context-dir=examples

# c) from an OpenShift Template (see 32-templates-helm/)
oc new-app --template=<template-name> -p PARAM=value
```

Check what got created — `new-app` creates a bundle, not just a Deployment:

```bash
oc get all -l app=hello
oc status
```

## 4. Exposing it (plain HTTP — see `24-routes-tls/` for TLS variants)

```bash
oc expose service/hello
oc get route hello -o jsonpath='{.spec.host}{"\n"}'
curl -s http://$(oc get route hello -o jsonpath='{.spec.host}')
```

## Verification checklist (functional test, not just "no error")
- [ ] `oc whoami` prints the expected user after login
- [ ] `oc get project myproj` shows the project exists and you're `oc project`'d into it
- [ ] `oc get pods` shows the new-app pod reaching `Running` / `1/1`
- [ ] `curl` against the exposed route returns HTTP 200 / expected body

## Cleanup
```bash
oc delete project myproj
```
