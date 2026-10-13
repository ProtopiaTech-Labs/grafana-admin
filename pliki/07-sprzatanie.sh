#!/usr/bin/env bash
# Modul 7 (Alerting): koncowe sprzatanie obiektow uczestnika w Labie wspolnym.
# Usuwa WYLACZNIE obiekty z Twoim loginem w nazwie i silences z matcherem
# owner=<LOGIN>, w kolejnosci zaleznosci (jak w 16-ex-provisioning-i-eksport.md, "Sprzatanie modulu"):
#   1. reguly "<LOGIN>-*" / "<LOGIN>:*" w folderze uczestnicy-<LOGIN> i jego
#      podfolderach (takze grupy provisioned z provenance "api") oraz reguly
#      zaimportowane przez /api/convert/ do namespace'u "<LOGIN>-import"
#   2. inhibition rules "<LOGIN>-*", silences z matcherem owner=<LOGIN> (Unsilence)
#   3. drzewo polityk "<LOGIN>", mute timingi "<LOGIN>-*", grupy szablonow "<LOGIN>-*"
#   4. contact pointy "<LOGIN>-*"
#   5. adnotacje stanu alertow z owner=<LOGIN> w polu text
#   6. raport: Twoje reguly w Recently deleted (PURGE_DELETED=1 usuwa je na stale)
# Skrypt jest idempotentny: brak obiektu (404) nie jest bledem.
#
# Uzycie:  bash pliki/07-sprzatanie.sh
#          DRY_RUN=1 bash pliki/07-sprzatanie.sh        # tylko wypisz, co zostaloby usuniete
#          PURGE_DELETED=1 bash pliki/07-sprzatanie.sh  # dodatkowo oproznij Recently deleted
#
# Srodowisko:
#   GRAFANA_URL     np. https://grafana.workshop2.indexoutofrange.com
#   GRAFANA_AUTH    login:haslo (basic auth imiennego konta)  albo
#   GRAFANA_TOKEN   token service account z rola Admin (Authorization: Bearer); token ma pierwszenstwo
#   LOGIN           Twoj login w labie (np. user7)
set -euo pipefail

: "${GRAFANA_URL:?ustaw GRAFANA_URL}"
LOGIN="${LOGIN:-}"
if [ -z "$LOGIN" ]; then
  echo "BLAD: pusty LOGIN - odmawiam (pusty login pasowalby do obiektow wszystkich uczestnikow)" >&2
  exit 1
fi
if ! [[ "$LOGIN" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "BLAD: LOGIN '$LOGIN' moze zawierac tylko litery, cyfry, _ i -" >&2
  exit 1
fi
if [ -n "${GRAFANA_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${GRAFANA_TOKEN}")
elif [ -n "${GRAFANA_AUTH:-}" ]; then
  AUTH=(-u "${GRAFANA_AUTH}")
else
  echo "ustaw GRAFANA_AUTH=login:haslo albo GRAFANA_TOKEN" >&2; exit 1
fi
command -v jq >/dev/null || { echo "BLAD: brak jq w PATH" >&2; exit 1; }

DRY_RUN="${DRY_RUN:-0}"
PURGE_DELETED="${PURGE_DELETED:-0}"
URL="${GRAFANA_URL%/}"
FOLDER="uczestnicy-${LOGIN}"
IMPORT_NS="${LOGIN}-import"
NOTIF="/apis/notifications.alerting.grafana.app/v1beta1/namespaces/default"
ERRORS=0

gf() { # gf <method> <path> [extra curl args...] -> GF_CODE, GF_BODY
  local method="$1" path="$2" out
  shift 2
  out=$(curl -sS "${AUTH[@]}" -X "$method" -w $'\n%{http_code}' "$@" "${URL}${path}") || {
    GF_CODE=000; GF_BODY="curl error"; return 0; }
  GF_CODE="${out##*$'\n'}"
  GF_BODY="${out%$'\n'*}"
}

fetch() { # fetch <path> <opis> -> JSON (pusty przy bledzie, blad liczony w ERRORS)
  gf GET "$1"
  if [[ "$GF_CODE" == 200 || "$GF_CODE" == 202 ]]; then
    JSON="$GF_BODY"
  else
    echo "  UWAGA: $2 -> HTTP $GF_CODE ${GF_BODY:0:200}" >&2
    ERRORS=$((ERRORS + 1))
    JSON=""
  fi
}

del() { # del <opis> <path> [extra curl args...]
  local what="$1" path="$2"
  shift 2
  if [ "$DRY_RUN" = 1 ]; then
    echo "  [dry-run] DELETE ${path}  (${what})"
    return 0
  fi
  gf DELETE "$path" "$@"
  case "$GF_CODE" in
    200|202|204) echo "  usuniete: ${what}" ;;
    404)         echo "  brak (juz usuniete): ${what}" ;;
    *)           echo "  BLAD: ${what} -> HTTP ${GF_CODE} ${GF_BODY:0:300}" >&2
                 ERRORS=$((ERRORS + 1)) ;;
  esac
}

