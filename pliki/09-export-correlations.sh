#!/usr/bin/env bash
# Moduł 9, ćwiczenie 06 — eksport korelacji do pliku provisioningu datasource'ów.
#
# UI Grafany nie eksportuje korelacji. Skrypt czyta je z HTTP API i wypisuje
# plik provisioning/datasources/*.yaml: każdy datasource źródłowy z jego sekcją
# correlations:. YAML przyjmuje JSON, więc każda korelacja to jedna linia JSON.
#
# Użycie:
#   export GRAFANA_URL=https://grafana.workshop2.indexoutofrange.com
#   export GRAFANA_AUTH='<login>:<hasło>'
#   bash pliki/09-export-correlations.sh loki-<login> prometheus-<login> > 09-moje-korelacje.yaml
#
# Co skrypt robi z każdą korelacją:
#   - zostawia targetUID, label, description, type, config (pomija uid, sourceUID, orgId, provisioned),
#   - pomija targetUID dla type: external,
#   - zamienia każde "$" na "$$" — w plikach provisioningu Grafana rozwija ${…} jako zmienne środowiskowe.
# Korelacje provisioned też trafiają do pliku (z ostrzeżeniem w komentarzu): to już jest kod.

set -euo pipefail

: "${GRAFANA_URL:?ustaw GRAFANA_URL}"
: "${GRAFANA_AUTH:?ustaw GRAFANA_AUTH=login:hasło}"
[ $# -ge 1 ] || { echo "użycie: $0 <uid źródła> [<uid źródła> ...]" >&2; exit 1; }

api() { curl -sS --fail-with-body -u "$GRAFANA_AUTH" "${GRAFANA_URL%/}$1"; }

echo "# Wygenerowane przez 09-export-correlations.sh z ${GRAFANA_URL%/} ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
echo "apiVersion: 1"
echo ""
echo "datasources:"

for src in "$@"; do
  ds=$(api "/api/datasources/uid/$src")
  corr=$(api "/api/datasources/uid/$src/correlations")

  jq -r '"  - name: \(.name | @json)\n    uid: \(.uid)\n    type: \(.type)\n    access: \(.access)\n    url: \(.url | @json)"' <<<"$ds"

  if [ "$(jq 'length' <<<"$corr")" = "0" ]; then
    echo "    # brak korelacji"
    continue
  fi

  provisioned=$(jq '[.[] | select(.provisioned)] | length' <<<"$corr")
  [ "$provisioned" = "0" ] || echo "    # uwaga: $provisioned z tych korelacji już pochodzi z provisioningu"

  echo "    correlations:"
  jq -c '
    .[]
    | {targetUID, label, description, type, config}
    | if .type == "external" then del(.targetUID) else . end
    | walk(if type == "string" then gsub("[$]"; "$$") else . end)
  ' <<<"$corr" | sed 's/^/      - /'
done
