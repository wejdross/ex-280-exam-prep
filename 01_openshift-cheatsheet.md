# OpenShift-specific cheat-sheet (EX280) — to, czego NIE ma w CKA/CKS/CKAD

> Zweryfikuj składnię na SWOJEJ wersji (`oc <cmd> --help`, `oc explain`). Oparte o OCP 4.x.

## 0. Login / projekty / new-app
```bash
oc login -u <user> -p <pass> https://api.cluster:6443
oc whoami ; oc whoami --show-console
oc new-project myproj ; oc project myproj
oc new-app --name=app quay.io/.../image:tag
oc new-app https://github.com/user/repo --name=app      # S2I build
oc expose service/app                                    # plain HTTP route
oc status ; oc get all
```

## 1. HTPasswd IdP (🔴🔴🔴 na pamięć)
```bash
htpasswd -c -B -b users.htpasswd alice redhat        # -c tworzy plik (pierwszy user)
htpasswd -B -b users.htpasswd bob redhat             # kolejni BEZ -c
oc create secret generic htpasswd-secret \
  --from-file=htpasswd=users.htpasswd -n openshift-config
oc edit oauth cluster                                # dodaj identityProvider
```
OAuth CR (`oc edit oauth cluster`):
```yaml
spec:
  identityProviders:
  - name: my_htpasswd
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData: { name: htpasswd-secret }
```
Aktualizacja userów (edycja istniejącego secretu):
```bash
oc extract secret/htpasswd-secret -n openshift-config --to=- > users.htpasswd
htpasswd -B -b users.htpasswd carol redhat
oc set data secret/htpasswd-secret \
  --from-file=htpasswd=users.htpasswd -n openshift-config
```

## 2. RBAC przez oc adm policy (🔴🔴🔴)
```bash
oc adm policy add-role-to-user edit alice -n myproj          # namespaced
oc adm policy add-cluster-role-to-user cluster-admin alice   # cluster-wide
oc adm policy add-role-to-group view devs -n myproj
oc adm policy remove-role-from-user edit alice -n myproj
# usun samoobslugowe tworzenie projektow:
oc adm policy remove-cluster-role-from-group self-provisioner system:authenticated:oauth
```

## 3. SCC + ServiceAccount (🔴🔴🔴 — klasyczny killer)
```bash
oc get scc
oc describe scc restricted-v2          # default od OCP 4.11
oc create sa mysa -n myproj
oc adm policy add-scc-to-user anyuid  -z mysa -n myproj    # -z = ServiceAccount!
oc adm policy add-scc-to-user nonroot -z mysa -n myproj
# w Deployment: spec.template.spec.serviceAccountName: mysa
```
Objaw: pod nie startuje / `CreateContainerError` / permission denied na UID → brakuje SCC dla jego SA.

## 4. Routes + TLS (🔴🔴🔴 — #1 przyczyna oblania)
```bash
oc expose svc/app                                  # HTTP (bez TLS)
# EDGE (TLS konczy sie na routerze; backend HTTP):
oc create route edge app --service=app \
  --cert=tls.crt --key=tls.key --hostname=app.apps.cluster
# PASSTHROUGH (TLS az do poda; brak certow na routerze):
oc create route passthrough app --service=app --hostname=app.apps.cluster
# REENCRYPT (TLS router->pod na nowo, z dest-ca):
oc create route reencrypt app --service=app \
  --cert=tls.crt --key=tls.key --dest-ca-cert=dest-ca.crt
```
Pamiętaj różnicę: **edge** (cert na routerze), **passthrough** (bez certu, pod robi TLS), **reencrypt** (cert + dest-ca).

## 5. Operators (OLM / OperatorHub) (🔴🔴)
```bash
oc get packagemanifests -n openshift-marketplace | grep -i <op>
```
Namespace + OperatorGroup + Subscription (YAML):
```yaml
# OperatorGroup (jeśli namespaced operator)
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata: { name: og, namespace: myproj }
spec: { targetNamespaces: [myproj] }
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata: { name: my-op, namespace: myproj }
spec:
  channel: stable
  name: <operator-package>
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```
Weryfikacja: `oc get csv -n myproj`, `oc get ip -n myproj` (InstallPlan).