uri() { jq -rn --arg v "$1" '$v | @uri'; }

echo "Sprzatanie modulu 7 dla ${LOGIN} na ${URL}$([ "$DRY_RUN" = 1 ] && echo ' (DRY_RUN)')"

# --- 1. Reguly ---------------------------------------------------------------
echo "1. Reguly"
# Import z /api/convert/: namespace = podfolder "<LOGIN>-import" w uczestnicy-<LOGIN>.
# Reguly z provenance converted_prometheus usuwa tylko ta sciezka (provisioning API daje 409).
del "namespace importu ${IMPORT_NS}" "/api/convert/prometheus/config/v1/rules/$(uri "$IMPORT_NS")" \
  -H "X-Grafana-Alerting-Folder-UID: ${FOLDER}"

# Folder uczestnika i jego podfoldery.
FOLDERS=$(jq -cn --arg f "$FOLDER" '[$f]')
fetch "/api/folders?parentUid=${FOLDER}&limit=1000" "podfoldery ${FOLDER}"; SUB="$JSON"
if [ -n "$SUB" ]; then
  FOLDERS=$(jq -c --argjson base "$FOLDERS" '$base + [.[].uid]' <<<"$SUB")
fi

fetch "/api/v1/provisioning/alert-rules" "lista regul"; RULES="$JSON"
if [ -n "$RULES" ]; then
  LIST=$(jq -r --argjson folders "$FOLDERS" --arg l "$LOGIN" '
      .[] | select(.folderUID as $f | $folders | index($f))
          | select(.title | startswith($l + "-") or startswith($l + ":"))
          | [.uid, .title, .ruleGroup, (.provenance // "")] | @tsv' <<<"$RULES" | tr -d '\r')
  while IFS=$'\t' read -r uid title group prov; do
    [ -n "$uid" ] || continue
    del "regula ${title} (grupa ${group}${prov:+, provenance ${prov}})" "/api/v1/provisioning/alert-rules/${uid}"
  done <<<"$LIST"
fi

# --- 2. Inhibition rules i silences -------------------------------------------
echo "2. Inhibition rules i silences"
fetch "${NOTIF}/inhibitionrules" "lista inhibition rules"; INH="$JSON"
if [ -n "$INH" ]; then
  LIST=$(jq -r --arg l "$LOGIN-" '.items[]?.metadata.name | select(startswith($l))' <<<"$INH" | tr -d '\r')
  while read -r name; do
    [ -n "$name" ] || continue
    del "inhibition rule ${name}" "${NOTIF}/inhibitionrules/${name}"
  done <<<"$LIST"
fi

fetch "/api/alertmanager/grafana/api/v2/silences" "lista silences"; SIL="$JSON"
if [ -n "$SIL" ]; then
  LIST=$(jq -r --arg l "$LOGIN" '
      .[] | select(.status.state != "expired")
          | select(any(.matchers[]; .name == "owner" and .value == $l
                                    and (.isRegex | not) and (.isEqual != false)))
          | [.id, (.comment // "")] | @tsv' <<<"$SIL" | tr -d '\r')
  while IFS=$'\t' read -r id comment; do
    [ -n "$id" ] || continue
    del "silence ${id} (${comment})" "/api/alertmanager/grafana/api/v2/silence/${id}"
  done <<<"$LIST"
fi

# --- 3. Drzewo polityk, mute timingi, szablony --------------------------------
echo "3. Drzewo polityk, mute timingi, szablony"
del "drzewo polityk ${LOGIN}" "${NOTIF}/routingtrees/${LOGIN}"

fetch "/api/v1/provisioning/mute-timings" "lista mute timingow"; MT="$JSON"
if [ -n "$MT" ]; then
  LIST=$(jq -r --arg l "$LOGIN-" '.[]?.name | select(startswith($l))' <<<"$MT" | tr -d '\r')
  while read -r name; do
    [ -n "$name" ] || continue
    del "mute timing ${name}" "/api/v1/provisioning/mute-timings/$(uri "$name")"
  done <<<"$LIST"
fi

fetch "/api/v1/provisioning/templates" "lista grup szablonow"; TPL="$JSON"
if [ -n "$TPL" ]; then
  LIST=$(jq -r --arg l "$LOGIN-" '.[]?.name | select(startswith($l))' <<<"$TPL" | tr -d '\r')
  while read -r name; do
    [ -n "$name" ] || continue
    del "grupa szablonow ${name}" "/api/v1/provisioning/templates/$(uri "$name")"
  done <<<"$LIST"
fi

# --- 4. Contact pointy ---------------------------------------------------------
echo "4. Contact pointy"
fetch "/api/v1/provisioning/contact-points" "lista contact pointow"; CP="$JSON"
if [ -n "$CP" ]; then
  # Jedna pozycja = jedna integracja; contact point znika razem z ostatnia.
  LIST=$(jq -r --arg l "$LOGIN-" '.[] | select(.name | startswith($l)) | [.uid, .name, .type] | @tsv' <<<"$CP" | tr -d '\r')
  while IFS=$'\t' read -r uid name type; do
    [ -n "$uid" ] || continue
    del "contact point ${name} (${type}, uid ${uid})" "/api/v1/provisioning/contact-points/${uid}"
  done <<<"$LIST"
fi

# --- 5. Adnotacje stanu alertow ------------------------------------------------
echo "5. Adnotacje stanu alertow (owner=${LOGIN})"
# Tekst adnotacji: "<tytul reguly> {etykieta=wartosc, owner=<LOGIN>, ...} - <wartosci>".
fetch "/api/annotations?type=alert&limit=100000" "lista adnotacji alertowych"; ANN="$JSON"
if [ -n "$ANN" ]; then
  LIST=$(jq -r --arg re "[{ ]owner=${LOGIN}[,}]" '.[] | select((.text // "") | test($re)) | [.id, .text] | @tsv' <<<"$ANN" | tr -d '\r')
  while IFS=$'\t' read -r id text; do
    [ -n "$id" ] || continue
    del "adnotacja ${id}: ${text:0:80}" "/api/annotations/${id}"
  done <<<"$LIST"
fi

# --- 6. Recently deleted -------------------------------------------------------
echo "6. Recently deleted"
gf GET "/api/ruler/grafana/api/v1/rules?deleted=true"
if [ "$GF_CODE" = 200 ]; then
  TRASH=$(jq -r --arg l "$LOGIN" '
      [.[][]?.rules[]?.grafana_alert] | .[]
      | select(.title | startswith($l + "-") or startswith($l + ":"))
      | [.guid, .title, .updated] | @tsv' <<<"$GF_BODY" | tr -d '\r')
  if [ -z "$TRASH" ]; then
    echo "  brak Twoich regul w Recently deleted"
  else
    while IFS=$'\t' read -r guid title updated; do
      [ -n "$guid" ] || continue
      if [ "$PURGE_DELETED" = 1 ]; then
        del "na stale: ${title} (usunieta ${updated})" "/api/ruler/grafana/api/v1/trash/rule/guid/${guid}"
      else
        echo "  zostaje w Recently deleted: ${title} (usunieta ${updated}) - Permanently delete w UI albo PURGE_DELETED=1"
      fi
    done <<<"$TRASH"
  fi
else
  echo "  UWAGA: Recently deleted -> HTTP ${GF_CODE} (lista tylko dla roli Admin) ${GF_BODY:0:200}" >&2
fi

echo "Zostaje: folder ${FOLDER}, pusty podfolder ${IMPORT_NS} (jesli byl), sesja webhook-testera (usun w jego UI)."
if [ "$ERRORS" -gt 0 ]; then
  echo "Zakonczone z bledami: ${ERRORS}. Popraw kolejnosc albo usun obiekt w UI i uruchom skrypt ponownie." >&2
  exit 1
fi
echo "Gotowe."
