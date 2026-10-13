#!/usr/bin/env bash
# Modul 6, cwiczenie 08: zespoly, prywatny folder, home dashboard per zespol
# i dashboard "Moje uslugi" w Labie wspolnym. Rozwiazanie wzorcowe i sprzatanie.
#
# Uzycie:  ./06-zespoly-i-foldery.sh setup     # zaklada wszystko (idempotentnie)
#          ./06-zespoly-i-foldery.sh cleanup   # usuwa wszystko, co zaklada setup
#
# setup:
#   - zespoly <LOGIN>-platnosci (czlonek <LOGIN>-test1) i <LOGIN>-sklep (<LOGIN>-test2),
#     bez Ciebie (Grafana dopisuje tworce zespolu jako Admina zespolu)
#   - folder w korzeniu "<LOGIN> · Płatności" (uid <LOGIN>-platnosci) z jednym wpisem
#     uprawnien: zespol <LOGIN>-platnosci -> View (lista zastepuje domyslne wpisy rol)
#   - dashboard "M06 Płatności — <LOGIN>" (uid <LOGIN>-platnosci-home) w tym folderze
#   - dashboard pliki/06-dashboard-per-zespol.json (uid <LOGIN>-moje-uslugi)
#     w folderze Uczestnicy/<LOGIN>
#   - preferencje zespolow: platnosci -> home <LOGIN>-platnosci-home, Europe/Warsaw;
#     sklep -> home <LOGIN>-moje-uslugi
#
# Srodowisko:
#   GRAFANA_URL   np. https://grafana.workshop2.indexoutofrange.com
#   GRAFANA_AUTH  login:haslo (basic auth imiennego konta)  albo
#   GRAFANA_TOKEN token service account z rola Admin (Authorization: Bearer)
#   LOGIN         Twoj login w labie (np. user7)
set -euo pipefail

: "${GRAFANA_URL:?ustaw GRAFANA_URL}"
: "${LOGIN:?ustaw LOGIN}"
if [ -n "${GRAFANA_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${GRAFANA_TOKEN}")
elif [ -n "${GRAFANA_AUTH:-}" ]; then
  AUTH=(-u "${GRAFANA_AUTH}")
else
  echo "ustaw GRAFANA_AUTH=login:haslo albo GRAFANA_TOKEN" >&2; exit 1
fi

MODE="${1:-setup}"
DIR="$(cd "$(dirname "$0")" && pwd)"
URL="${GRAFANA_URL%/}"
V2="/apis/dashboard.grafana.app/v2/namespaces/default/dashboards"
TEAM_PAY="${LOGIN}-platnosci"
TEAM_SHOP="${LOGIN}-sklep"
FOLDER_PAY="${LOGIN}-platnosci"
DASH_PAY="${LOGIN}-platnosci-home"
DASH_MINE="${LOGIN}-moje-uslugi"

gf() { # gf <method> <path> [json] -> GF_CODE, GF_BODY
  # Cialo idzie przez stdin, nie jako argument: curl w Git Bash na Windows
  # zamienia polskie znaki z argumentow na znaki zastepcze.
  local out
  out=$(printf '%s' "${3:-}" | curl -sS "${AUTH[@]}" -H 'Content-Type: application/json' -X "$1" \
        -w $'\n%{http_code}' "${URL}$2" ${3:+--data-binary @-})
  GF_CODE="${out##*$'\n'}"
  GF_BODY="${out%$'\n'*}"
}
must() { # must <ok-codes-regex> <opis>
  [[ "$GF_CODE" =~ ^($1)$ ]] || { echo "BLAD: $2 -> HTTP $GF_CODE $GF_BODY" >&2; exit 1; }
}
team_id() { # team_id <nazwa> -> id albo pusto
  gf GET "/api/teams/search?name=$1"; must 200 "szukanie zespolu $1"
  jq -r --arg n "$1" '.teams[] | select(.name == $n) | .id' <<<"$GF_BODY" | tr -d '\r'
}
user_id() { # user_id <login> -> id (uzytkownik organizacji)
  gf GET "/api/org/users/lookup?query=$1&limit=20"; must 200 "szukanie uzytkownika $1"
  jq -r --arg l "$1" '.[] | select(.login == $l) | .userId' <<<"$GF_BODY" | tr -d '\r'
}

ensure_team() { # ensure_team <nazwa> <login-czlonka>
  local id member me
  id=$(team_id "$1")
  if [ -z "$id" ]; then
    gf POST /api/teams "$(jq -cn --arg n "$1" '{name: $n}')"; must 200 "tworzenie zespolu $1"
    id=$(jq -r '.teamId' <<<"$GF_BODY")
  fi
  member=$(user_id "$2")
  [ -n "$member" ] || { echo "BLAD: brak uzytkownika $2 w organizacji" >&2; exit 1; }
  gf POST "/api/teams/$id/members" "{\"userId\": $member}"; must '200|400|409' "dodanie $2 do $1"
  # Tworca zespolu jest jego czlonkiem (Admin zespolu) - usun siebie, zeby
  # preferencje zespolu nie dotyczyly Ciebie.
  gf GET /api/user
  if [ "$GF_CODE" = "200" ] && [ "$(jq -r '.login' <<<"$GF_BODY")" = "$LOGIN" ]; then
    me=$(jq -r '.id' <<<"$GF_BODY")
    gf DELETE "/api/teams/$id/members/$me"; must '200|404|400' "usuniecie siebie z $1"
  fi
  echo "zespol $1 (id $id): czlonek $2" >&2
  printf '%s' "$id"
}

