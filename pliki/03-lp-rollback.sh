#!/usr/bin/env bash
# Modul 3, cwiczenie 18: "rollback" library panelu z modelu zapisanego w Git.
# Library panels nie maja historii wersji, wiec przywracasz model z pliku przez
# PATCH /api/library-elements/<uid>. Pole version to blokada optymistyczna:
# nieaktualne version -> HTTP 412.
#
# Uzycie:  bash 03-lp-rollback.sh <UID> <PLIK> [VERSION]
#   VERSION pominiete -> skrypt pobiera biezace version z Grafany (rollback przechodzi).
#   VERSION podane    -> skrypt wysyla dokladnie te wartosc (np. stara -> 412).
# PLIK: wynik `jq '.result | {uid, name, kind, folderUid, model}'` na GET /api/library-elements/<uid>.
#
# Srodowisko:
#   GRAFANA_URL   np. https://grafana.workshop2.indexoutofrange.com
#   GRAFANA_AUTH  login:haslo (basic auth imiennego konta)  albo
#   GRAFANA_TOKEN token service account (Authorization: Bearer)
set -euo pipefail

: "${GRAFANA_URL:?ustaw GRAFANA_URL}"
if [ -n "${GRAFANA_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${GRAFANA_TOKEN}")
elif [ -n "${GRAFANA_AUTH:-}" ]; then
  AUTH=(-u "${GRAFANA_AUTH}")
else
  echo "ustaw GRAFANA_AUTH=login:haslo albo GRAFANA_TOKEN" >&2; exit 1
fi

LP_UID="${1:?podaj UID library panelu}"
SRC="${2:?podaj plik z modelem}"
VERSION="${3:-}"
[ -f "$SRC" ] || { echo "brak pliku $SRC" >&2; exit 1; }

H=("${AUTH[@]}" -H "Content-Type: application/json")
CURRENT=$(curl -fsS "${H[@]}" "${GRAFANA_URL%/}/api/library-elements/${LP_UID}")

if [ -z "$VERSION" ]; then
  VERSION=$(jq -r '.result.version' <<<"$CURRENT")
fi
echo "PATCH ${LP_UID} z version=${VERSION} (biezace w Grafanie: $(jq -r '.result.version' <<<"$CURRENT"))"

# folderUid jest obowiazkowy w praktyce: PATCH bez niego przenosi panel do General,
# a razem z folderem zmieniaja sie uprawnienia. Bierzemy folder z pliku, a gdy
# plik go nie ma, zostawiamy biezacy.
FOLDER=$(jq -r --argjson cur "$CURRENT" '.folderUid // $cur.result.folderUid' "$SRC")

RESP=$(jq --argjson v "$VERSION" --arg f "$FOLDER" \
          '{name, kind, model, folderUid: $f, version: $v}' "$SRC" \
  | curl -sS -w '\n%{http_code}' -X PATCH "${H[@]}" \
      "${GRAFANA_URL%/}/api/library-elements/${LP_UID}" -d @-)
CODE="${RESP##*$'\n'}"
BODY="${RESP%$'\n'*}"
echo "HTTP ${CODE}"
jq -c 'if .result then .result | {uid, name, folderUid, version} else . end' <<<"$BODY"
[ "$CODE" = "200" ]
