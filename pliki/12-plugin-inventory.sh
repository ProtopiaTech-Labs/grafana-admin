#!/usr/bin/env bash
# Modul 12, cwiczenia 03 i 05: inwentarz pluginow instancji Grafany.
# Dla kazdego pluginu: wersja, najnowsza wersja z katalogu, podpis i skad plugin
# pochodzi (core w binarce, wypieczony w obrazie + preinstall, preinstall z
# konfiguracji, pin wersji, instalacja reczna). Na koncu lista preinstall
# z /api/frontend/settings i bledy ladowania z /api/plugins/errors.
# Tylko odczyt: skrypt niczego nie instaluje ani nie zmienia.
#
# Uzycie:  bash pliki/12-plugin-inventory.sh
#          bash pliki/12-plugin-inventory.sh --json     # surowe rekordy do jq
#
# Srodowisko:
#   GRAFANA_URL     np. https://grafana.workshop2.indexoutofrange.com
#   GRAFANA_TOKEN   token service account (Authorization: Bearer)  albo
#   GRAFANA_AUTH    login:haslo (basic auth imiennego konta); token ma pierwszenstwo
#
# Klasyfikacja dla Grafany 13.2 (listy z pkg/setting/setting_plugins.go
# i scripts/catalog-plugins-defaults na tagu v13.2.1):
#   core            signature = internal (kod w binarce)
#   obraz+preinst.  jeden z 13 datasource'ow wypieczonych w data/plugins-bundled
#                   obrazu pelnego i obecnych na domyslnej liscie preinstall
#   preinst. dom.   app plugin z domyslnej listy preinstall (Drilldown, Advisor)
#   preinst. konf.  dopisany w preinstall albo preinstall_sync
#   pin @X          wpis z wersja w preinstall albo preinstall_sync
#   reczny          poza lista preinstall: UI, grafana cli albo ZIP
# /api/frontend/settings laczy listy preinstall i preinstall_sync, wiec tego,
# z ktorej listy pochodzi wpis, skrypt nie rozstrzygnie. Rozstrzyga log startu
# (dwa wpisy "Installing plugins", najpierw lista sync).
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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
get "/api/plugins?embedded=0" > "$TMP/plugins.json"
get "/api/frontend/settings"  > "$TMP/settings.json"
get "/api/plugins/errors"     > "$TMP/errors.json"

# Pliki zamiast --argjson: frontend/settings przekracza limit dlugosci argumentu w Git Bash
RECORDS=$(jq -n --slurpfile p "$TMP/plugins.json" --slurpfile s "$TMP/settings.json" '
  $p[0] as $p | $s[0] as $s
  | ["elasticsearch","prometheus","tempo","zipkin","opentsdb","stackdriver","mssql",
   "jaeger","loki","mysql","influxdb","grafana-postgresql-datasource",
   "grafana-pyroscope-datasource"] as $bundled
  | ["grafana-lokiexplore-app","grafana-pyroscope-app","grafana-exploretraces-app",
     "grafana-metricsdrilldown-app","grafana-advisor-app"] as $defapps
  | (($s.pluginCatalogPreinstalledPlugins // []) | map({key: .id, value: .version}) | from_entries) as $pre
  | $p
  | map(select(.signature != "internal" or .type == "datasource" or .type == "app"))
  | map(. as $x
      | ($pre | has($x.id)) as $inpre
      | ($pre[$x.id] // "") as $pin
      | {
          id, type,
          version: (.info.version // ""),
          latest: (.latestVersion // ""),
          hasUpdate,
          signature,
          signatureType: (.signatureType // ""),
          org: (.signatureOrg // ""),
          source: (
            if .signature == "internal" then "core"
            elif ($pin != "") then "pin @\($pin)"
            elif $inpre and ($bundled | index($x.id)) then "obraz+preinst."
            elif $inpre and ($defapps | index($x.id)) then "preinst. dom."
            elif $inpre then "preinst. konf."
            else "reczny" end)
        })
  | sort_by(.source, .type, .id)')

if [ "${1:-}" = "--json" ]; then
  echo "$RECORDS"
  exit 0
fi

{
  echo -e "id\ttyp\twersja\tnajnowsza\thasUpdate\tpodpis\tsignatureType\torganizacja\tzrodlo"
  echo "$RECORDS" | jq -r '.[] | [.id, .type, .version, .latest, (.hasUpdate|tostring),
    .signature, .signatureType, .org, .source] | map(if . == "" then "-" else . end) | @tsv'
} | column -t -s $'\t'

echo
echo "pluginCatalogPreinstalledAutoUpdate: $(jq -r '.pluginCatalogPreinstalledAutoUpdate' "$TMP/settings.json")"
echo "lista preinstall + preinstall_sync (id@wersja):"
jq -r '.pluginCatalogPreinstalledPlugins // [] | map(if .version != "" then "\(.id)@\(.version)" else .id end) | join(", ")' "$TMP/settings.json"
echo
echo "/api/plugins/errors:"
jq -c 'if length == 0 then "brak bledow ladowania" else .[] end' "$TMP/errors.json"
