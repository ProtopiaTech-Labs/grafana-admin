#!/usr/bin/env bash
# Modul 4, cwiczenie 09: rozklad adnotacji na klasy retencji przez API
# i przewidywanie, co usunie najblizszy przebieg zadania czyszczacego.
# Zamiennik zapytania 04-annotation-klasy.sql, gdy nie masz dostepu do bazy Grafany.
# Tylko odczyt: skrypt niczego nie tworzy ani nie usuwa.
#
# Uzycie:  ./04-annotation-klasy.sh
#          API_KEEP=5 DASH_MAX_AGE=5m ./04-annotation-klasy.sh   # "co by bylo, gdyby"
#
# Srodowisko:
#   GRAFANA_URL     np. https://grafana.workshop2.indexoutofrange.com
#   GRAFANA_TOKEN   token service account (Authorization: Bearer)  albo
#   GRAFANA_AUTH    login:haslo (basic auth imiennego konta); token ma pierwszenstwo
#   Retencja do symulacji, domyslnie wartosci Labu wspolnego; puste albo 0 = bez limitu.
#   max_age w formacie grafana.ini (30m, 6h, 90d, 2w, 1M, 1y):
#   DASH_MAX_AGE=90d  DASH_KEEP=10000    [annotations.dashboard]
#   API_MAX_AGE=90d   API_KEEP=10000     [annotations.api]
#   ALERT_MAX_AGE=30d ALERT_KEEP=10000   [unified_alerting.state_history.annotations]
#
# Klasy jak w zadaniu czyszczacym: alertowe (alertId <> 0), dashboardowe
# (dashboardUID niepuste), organizacyjne (reszta). max_age liczy od pola created,
# limit zostawia rekordy o najwyzszym id. API zwraca tylko adnotacje, ktore wolno
# Ci czytac: adnotacje usunietych dashboardow sa w tabeli, ale nie w API, wiec
# wynik to dolna granica. Skrypt liczy wedlug dokumentacji; samo
# ALERT_KEEP przy pustym ALERT_MAX_AGE Grafana ignoruje (lekcja 08).
set -euo pipefail

: "${GRAFANA_URL:?ustaw GRAFANA_URL}"
if [ -n "${GRAFANA_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${GRAFANA_TOKEN}")
elif [ -n "${GRAFANA_AUTH:-}" ]; then
  AUTH=(-u "${GRAFANA_AUTH}")
else
  echo "ustaw GRAFANA_TOKEN albo GRAFANA_AUTH=login:haslo" >&2; exit 1
fi

get() { curl -fsS "${AUTH[@]}" "${GRAFANA_URL%/}$1"; }

ALL=$( { get "/api/annotations?type=annotation&limit=100000"; echo
          get "/api/annotations?type=alert&limit=100000"; } | jq -s 'add')

jq -r --argjson now "$(( $(date +%s) * 1000 ))" \
  --arg da "${DASH_MAX_AGE-90d}" --arg dk "${DASH_KEEP-10000}" \
  --arg aa "${API_MAX_AGE-90d}" --arg ak "${API_KEEP-10000}" \
  --arg la "${ALERT_MAX_AGE-30d}" --arg lk "${ALERT_KEEP-10000}" '
  def klasa: if (.alertId // 0) != 0 then "alertowe"
             elif (.dashboardUID // "") != "" then "dashboardowe"
             else "organizacyjne" end;
  def day: 86400000;
  def ts: (. / 1000 | floor | todate);
  def age_ms:  # "90d" -> ms; "" albo "0" -> 0 (bez limitu)
    if . == "" or . == "0" then 0
    else capture("^(?<n>[0-9]+)(?<u>[smhdwMy])$")
      | (.n | tonumber) * ({"s": 1000, "m": 60000, "h": 3600000, "d": 86400000,
                             "w": 604800000, "M": 2592000000, "y": 31536000000}[.u])
    end;
  def keep: if . == "" then 0 else tonumber end;
  {"dashboardowe": [$da, $dk], "organizacyjne": [$aa, $ak], "alertowe": [$la, $lk]} as $ret
  | (["klasa", "liczba", "najstarsza (created)", "najnowsza (created)", "/dobe (7 dni)",
      "max_age", "usunie wiek", "keep", "usunie limit", "pierwsze wygasniecie"] | @tsv),
    (["organizacyjne", "dashboardowe", "alertowe"][] as $k
     | [ .[] | select(klasa == $k) ] as $a
     | ($ret[$k][0] | age_ms) as $age
     | ($ret[$k][1] | keep) as $keep
     | ($a | map(.created) | sort) as $c
     | [ $k,
         ($a | length),
         (if $c == [] then "-" else ($c[0] | ts) end),
         (if $c == [] then "-" else ($c[-1] | ts) end),
         ($c | map(select(. > $now - 7 * day)) | length / 7 * 10 | round / 10),
         (if $age == 0 then "-" else $ret[$k][0] end),
         (if $age == 0 then "-" else ($c | map(select(. < $now - $age)) | length) end),
         (if $keep == 0 then "-" else $keep end),
         (if $keep == 0 then "-" else ([($a | length) - $keep, 0] | max) end),
         (if $age == 0 or $c == [] then "-" else ($c[0] + $age | ts) end)
       ] | @tsv)
  ' <<<"$ALL" | column -t -s $'\t'
