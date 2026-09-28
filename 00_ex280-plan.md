# EX280 — Red Hat Certified Specialist in OpenShift Administration

## Fakty o egzaminie (zweryfikowane)
- **Format:** performance-based, **~3h**, jedna sesja lab na **żywym klastrze OCP**. Zero MCQ.
- **Wersja:** oparty o **OpenShift Container Platform 4.18** (aktualnie).
- **Zadania:** ~15–23 realnych tasków, różne wagi (core = więcej punktów).
- **Zaliczenie:** **210/300 (70%)**.
- **Open book:** masz dostęp do **oficjalnej dokumentacji OpenShift** (bez listy komend); pomoc CLI (`oc <cmd> --help`, `oc explain`).
- **KRYTYCZNE:** konfiguracja musi **przetrwać reboot** (deklaratywnie, nie hacki w locie). **Weryfikuj każdy task.**

## Twój background vs egzamin (gap-analysis)

### 🟢 Masz z CKA/CKS/CKAD (transfer ~bezpośredni)
Deployments/Pods/Services, ConfigMaps/Secrets, **PV/PVC/StorageClass + dynamic provisioning**, **NetworkPolicy**, probes/health checks, **ResourceQuota/LimitRange**, CronJobs, RBAC Role/RoleBinding (K8s-native), YAML authoring, troubleshooting/logs, rollouts/rollback. → Tu nie tracisz czasu, tylko mapujesz `kubectl`→`oc`.

### 🔴 OpenShift-specific — TU SIĘ UCZYSZ (i tu ludzie oblewają)
| Temat | Dlaczego gap | Priorytet |
|---|---|---|
| **HTPasswd IdP** (OAuth cluster CR + secret) | czysto OCP, trzeba znać flow na pamięć | 🔴🔴🔴 |
| **oc adm policy** (RBAC + SCC) | `add-role-to-user`, `add-cluster-role-to-user`, `add-scc-to-user` | 🔴🔴🔴 |
| **SCC** (restricted-v2/nonroot/anyuid) | inny mechanizm niż PodSecurity z CKS; pody padają na permissions | 🔴🔴🔴 |
| **Routes + TLS** (edge/passthrough/reencrypt) | **#1 przyczyna oblania** — ćwiczenia z kursu ≠ egzamin | 🔴🔴🔴 |
| **Operators (OLM/OperatorHub)** | Subscription + OperatorGroup + channel + source | 🔴🔴 |
| **oc new-app / new-project / expose** | idiomy OCP zamiast kubectl create | 🔴🔴 |
| **Project templates / self-provisioner / default nodeSelector** | admin-config OCP | 🔴 |
| **ImageStreams** (lżej niż kiedyś) | OCP-specific build/deploy | 🔴 |
| **oc adm upgrade / cordon / drain / top** | cluster ops OCP-style | 🔴 |

## Dlaczego ludzie oblewają (unikaj tego)
1. **TLS na Routes** — edge vs passthrough vs reencrypt + certy. Najczęstszy killer. Wyćwicz do automatyzmu.
2. **Zależności między taskami** — jeśli task 3 (np. IdP/SCC) zrobisz źle, task 8 (deploy jako user) się sypie kaskadowo. Rób starannie od początku.
3. **Detale** — pominięty jeden element konfiguracji = task nie liczony. **Weryfikuj wynik** (functional test).
4. **Time management** — 3h, dokumentacja to rabbit-hole. Nie „czytaj docs" — używaj `oc explain`/`--help` i leć.
5. **Persist after reboot** — rób deklaratywnie (YAML/oc apply), nie interaktywne hacki.
6. **Secrets/ConfigMaps/Volumes/Health checks** — w niektórych materiałach niedoreprezentowane, a na egzaminie są. (Ty to znasz z CKAD — atut.)

