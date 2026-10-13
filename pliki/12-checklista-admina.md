# Checklista administratora Grafany OSS

Moduł 12, lekcja 08. Kopia do uzupełnienia dla własnej instancji. Przy każdym punkcie: stan (✅ / ⚠️ / ❌), właściciel, termin, sposób sprawdzenia. W nawiasie moduł kursu, w którym punkt ćwiczyłeś.

Instancja: ______________________ · wersja Grafany: ________ · data przeglądu: ________

## 1. Upgrade'y

- [ ] Wersja to ostatnia łatka używanej linii (release notes i security advisories sprawdzone). (12)
- [ ] Proces: łatka linii → aktualizacja pluginów → wersja major, każdy krok najpierw na stagingu. (12)
- [ ] Upgrade guide i breaking changes docelowej wersji przeczytane; skrypty, entrypointy, jednostki systemd i role Ansible sprawdzone pod kątem usuniętych poleceń i funkcji (np. `grafana cli` zamiast `grafana-cli`). (10, 12)
- [ ] `/api/plugins/errors` na stagingu po upgrade'zie bez wpisów (np. `angular`, `failedBackendStart`). (12)
- [ ] Advisor bez datasource'ów z `missing-plugin`. (12)
- [ ] `grafanaDependency` każdego pluginu obejmuje docelową wersję Grafany. (12)

## 2. Pluginy jako kod

- [ ] Każdy plugin pochodzi z konfiguracji (`preinstall*`, Helm `plugins:`, obraz), żaden z ręcznej instalacji (`pliki/12-plugin-inventory.sh` → kolumna `zrodlo` bez `reczny`). (12)
- [ ] Wersje przypięte w `preinstall`; `preinstall_sync` tylko dla pluginów potrzebnych w provisioningu. (12)
- [ ] Wersje pinów istnieją w katalogu (`https://grafana.com/api/plugins/<id>/versions`). (12)
- [ ] Decyzja o `preinstall_auto_update` zapisana; przy `false` jest cykliczny przegląd wersji (pin w `preinstall` wycisza Advisora i badge). (12)
- [ ] Kubernetes: wiadomo, czy root FS jest read-only i czy `shadowBundledPlugins` jest potrzebne; `/var/lib/grafana` na PVC albo świadomie `emptyDir` z planem na awarię grafana.com. (12)
- [ ] Air-gapped: pakiety pod platformę serwera, sha256 z API katalogu, kontrola `MANIFEST.txt`, `preinstall_disabled`, `public_key_retrieval_disabled`, `check_for_*updates = false`. (12)

## 3. Backup i DR

- [ ] Backup bazy Grafany (SQLite, PostgreSQL, MySQL) z przećwiczonym odtworzeniem.
- [ ] `secret_key` przechowywany poza instancją; bez niego `secureJsonData` po odtworzeniu jest nie do odczytania. (1)
- [ ] `grafana.ini`, katalog provisioningu i lista pluginów z wersjami w repozytorium. (11, 12)
- [ ] Dashboardy zespołów w Git Sync albo eksporcie V2. (10, 11)

## 4. Bezpieczeństwo

- [ ] Tokeny service account z czasem życia i minimalną rolą; brak tokenów admina w skryptach. (2, 10)
- [ ] Agent AI przez Grafana MCP ma osobne konto z rolą Viewer i zawężonymi narzędziami. (2)
- [ ] Anonymous access wyłączony albo z rolą Viewer i uzasadnieniem. (10)
- [ ] Snapshoty, externally shared dashboards i embedding: kto może, co ujawniają. (10)
- [ ] Każdy datasource Infinity ma Allowed hosts (SSRF). (12)
- [ ] `allow_loading_unsigned_plugins` pusta albo każdy wpis uzasadniony; przegląd razem z `/api/plugins/errors`. (12)
- [ ] Pluginy community z własnym JS rozważone dla Frontend Sandbox (public preview). (12)
- [ ] CSP włączone, najpierw w `content_security_policy_report_only`. (12)
- [ ] `permitted_provisioning_paths` i typy repozytoriów Git Sync ograniczone. (11)
- [ ] Renderer: osobna usługa, token, sieć ograniczona. (10)

## 5. Alerting

- [ ] HA Alertmanagera przy więcej niż jednej replice Grafany. (7)
- [ ] Backend historii stanu wybrany i ma retencję. (7)
- [ ] Limit wyników reguł w `[quota]` dobrany do kardynalności. (7)
- [ ] Reguły, polityki i contact pointy jako kod (provisioning albo API). (7)
- [ ] Meta-monitoring: alert na nieudane powiadomienia (`grafana_alerting_*`). (7)

## 6. Dane

- [ ] Retencja adnotacji policzona na tempo zdarzeń (`max_age` główny limit, `max_annotations_to_keep` z zapasem). (4)
- [ ] Limity SQL Expressions znane zespołom. (5)
- [ ] Datasource'y używane w alertach mają backend (Infinity: parser JSONata albo JQ). (5, 12)

## 7. Automatyzacja

- [ ] Zasoby stałe (datasource'y, foldery, app pluginy) z provisioningu z plików. (11)
- [ ] Dashboardy zespołów przez Git Sync, walidacja `gcx` w CI. (11)
- [ ] Library panels jako kod z rollbackiem. (3)
- [ ] Correlations w provisioningu. (9)

## 8. Obserwowalność samej Grafany

- [ ] Logi Grafany w Loki z możliwością filtrowania po loggerze. (4, 12)
- [ ] `/metrics` Grafany scrapowane; dashboard instancji z `grafana_plugin_build_info`, `grafana_plugin_request_total`, `grafana_alerting_*`. (7, 12)
- [ ] Alert na `grafana_plugin_build_info{signature_status!="valid"}` i na zmianę wersji pluginu po restarcie. (12)
- [ ] `/api/plugins/errors` sprawdzane po każdym wdrożeniu. (12)
- [ ] Raport Grafana Advisor przeglądany regularnie, zgłoszenia ukryte tylko z uzasadnieniem. (12)

## Trzy rzeczy na poniedziałek

| # | Punkt checklisty | Właściciel | Termin | Jak sprawdzę |
|---|---|---|---|---|
| 1 (ryzyko) | | | | |
| 2 (kod) | | | | |
| 3 (widoczność) | | | | |
