#!/usr/bin/env bash
# Modul 4, cwiczenie 09 (Stretch: eksperyment z agresywna retencja).
# Generator adnotacji do testu retencji na WLASNEJ instancji testowej, na ktorej
# mozesz zmienic grafana.ini i zrestartowac Grafane. W Labie wspolnym go nie
# uruchamiasz: tam retencji nie zmienisz, a cwiczenie 09 liczy istniejace adnotacje.
#
# Tworzy N adnotacji organizacyjnych z tagiem "bulk" i M dashboardowych na
# dashboardzie m04-retencja-<OWNER> (zaklada go, jesli nie istnieje), wszystkie
# z tagiem owner:<OWNER>, potem liczy klasy przez 04-annotation-klasy.sh.
#
# Uzycie:  ./04-bulk-annotations.sh [N=20] [M=5]
#          ./04-bulk-annotations.sh --cleanup   # usun adnotacje bulk/bulk-dash z owner:<OWNER> i dashboard
#
# Srodowisko:
#   GRAFANA_URL     adres instancji testowej
#   GRAFANA_TOKEN   token service account (Authorization: Bearer)  albo
#   GRAFANA_AUTH    login:haslo (basic auth); token ma pierwszenstwo
#   OWNER           login do tagu owner:<login>; domyslnie login z GRAFANA_AUTH
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
DASH="m04-retencja-${OWNER}"

api() { # api <metoda> <sciezka> [json]
  curl -fsS -X "$1" "${GRAFANA_URL%/}$2" \
    "${AUTH[@]}" -H "Content-Type: application/json" \
    ${3:+-d "$3"}
}

if [ "${1:-}" = "--cleanup" ]; then
  N=0
  for tag in bulk bulk-dash; do
    for id in $(api GET "/api/annotations?tags=owner:${OWNER}&tags=${tag}&type=annotation&limit=1000" \
                | jq -r '.[].id' | tr -d '\r'); do
      api DELETE "/api/annotations/${id}" >/dev/null && N=$((N + 1))
    done
  done
  api DELETE "/api/dashboards/uid/${DASH}" >/dev/null 2>&1 || true
  echo "usunieto: ${N} adnotacji i dashboard ${DASH}"
  exit 0
fi

N="${1:-20}"
M="${2:-5}"
NOW=$(( $(date +%s) * 1000 ))

api POST /api/dashboards/db \
  "{\"overwrite\":true,\"dashboard\":{\"uid\":\"${DASH}\",\"title\":\"M04 ${OWNER} retencja\",\"panels\":[]}}" >/dev/null

for i in $(seq 1 "$N"); do
  api POST /api/annotations "$(jq -nc --argjson t "$(( NOW - (N - i) * 60000 ))" --arg i "$i" --arg o "$OWNER" \
    '{time: $t, text: "bulk org \($i)", tags: ["bulk", "owner:\($o)"]}')" >/dev/null
done
for i in $(seq 1 "$M"); do
  api POST /api/annotations "$(jq -nc --argjson t "$(( NOW - (M - i) * 60000 ))" --arg i "$i" --arg o "$OWNER" --arg d "$DASH" \
    '{dashboardUID: $d, time: $t, text: "bulk dashboard \($i)", tags: ["bulk-dash", "owner:\($o)"]}')" >/dev/null
done

echo "utworzono: ${N} organizacyjnych (tag bulk), ${M} dashboardowych (${DASH}), $(date +%T)"
bash "$(dirname "$0")/04-annotation-klasy.sh"