## Plan nauki (Pareto)
1. **Postaw sobie klaster do ćwiczeń:** CRC (CodeReady Containers / OpenShift Local) na laptopie ALBO Red Hat Developer Sandbox (free, ograniczony — brak cluster-admin do IdP/SCC → do części zadań i tak potrzebny własny klaster/CRC). Masz OCP w pracy — idealne lab.
2. **Drill OCP-specific** (patrz `01_openshift-cheatsheet.md` + `99_ex280_drill.txt`) — komendy na automatyzm, zwłaszcza IdP/SCC/Routes-TLS/Operators.
3. **Hands-on repeat** high-frequency tasków: deploy+probes+route(TLS), PV/PVC, NetworkPolicy, quota/limit, SCC+SA, HTPasswd user, Operator install.
4. **2–3 pełne mock-egzaminy** na czas (3h) w 1–2 tygodnie przed. Trenuj tempo + weryfikację.

## Zasoby
- Oficjalne: kurs **DO280** (+ DO180 bazowo) — objectives z redhat.com/EX280.
- Lab: **OpenShift Local (CRC)** lub sandbox.developers.redhat.com.
- Docs: docs.openshift.com (masz do nich dostęp na egzaminie — naucz się szybko nawigować).

## Proces
Ćwicz task → jak się wywalisz, dopisz błąd/komendę do `99_ex280_drill.txt` → drilluj przed kolejną sesją. Pętla ta sama.

---

## Aktualizacja gap-analysis (2026-07-13, zweryfikowane na redhat.com/EX280, live objectives)

Sprawdziłem oficjalną listę objectives na stronie Red Hata (wciąż OCP 4.18). Nasz istniejący cheatsheet/drill pokrywa większość, ale **brakuje kilku sekcji z aktualnych objectives** — prawdopodobnie dodanych do egzaminu po tym, jak pierwsza wersja tego pliku powstała. To nowe 🔴 priorytety, bo nieprzećwiczone = zero:

| Temat (z oficjalnych objectives) | Status u nas | Priorytet |
|---|---|---|
| **Kustomize** (deploy + overlays) | ❌ brakowało całkowicie | 🔴🔴🔴 |
| **Templates + Helm charts** (deploy z obu) | ❌ brakowało całkowicie | 🔴🔴🔴 |
| **Expose non-HTTP/SNI apps** (LoadBalancer Service, external access bez Route) | ❌ brakowało całkowicie | 🔴🔴🔴 (osobna sekcja objectives = na pewno pytanie) |
| **Jobs** (jednorazowe, odróżnij od CronJob) | ❌ brakowało (mieliśmy tylko CronJob) | 🔴🔴 |
| **Labels/selectors + query/format/filter** (`-l`, `-o jsonpath`, `--show-labels`) | 🟡 tylko dorozumiane | 🔴🔴 |
| **Image tags vs digests** (`oc image info`, `@sha256:`) | ❌ brakowało | 🔴 |
| **Cluster events & alerts monitoring** (`oc get events`, Observe→Alerting) | 🟡 tylko `oc get co` | 🔴 |
| Import/export manifestów (`-o yaml >`, `apply -f`) | 🟡 oczywiste z CKA, nie drillowane explicite | 🟡 |

Dopisane do `01_openshift-cheatsheet.md` (sekcje 10-16) i do `99_ex280_drill.txt` (flashcards). Drilluj to PRZED resztą — to są luki, nie powtórki.

**Reszta objectives** (image lookup, RBAC/SCC, Routes+TLS, quota/limitrange, storage, probes/rollout, operators, cordon/drain) — pokrywa się z tym co już mieliśmy, bez zmian.

## Weryfikacja 2026-07-17 (research agent, redhat.com/EX280 + DO280 live)

- **9 oficjalnych domen objectives potwierdzonych 1:1** z naszą strukturą tematów — nic większego nie brakuje.
  Domeny: (1) Manage OCP (konsola/CLI, projekty, obrazy, query zasobów, import/export, status klastra,
  monitoring, troubleshooting), (2) Resource manifests (YAML, Kustomize, secrets, ConfigMaps),
  (3) Deploy apps (Templates, Helm, Deployments/RS, labels, Services, external access),
  (4) AuthN/AuthZ (HTPasswd, users/groups, permissions), (5) Network security (routes, ingress, TLS,
  NetworkPolicy), (6) Expose non-HTTP/SNI (LoadBalancer Service), (7) Developer self-service (quota,
  LimitRange, **project templates**), (8) Operators (OLM install/update/uninstall), (9) Application security
  (ServiceAccounts, SCC, secrets, API access, Jobs/CronJobs).