## 6. Quota / LimitRange / CronJob (znasz z CKAD — składnia OCP)
```bash
oc create quota myquota --hard=cpu=4,memory=8Gi,pods=10 -n myproj
oc create -f limitrange.yaml -n myproj
oc create cronjob hello --image=busybox --schedule="*/5 * * * *" -- echo hi
```

## 7. Storage (znasz — OCP idiomy)
```bash
oc get sc                                  # StorageClasses
oc set volume deploy/app --add --name=data -t pvc \
  --claim-name=mypvc --mount-path=/data
```

## 8. Apps: probes / rollout / env (znasz — OCP)
```bash
oc set probe deploy/app --readiness --get-url=http://:8080/healthz
oc set probe deploy/app --liveness  --open-tcp=8080
oc set env  deploy/app KEY=value
oc set env  deploy/app --from=configmap/mycm
oc set image deploy/app app=image:2.0
oc rollout status deploy/app ; oc rollout undo deploy/app
```

## 9. Cluster ops (OCP)
```bash
oc adm cordon <node> ; oc adm drain <node> --ignore-daemonsets --delete-emptydir-data
oc adm top nodes ; oc adm top pods
oc adm upgrade                              # sprawdz/uruchom update
oc get co                                   # ClusterOperators (zdrowie)
```

## 10. Kustomize (🔴🔴🔴 — było brakujące, jest w oficjalnych objectives)
```bash
oc apply -k overlays/prod/          # deploy z kustomization.yaml
oc kustomize overlays/prod/         # tylko wyrenderuj YAML (bez apply) - debug
```
Struktura typowa:
```
base/
  kustomization.yaml
  deployment.yaml
  service.yaml
overlays/
  prod/
    kustomization.yaml     # referuje ../../base + patche
  dev/
    kustomization.yaml
```
`base/kustomization.yaml`:
```yaml
resources:
  - deployment.yaml
  - service.yaml
```
`overlays/prod/kustomization.yaml` (przykład patcha + generatora):
```yaml
resources:
  - ../../base
namePrefix: prod-
labels:
  - pairs:
      env: prod
    includeSelectors: true
patches:
  - target:
      kind: Deployment
      name: app
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
configMapGenerator:
  - name: app-config
    literals:
      - LOG_LEVEL=info
images:
  - name: app-image
    newTag: v2.0
```
**Uwaga:** `-k` = kustomize, `-f` = zwykły manifest. Nie mylić.

## 11. Templates + Helm charts (🔴🔴🔴 — było brakujące)
**OpenShift Templates** (stare, natywne OCP; parametryzowane YAML):
```bash
oc get templates -n openshift                       # wbudowane templates
oc process -f template.yaml -p NAME=foo | oc apply -f -
oc new-app --template=<template-name> -p PARAM=value
oc describe template <name> -n openshift             # zobacz parametry
```
Dodanie własnego template do katalogu projektu:
```bash
oc create -f my-template.yaml -n openshift
```
**Helm** (osobne narzędzie, ale wymagane na egzaminie):
```bash
helm repo add <repo-name> <url>
helm repo update
helm search repo <keyword>
helm install <release-name> <repo/chart> -n myproj
helm list -n myproj
helm upgrade <release-name> <repo/chart> -n myproj --set key=value
helm uninstall <release-name> -n myproj
helm show values <repo/chart>                         # zobacz konfigurowalne wartości
```
Konsola web: Developer perspective → +Add → Helm Chart / Catalog → też liczy się jako poprawna metoda.
**Różnica Template vs Helm:** Template = natywny OCP, prościej, mniej mocy. Helm = pełny package manager, wersjonowanie release'ów, rollback (`helm rollback`).

