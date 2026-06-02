#!/usr/bin/env bash

# Configures the staged AIOStreams .env file.
#
# Purpose:
#   This hook applies the prompt.md AIOStreams defaults in the staged
#   AIOSTREAMS.env file: set the configured parameter values, generate
#   SECRET_KEY, optionally prompt for AIOSTREAMS_AUTH, and point
#   BUILTIN_STREMTHRU_URL at the local stremthru container when stremthru was
#   selected.
#
# Called automatically by main.sh when aiostreams is selected.
#
# Manual hook contract:
#
#   HOSTING_CONFIG_DIR=./hosting/.work/config \
#   HOSTING_SELECTED_MODULES_FILE=./hosting/.work/selected-modules.txt \
#   ./hosting/modules/aiostreams.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

MODULE_NAME=aiostreams
STREMTHRU_MODULE=stremthru
LOCAL_STREMTHRU_URL=http://stremthru:8080
read -r -d '' PARAMETERS <<'JSON' || true
{
  "TORRENTIO_URL": "https://torrentio.stremio.ru/",
  "FEATURED_TEMPLATE_IDS": "stremio.perfect.setup",
  "SEL_SYNC_ACCESS":"trusted",
  "TEMPLATE_URLS": "[\"https://numb3rs.stream/templates/AIOStreams.json\", \"https://numb3rs.stream/templates/AIOStreams-Formatter.json\"]",
  "WHITELISTED_SEL_URLS":"[\"https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-ESEs-extended.json\",\"https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-ESEs-standard.json\",\"https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-ISEs.json\",\"https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-PSEs.json\",\"https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/English/expressions.json\",\"https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/German/expressions.json\",\"https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/English/legacy-expressions.json\"]",
  "WHITELISTED_REGEX_PATTERNS_URLS":"[\"https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/English/regexes.json\",\"https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/German/regexes.json\",\"https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-excluded-regex.json\"]"
}
JSON

prompt_aiostreams_auth_value() {
  local current_auth_value="$1"
  local auth_value="${current_auth_value}"

  if is_interactive; then
    show_message \
      "AIOStreams Proxy" \
      "Optional: set built-in proxy users for AIOStreams. Use comma-separated username:password pairs, for example user1:pass1,user2:pass2."

    if prompt_yes_no "Configure AIOSTREAMS_AUTH now for the built-in proxy users?" no; then
      auth_value="$(prompt_value "Enter comma-separated username:password pairs for AIOSTREAMS_AUTH" "${current_auth_value}")"
    fi
  fi

  printf '%s' "${auth_value}"
}

build_final_parameters_json() {
  local base_parameters_json="$1"
  local secret_key_value="$2"
  local auth_value="$3"
  local enable_local_stremthru="$4"

  HOSTING_AIOSTREAMS_BASE_PARAMETERS_JSON="${base_parameters_json}" \
  HOSTING_AIOSTREAMS_SECRET_KEY="${secret_key_value}" \
  HOSTING_AIOSTREAMS_AUTH_VALUE="${auth_value}" \
  HOSTING_AIOSTREAMS_LOCAL_STREMTHRU_URL="${LOCAL_STREMTHRU_URL}" \
  HOSTING_AIOSTREAMS_ENABLE_LOCAL_STREMTHRU="${enable_local_stremthru}" \
  python3 - <<'PY'
import json
import os

values = json.loads(os.environ["HOSTING_AIOSTREAMS_BASE_PARAMETERS_JSON"])
values["SECRET_KEY"] = os.environ["HOSTING_AIOSTREAMS_SECRET_KEY"]
values["AIOSTREAMS_AUTH"] = os.environ["HOSTING_AIOSTREAMS_AUTH_VALUE"]

if os.environ.get("HOSTING_AIOSTREAMS_ENABLE_LOCAL_STREMTHRU", "").strip() == "1":
    values["BUILTIN_STREMTHRU_URL"] = os.environ["HOSTING_AIOSTREAMS_LOCAL_STREMTHRU_URL"]

print(json.dumps(values), end="")
PY
}

apply_parameters_json() {
  local file="$1"
  local parameters_json="$2"
  local parameter_rows=""
  local key="" value=""

  parameter_rows="$(
    HOSTING_AIOSTREAMS_PARAMETERS_JSON="${parameters_json}" python3 - <<'PY'
import json
import os

for key, value in json.loads(os.environ["HOSTING_AIOSTREAMS_PARAMETERS_JSON"]).items():
    print(f"{key}\t{value}")
PY
  )"

  while IFS=$'\t' read -r key value; do
    [[ -n "${key}" ]] || continue
    env_upsert_uncomment "${file}" "${key}" "${value}"
  done <<< "${parameter_rows}"
}

if [[ "${1:-}" == "--metadata" ]]; then
  printf 'scope=module\nmodule=%s\n' "${MODULE_NAME}"
  exit 0
fi

[[ -n "${HOSTING_CONFIG_DIR:-}" ]] || die "HOSTING_CONFIG_DIR is not set"
[[ -n "${HOSTING_SELECTED_MODULES_FILE:-}" ]] || die "HOSTING_SELECTED_MODULES_FILE is not set"

if ! selected_module_enabled "${MODULE_NAME}"; then
  exit 0
fi

AIOSTREAMS_ENV="${HOSTING_CONFIG_DIR}/AIOSTREAMS.env"
[[ -f "${AIOSTREAMS_ENV}" ]] || die "Missing staged AIOStreams env file: ${AIOSTREAMS_ENV}"

current_secret_key="$(env_get "${AIOSTREAMS_ENV}" SECRET_KEY || true)"
current_auth_value="$(env_get "${AIOSTREAMS_ENV}" AIOSTREAMS_AUTH || true)"

AIOSTREAMS_ENABLE_LOCAL_STREMTHRU=0
if selected_module_enabled "${STREMTHRU_MODULE}"; then
  AIOSTREAMS_ENABLE_LOCAL_STREMTHRU=1
fi

apply_parameters_json \
  "${AIOSTREAMS_ENV}" \
  "$(build_final_parameters_json \
    "${PARAMETERS}" \
    "${current_secret_key:-$(generate_secret_hex)}" \
    "$(prompt_aiostreams_auth_value "${current_auth_value}")" \
    "${AIOSTREAMS_ENABLE_LOCAL_STREMTHRU}")"

success "Configured AIOStreams defaults"
