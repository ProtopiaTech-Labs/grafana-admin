#!/usr/bin/env bash
# Modul 4, cwiczenie 07: adnotacja regionowa deploymentu.
# POST na starcie (punkt), PATCH z timeEnd i tagiem result:<ok|failed> na koncu (region).
#
# Uzycie:  ./04-annotate-deploy.sh <usluga> <wersja>
#          ./04-annotate-deploy.sh --cleanup [tag...]
#            usuwa Twoje adnotacje: tag owner:$OWNER plus podane tagi (AND);
#            bez tagow - wszystkie adnotacje z owner:$OWNER
#
# Srodowisko:
#   GRAFANA_URL       np. https://grafana.workshop2.indexoutofrange.com
#   GRAFANA_TOKEN     token service account (Authorization: Bearer)  albo
#   GRAFANA_AUTH      login:haslo (basic auth imiennego konta); token ma pierwszenstwo
#   OWNER             login do tagu owner:<login>; domyslnie login z GRAFANA_AUTH
#   DEPLOY_SECONDS=20 czas symulowanego deploymentu
#   DEPLOY_RESULT=ok  ok | failed
#   DASHBOARD_UID=    pusty = adnotacja organizacyjna; UID = adnotacja dashboardowa
#
# Lab wspolny to jedna organizacja: kazda adnotacja dostaje tag owner:<login>,
# a --cleanup usuwa tylko adnotacje z tym tagiem.
# Ctrl+C w trakcie "deploymentu" zostawia punkt bez timeEnd i bez tagu result
# (celowo, do cwiczenia). W prawdziwym CI krok PATCH uruchamiaj zawsze
# (GitHub Actions: if: always()), z result:failed przy bledzie.
# Tylko ASCII w tekstach: Git Bash na Windows psuje znaki spoza ASCII w JSON-ie.
set -euo pipefail

: "${GRAFANA_URL:?ustaw GRAFANA_URL}"
if [ -n "${GRAFANA_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${GRAFANA_TOKEN}")
elif [ -n "${GRAFANA_AUTH:-}" ]; then
  AUTH=(-u "${GRAFANA_AUTH}")
else
  echo "ustaw GRAFANA_TOKEN albo GRAFANA_AUTH=login:haslo" >&2; exit 1
fi
BASIC="${GRAFANA_AUTH:-}"
OWNER="${OWNER:-${BASIC%%:*}}"
[ -n "$OWNER" ] || { echo "ustaw OWNER=<login>" >&2; exit 1; }

api() { # api <metoda> <sciezka> [json]
  local out code
  out=$(curl -sS -w $'\n%{http_code}' -X "$1" "${GRAFANA_URL%/}$2" \
    "${AUTH[@]}" -H "Content-Type: application/json" \
    ${3:+-d "$3"})
  code="${out##*$'\n'}"
  if [ "$code" != "200" ]; then
    echo "HTTP ${code} ${1} ${2}: ${out%$'\n'*}" >&2
    return 1
  fi
  printf '%s\n' "${out%$'\n'*}"
}
now_ms() { echo $(( $(date +%s) * 1000 )); }

if [ "${1:-}" = "--cleanup" ]; then
  shift
  Q="tags=owner:${OWNER}"
  for t in "$@"; do Q="${Q}&tags=${t}"; done
  IDS=$(api GET "/api/annotations?${Q}&type=annotation&limit=1000" | jq -r '.[].id' | tr -d '\r')
  N=0
  for id in $IDS; do
    api DELETE "/api/annotations/${id}" >/dev/null && N=$((N + 1))
  done
  echo "usunieto: ${N} adnotacji z tagami owner:${OWNER}${*:+ $*}"
  exit 0
fi

SERVICE="${1:-cart}"
VERSION="${2:-1.0.0}"
RESULT="${DEPLOY_RESULT:-ok}"
DASHBOARD_UID="${DASHBOARD_UID:-}"

START=$(now_ms)
PAYLOAD=$(jq -nc --argjson time "$START" --arg s "$SERVICE" --arg v "$VERSION" \
  --arg o "$OWNER" --arg d "$DASHBOARD_UID" \
  '{time: $time, text: "Deploy \($s) \($v) - start",
    tags: ["deploy", "service:\($s)", "env:lab", "owner:\($o)"]}
   + (if $d == "" then {} else {dashboardUID: $d} end)')
ID=$(api POST /api/annotations "$PAYLOAD" | jq -r .id | tr -d '\r')
echo "start: annotation id=${ID}"

# --- wlasciwy deployment (tu: symulacja) ---
sleep "${DEPLOY_SECONDS:-20}"

END=$(now_ms)
PATCH=$(jq -nc --argjson timeEnd "$END" --arg s "$SERVICE" --arg v "$VERSION" \
  --arg o "$OWNER" --arg r "$RESULT" \
  '{timeEnd: $timeEnd, text: "Deploy \($s) \($v) - \($r)",
    tags: ["deploy", "service:\($s)", "env:lab", "owner:\($o)", "result:\($r)"]}')
api PATCH "/api/annotations/${ID}" "$PATCH" >/dev/null
echo "koniec: result=${RESULT}, czas trwania $(( (END - START) / 1000 )) s"

api GET "/api/annotations/${ID}" | jq -c '{id, time, timeEnd, text, tags, dashboardUID, login}'
