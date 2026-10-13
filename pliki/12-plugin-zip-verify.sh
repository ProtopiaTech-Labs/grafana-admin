#!/usr/bin/env bash
# Modul 12, cwiczenie 05: pakiet pluginu do instalacji air-gapped.
# Pobiera ZIP z katalogu grafana.com dla wskazanej platformy, porownuje sha256
# z API katalogu, rozpakowuje i sprawdza pliki wobec MANIFEST.txt tak jak
# Grafana przy starcie. Na koncu przewiduje status podpisu.
#
# Uzycie:
#   bash pliki/12-plugin-zip-verify.sh <plugin-id> [wersja] [platforma]
#        wersja     domyslnie najnowsza z katalogu
#        platforma  np. linux-amd64, linux-arm64, darwin-arm64, windows-amd64;
#                   domyslnie any (pakiet z binarkami dla wszystkich platform)
#   bash pliki/12-plugin-zip-verify.sh --check <katalog-pluginu>
#        tylko kontrola rozpakowanego pluginu (po recznej zmianie plikow)
#
# Srodowisko:
#   OUT_DIR   katalog na pakiety i rozpakowane pluginy (domyslnie ./plugins-airgap)
#
# Przewidywanie wedlug pkg/plugins/manager/signature/manifest.go (v13.2.1):
#   brak MANIFEST.txt                                 -> unsigned
#   inna suma pliku, brak pliku z manifestu,
#   plik spoza manifestu, inne id/wersja niz plugin.json -> modified
#   rootUrls w manifescie bez root_url instancji      -> invalid
# Podpisu PGP manifestu skrypt nie sprawdza (gpg, patrz cwiczenie 05 ⭐Stretch).
set -euo pipefail

API=https://grafana.com/api/plugins

check_dir() {
  local dir=${1%/}
  [ -d "$dir" ] || { echo "brak katalogu $dir" >&2; return 1; }
  if [ ! -f "$dir/MANIFEST.txt" ]; then
    echo "MANIFEST.txt: brak"
    echo "PRZEWIDYWANIE: unsigned (signatureMissing); zaladuje sie tylko z allow_loading_unsigned_plugins"
    return 0
  fi

  local m sums disk listed bad=0
  # JSON manifestu to tresc miedzy linia "{" i "}" w bloku PGP SIGNED MESSAGE;
  # tr -d '\r' - Git Bash na Windows dopisuje \r do wyjscia jq
  m=$(sed -n '/^{/,/^}/p' "$dir/MANIFEST.txt" | tr -d '\r')
  echo "$m" | jq -r '"MANIFEST.txt: plugin=\(.plugin) wersja=\(.version) signatureType=\(.signatureType) signedByOrg=\(.signedByOrg) plikow=\(.files|length)"'
  echo "$m" | jq -r 'if (.rootUrls // []) | length > 0 then "rootUrls: \(.rootUrls|join(", ")) - plugin zaladuje sie tylko przy takim root_url" else empty end'

  local pj_id pj_ver
  pj_id=$(jq -r '.id' "$dir/plugin.json" | tr -d '\r')
  pj_ver=$(jq -r '.info.version' "$dir/plugin.json" | tr -d '\r')
  if [ "$pj_id" != "$(echo "$m" | jq -r .plugin)" ] || [ "$pj_ver" != "$(echo "$m" | jq -r .version)" ]; then
    echo "plugin.json ($pj_id $pj_ver) nie zgadza sie z manifestem"; bad=1
  fi

  sums=$(mktemp)
  echo "$m" | jq -r '.files | to_entries[] | "\(.value)  \(.key)"' | tr -d '\r' > "$sums"
  if ! (cd "$dir" && sha256sum -c --quiet "$sums"); then bad=1; fi

  disk=$(cd "$dir" && find . -type f ! -name MANIFEST.txt | sed 's#^\./##' | sort)
  listed=$(echo "$m" | jq -r '.files | keys[]' | tr -d '\r' | sort)
  extra=$(comm -23 <(echo "$disk") <(echo "$listed"))
  if [ -n "$extra" ]; then
    echo "pliki spoza manifestu:"; echo "$extra" | sed 's/^/  /'; bad=1
  fi
  rm -f "$sums"

  if [ "$bad" -eq 0 ]; then
    echo "PRZEWIDYWANIE: valid - wszystkie pliki zgodne z MANIFEST.txt"
  else
    echo "PRZEWIDYWANIE: modified (signatureModified); nie zaladuje sie nigdy, allowlista nie pomoze"
  fi
}

if [ "${1:-}" = "--check" ]; then
  check_dir "${2:?podaj katalog pluginu}"
  exit 0
fi

ID=${1:?podaj plugin-id, np. grafana-clock-panel}
VER=${2:-$(curl -fsS "$API/$ID" | jq -r .version)}
PLAT=${3:-any}
OUT=${OUT_DIR:-plugins-airgap}
mkdir -p "$OUT"

INFO=$(curl -fsS "$API/$ID/versions/$VER")
echo "$INFO" | jq -r '"\(.pluginSlug // "'"$ID"'") \(.version): grafanaDependency \(.grafanaDependency), signatureType \(.signatureType // "-"), pakiety: \(.packages|keys|join(", "))"'

if [ "$(echo "$INFO" | jq --arg p "$PLAT" '.packages | has($p)')" != "true" ]; then
  echo "brak pakietu $PLAT - plugin ma tylko: $(echo "$INFO" | jq -r '.packages|keys|join(", ")'); biore any" >&2
  PLAT=any
fi
EXPECTED=$(echo "$INFO" | jq -r --arg p "$PLAT" '.packages[$p].sha256')

URL="$API/$ID/versions/$VER/download"
if [ "$PLAT" != "any" ]; then URL="$URL?os=${PLAT%%-*}&arch=${PLAT#*-}"; fi
ZIP="$OUT/$ID-$VER.$PLAT.zip"
# -L: download to 302 na storage.googleapis.com - allowlista proxy musi objac oba hosty
curl -fsSL -o "$ZIP" "$URL"
ACTUAL=$(sha256sum "$ZIP" | cut -d' ' -f1)
echo "pakiet:          $ZIP ($(wc -c < "$ZIP") B)"
echo "sha256 katalog:  $EXPECTED"
echo "sha256 plik:     $ACTUAL"
[ "$EXPECTED" = "$ACTUAL" ] || { echo "SUMA SIE NIE ZGADZA - nie instaluj" >&2; exit 1; }
echo "sha256 OK"

# ZIP z katalogu ma juz katalog glowny <plugin-id>/ - rozpakowujesz do katalogu pluginow
rm -rf "${OUT:?}/$ID"
unzip -q -o "$ZIP" -d "$OUT"
ls "$OUT/$ID" | grep -E '^gpx_' | sed 's/^/binarka backendu: /' || echo "binarka backendu: brak (plugin frontend-only)"
check_dir "$OUT/$ID"