## 12. Expose non-HTTP/SNI applications (🔴🔴🔴 — osobna sekcja objectives, było brakujące)
Route (HAProxy) obsługuje TYLKO HTTP/HTTPS/TLS-z-SNI. Dla surowego TCP/UDP (np. baza danych, custom protokół) **Route nie zadziała** — trzeba Service typu LoadBalancer albo NodePort.
```bash
# zmień istniejący Service na LoadBalancer:
oc patch svc/app -p '{"spec":{"type":"LoadBalancer"}}'
# albo utwórz nowy:
oc create service loadbalancer app --tcp=5432:5432
oc get svc app                                        # sprawdź EXTERNAL-IP (zależy od providera/MetalLB)
# NodePort jako alternatywa (bez zależności od cloud LB):
oc create service nodeport app --tcp=5432:5432
oc get svc app -o jsonpath='{.spec.ports[0].nodePort}'
```
**Kluczowe rozróżnienie na egzaminie:** "wystaw appkę po HTTP" → Route. "Wystaw appkę po surowym TCP (baza, custom port)" → LoadBalancer/NodePort Service, NIE Route.

## 13. Jobs (🔴🔴 — jednorazowe zadania, odróżnij od CronJob)
```bash
oc create job myjob --image=busybox -- echo "hello"
oc create job myjob-from-cron --from=cronjob/hello     # odpal CronJob ręcznie, raz
oc get jobs
oc logs job/myjob
oc delete job myjob                                    # jobs nie czyszczą się same
```
CronJob (mieliśmy już, przypomnienie):
```bash
oc create cronjob hello --image=busybox --schedule="*/5 * * * *" -- echo hi
oc get cronjob ; oc get jobs -l cronjob-name=hello     # jobs stworzone przez crona
```

## 14. Labels, selectors, query/format/filter (🔴🔴 — było tylko dorozumiane)
```bash
oc label pod mypod env=prod                            # dodaj label
oc label pod mypod env-                                 # usuń label (minus na końcu klucza)
oc get pods -l env=prod                                 # filtruj po labelu
oc get pods -l 'env in (prod,staging)'                  # set-based selector
oc get pods --show-labels
oc get pods -o wide
oc get pods -o jsonpath='{.items[*].metadata.name}'      # jsonpath - częste na egzaminie
oc get pods -o custom-columns=NAME:.metadata.name,IP:.status.podIP
oc get deploy app -o yaml | grep -A3 selector            # sprawdź selector Deploymentu
```
Selector musi się zgadzać: `Deployment.spec.selector.matchLabels` == `Pod.metadata.labels` (inaczej Deployment nie widzi swoich podów).

## 15. Image tags vs digests (🔴 — było brakujące)
```bash
oc get is                                                # ImageStreams
oc describe imagestream app
oc describe imagestreamtag app:latest                     # tag -> konkretny digest
oc image info quay.io/org/image@sha256:abcdef...          # info o obrazie po digest
```
**Tag** (`image:v1`) = ruchoma etykieta, może wskazywać na różne digesty w czasie.
**Digest** (`image@sha256:...`) = niezmienny, immutable, jednoznaczny — używaj w produkcji dla powtarzalności.

## 16. Monitor cluster events & alerts (🔴 — było brakujące)
```bash
oc get events -n myproj --sort-by=.lastTimestamp          # events w namespace, chronologicznie
oc get events -A --sort-by=.lastTimestamp | tail -20        # cały klaster
oc describe pod mypod                                       # sekcja Events na dole - debug pierwszy krok
```
Alerts (Prometheus/Alertmanager wbudowany w OCP monitoring):
- Konsola web → **Administrator perspective → Observe → Alerting** (firing alerts, silences).
- `oc get co` — health ClusterOperators (Degraded/Progressing/Available).
- `oc adm top nodes` / `oc adm top pods` — zużycie zasobów, szybki sanity check.

## Nawyki egzaminacyjne
- Po KAŻDYM tasku: **functional test** (curl route, `oc get ...`, zaloguj jako user).
- Rób **deklaratywnie** (YAML), żeby przeżyło reboot.
- `oc explain <res>.spec` zamiast szukania w docs.
- Konsola web bywa szybsza dla Operatorów/IdP/Helm — mieszaj CLI + UI.
