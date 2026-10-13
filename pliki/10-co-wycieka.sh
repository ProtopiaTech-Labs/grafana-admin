#!/usr/bin/env bash
# Modul 10, cwiczenie 12: co widzi odbiorca BEZ konta.
# Wszystkie zapytania ida bez naglowka Authorization - tak jak u osoby z linkiem.
#
# Uzycie:  bash pliki/10-co-wycieka.sh <snapshot-key> <access-token-shared-dashboardu>
#   snapshot-key  - koncowka linku /dashboard/snapshot/<key>
#   access-token  - koncowka linku /public-dashboards/<token>
# Zmienne: GRAFANA_URL (domyslnie Lab wspolny)
set -uo pipefail

KEY="${1:?podaj klucz snapshotu}"
TOKEN="${2:?podaj access token shared dashboardu}"
GRAFANA_URL="${GRAFANA_URL:-https://grafana.workshop2.indexoutofrange.com}"
EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+'
NOW=$(( $(date +%s) * 1000 ))
FROM=$(( NOW - 24 * 3600 * 1000 ))
BODY=$(mktemp); trap 'rm -f "$BODY"' EXIT

call() { # $@ = argumenty curl; body -> $BODY, wypisuje kod HTTP
  local code; code=$(curl -sS -o "$BODY" -w '%{http_code}' "$@") || code="000"
  echo "  HTTP $code"
  [ "$code" = "200" ]
}

echo "== 1. Snapshot: GET /api/snapshots/<key>"
if call "$GRAFANA_URL/api/snapshots/$KEY"; then
  echo "  Adresy e-mail w zamrozonych danych (sprzed transformacji):"
  jq -r '.. | strings' "$BODY" | grep -Eo "$EMAIL" | sort -u | sed 's/^/    /' || echo "    (brak)"
  echo "  Adnotacje zamrozone w danych paneli (tekst i autor):"
  out=$(jq -c '.. | objects | select(has("schema") and has("data")) | select(any(.schema.fields[]; .name == "login"))
    | [.schema.fields[].name] as $n | .data.values as $v | range(0; $v[0] | length) as $i
    | [range(0; $n | length) | {($n[.]): $v[.][$i]}] | add | {text, login, email, z_dashboardu: .dashboardUID}' "$BODY" | sort -u)
  if [ -n "$out" ]; then echo "$out" | sed 's/^/    /'; else echo "    (brak)"; fi
fi

echo
echo "== 2. Shared dashboard: JSON dashboardu - pola zapytan po sanitizacji (usuwa tylko expr, query, rawSql)"
if call "$GRAFANA_URL/api/public/dashboards/$TOKEN"; then
  jq -c '.. | objects | select(has("refId")) | del(.datasource)' "$BODY" | sed 's/^/    /'
fi

echo
echo "== 3. Shared dashboard: wynik zapytania panelu 1 - kolumny przed transformacja Organize fields"
if call -X POST -H 'Content-Type: application/json' -d '{}' "$GRAFANA_URL/api/public/dashboards/$TOKEN/panels/1/query"; then
  jq -c '.results[].frames[] | {kolumny: [.schema.fields[].name], wiersze: (.data.values | transpose)}' "$BODY" | sed 's/^/    /'
fi

echo
echo "== 4. Shared dashboard: adnotacje z ostatnich 24 h (zapytanie po tagu przeszukuje cala organizacje)"
if call "$GRAFANA_URL/api/public/dashboards/$TOKEN/annotations?from=$FROM&to=$NOW"; then
  out=$(jq -c '.[] | {text, tags, z_dashboardu: .dashboardUID}' "$BODY")
  if [ -n "$out" ]; then echo "$out" | sed 's/^/    /'; else echo "    (brak - czy wlaczyles Display annotations?)"; fi
fi