payments_dashboard() {
  jq -n --arg name "$DASH_PAY" --arg folder "$FOLDER_PAY" --arg login "$LOGIN" '{
    apiVersion: "dashboard.grafana.app/v2", kind: "Dashboard",
    metadata: {name: $name, annotations: {"grafana.app/folder": $folder}},
    spec: {
      title: ("M06 Płatności — " + $login), tags: ["szkolenie", "modul-06"],
      description: "Modul 6, cwiczenie 08: home dashboard zespolu platnosci w prywatnym folderze.",
      editable: true, cursorSync: "Off", preload: false, links: [], annotations: [], variables: [],
      # "browser" jak po zapisie z UI (cwiczenie, krok z dashboardem platnosci);
      # strefe zespolu widac na <LOGIN>-moje-uslugi, ktory ma pusty timezone.
      timeSettings: {timezone: "browser", from: "now-1h", to: "now", autoRefresh: "",
                     autoRefreshIntervals: ["30s", "1m", "5m"], hideTimepicker: false, fiscalYearStartMonth: 0},
      elements: {"platnosci": {kind: "Panel", spec: {id: 1, title: "payment: ruch i błędy", links: [],
        data: {kind: "QueryGroup", spec: {transformations: [], queryOptions: {}, queries: [
          {kind: "PanelQuery", spec: {refId: "A", hidden: false, query: {kind: "DataQuery", group: "prometheus",
            version: "v0", datasource: {name: "prometheus"}, spec: {legendFormat: "{{status_code}}",
            expr: "sum by (status_code) (rate(traces_spanmetrics_calls_total{service_name=\"payment\", span_kind=\"SPAN_KIND_SERVER\"}[$__rate_interval]))"}}}}]}},
        vizConfig: {kind: "VizConfig", group: "timeseries", version: "13.2.1",
          spec: {options: {}, fieldConfig: {defaults: {unit: "reqps"}, overrides: []}}}}}},
      layout: {kind: "AutoGridLayout", spec: {maxColumnCount: 1, columnWidthMode: "standard",
        rowHeightMode: "tall", fillScreen: false,
        items: [{kind: "AutoGridLayoutItem", spec: {element: {kind: "ElementReference", name: "platnosci"}}}]}}
    }}'
}

ensure_dashboard() { # ensure_dashboard <name> <json>
  gf GET "$V2/$1"
  if [ "$GF_CODE" = "200" ]; then echo "dashboard $1 juz jest" >&2; return 0; fi
  gf POST "$V2" "$2"; must '200|201' "tworzenie dashboardu $1"
  echo "dashboard $1 utworzony" >&2
}

setup() {
  local pay shop
  pay=$(ensure_team "$TEAM_PAY" "${LOGIN}-test1")
  shop=$(ensure_team "$TEAM_SHOP" "${LOGIN}-test2")

  gf GET "/api/folders/$FOLDER_PAY"
  if [ "$GF_CODE" != "200" ]; then
    gf POST /api/folders "$(jq -cn --arg u "$FOLDER_PAY" --arg t "$LOGIN · Płatności" '{uid: $u, title: $t}')"
    must 200 "tworzenie folderu $FOLDER_PAY"
  fi
  # Nowy folder ma wpisy rol Editor -> Edit i Viewer -> View. POST zastepuje cala
  # liste: zostaje tylko zespol (Admin organizacji i tak widzi wszystko).
  gf POST "/api/folders/$FOLDER_PAY/permissions" "{\"items\": [{\"teamId\": $pay, \"permission\": 1}]}"
  must 200 "uprawnienia folderu $FOLDER_PAY"
  echo "folder $FOLDER_PAY: tylko zespol $TEAM_PAY (View)" >&2

  ensure_dashboard "$DASH_PAY" "$(payments_dashboard)"
  ensure_dashboard "$DASH_MINE" "$(sed "s/LOGIN/$LOGIN/g" "$DIR/06-dashboard-per-zespol.json")"

  gf PUT "/api/teams/$pay/preferences" "$(jq -cn --arg d "$DASH_PAY" '{homeDashboardUID: $d, timezone: "Europe/Warsaw"}')"
  must 200 "preferencje $TEAM_PAY"
  gf PUT "/api/teams/$shop/preferences" "$(jq -cn --arg d "$DASH_MINE" '{homeDashboardUID: $d}')"
  must 200 "preferencje $TEAM_SHOP"
  echo "preferencje: $TEAM_PAY -> $DASH_PAY (Europe/Warsaw), $TEAM_SHOP -> $DASH_MINE" >&2
}

cleanup() {
  local id name
  for name in "$TEAM_PAY" "$TEAM_SHOP"; do
    id=$(team_id "$name")
    if [ -n "$id" ]; then gf DELETE "/api/teams/$id"; must '200|404' "usuniecie zespolu $name"; echo "usuniety zespol $name" >&2; fi
  done
  for name in "$DASH_MINE" "$DASH_PAY"; do
    gf DELETE "$V2/$name"; must '200|404' "usuniecie dashboardu $name"
  done
  # Podfolder z proby w kroku 2 cwiczenia i prywatny folder w korzeniu.
  for name in "${LOGIN}-platnosci-sub" "$FOLDER_PAY"; do
    gf DELETE "/api/folders/$name"; must '200|404' "usuniecie folderu $name"
  done
  echo "posprzatane: zespoly, foldery i dashboardy cwiczenia 08 dla $LOGIN" >&2
}

case "$MODE" in
  setup) setup ;;
  cleanup) cleanup ;;
  *) echo "uzycie: $0 setup|cleanup" >&2; exit 1 ;;
esac