- **KOREKTA "open book":** to NIE jest internet/wyszukiwarka. Dostajesz **offline mirror** dokumentacji
  OCP z access.redhat.com (HTML/PDF, **bez okienka wyszukiwania** — musisz wiedzieć w który dział wejść) +
  `oc --help` / `oc explain` / man. Trenuj nawigację po spisie treści, nie "szukaj po słowie kluczowym".
- **Nazwa certyfikatu zmieniona (2023, nie 2026):** "Red Hat Certified Specialist in OpenShift
  Administration" → **"Red Hat Certified OpenShift Administrator"**, kod egzaminu wciąż EX280.
- **210/300 (70%) i ~3h:** NIE ma tego już na oficjalnej stronie marketingowej wprost — powtarzane
  konsekwentnie w community/Red Hat Learning Community, więc traktuj jako prawdopodobnie aktualne, ale
  **medium confidence**, nie 100% zweryfikowane z primary source.
- **Tekton/GitOps/ArgoCD/Virtualization/Service Mesh:** NIE znalezione w oficjalnych objectives (EX280
  ani DO280). Kilka stron typu "exam dump" twierdzi inaczej — niepotwierdzone, low confidence, **nie
  przenoś tu czasu nauki**.
- **Uzupełniono lukę:** "project request template" (self-service admin config, `oc adm
  create-bootstrap-project-template` + `project.config.openshift.io/cluster`) dopisane do
  `22-rbac-oc-adm-policy/README.md` — było tylko częściowo pokryte (mieliśmy self-provisioner, brakowało
  customowego project template).

## Środowisko lab (stan 2026-09-05, po naprawie)

Klaster CRC był w złym stanie po przerwie (lipiec → wrzesień). Naprawione:

| Problem | Było | Jest |
|---|---|---|
| **Node w DiskPressure** (kubelet eksmitował pody, GC obrazów) | disk-size 31 GiB, 27,3/32,7 GB zajęte | `disk-size 80` → 29,2/85,3 GB, `DiskPressure=False` |
| **Skew klienta `oc`** (wspierany zakres to ±1 minor) | `/usr/local/bin/oc` = **4.16.0** vs serwer 4.22.7 | PATH prepend w `~/.zshrc` → `~/.crc/bin/oc/oc` = **4.22.7** |
| **Monitoring wyłączony** (blokował tematy 30 i 36: `oc adm top`, alerty) | `enable-cluster-monitoring` nieustawione | `true` → 12 podów w `openshift-monitoring` Running, `oc adm top nodes` działa |
| Zasoby VM ciasne na 20 projektów naraz | 10,5 GB RAM / 4 CPU | `memory 16384` / `cpus 6` (host: 48 GB / 12 CPU) |

Cofnięcie zmiany `oc`: usuń linię `export PATH="$HOME/.crc/bin/oc:$PATH"` z `~/.zshrc`.

**Uwaga o wersji:** CRC serwuje teraz **OCP 4.22.7**, a egzamin celuje w **4.18**. Do ćwiczeń OK,
ale kilka zachowań się rozjedzie — np. `oc get apirequestcounts` (temat 40) na świeżej 4.22 zwraca
legalnie „no resources found", bo nic nie używa przestarzałych API.

**Stan przed mockiem (zweryfikowany):** zero projektów `ex280-t*`, brak `alice`/`bob`, IdP tylko
wbudowany CRC-owy `developer`, binding `self-provisioner` nietknięty, zegar `.exam-start`
nieuruchomiony, wszystkie ClusterOperatory zdrowe. `task grade:01` przechodzi smoke-test
(poprawnie FAIL-uje na nieskonfigurowanym IdP, sesja kubeadmin zachowana). Czysty start.
