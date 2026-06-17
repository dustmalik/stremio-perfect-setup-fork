#!/usr/bin/env bash

# PostgreSQL provisioning hook for the AIO addon family.
#
# Purpose:
#   This hook runs when any selected module is aiomanager, aiometadata, or
#   aiostreams. A PostgreSQL database (Supabase, Neon, or any other Postgres
#   provider) is offered to the user as an alternative to each addon's upstream
#   local SQLite default. If the user provides a Postgres connection string, the
#   hook creates per-addon schemas and roles, then writes generated Postgres URLs
#   into the staged addon .env files.
#
# Manual hook contract:
#
#   HOSTING_CONFIG_DIR=./hosting/.work/config \
#   HOSTING_SELECTED_MODULES_FILE=./hosting/.work/selected-modules.txt \
#
# Expected environment variables (from module_get_param):
#   POSTGRES_CONNECTION_STRING - PostgreSQL connection string (e.g. a Supabase
#     session pooler URI or a Neon pooled connection string)
#   POSTGRES_DB_PASSWORD - database password; only needed when the connection
#     string contains the [YOUR-PASSWORD] placeholder (as Supabase's does).
#     When the string already embeds the password (as Neon's does) it is used
#     directly and no password prompt is shown.
#
# Skip behavior:
#   If no connection string is supplied, the hook exits without modifying
#   database variables and the addons keep their default local SQLite setup.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
ensure_dialog_ui "PostgreSQL setup"

MODULE_NAME="postgres"
SUPPORTED_ADDONS=(aiomanager aiometadata aiostreams)
declare -A DATABASE_URL_KEYS=(
  [aiomanager]=DATABASE_URL
  [aiometadata]=DATABASE_URI
  [aiostreams]=DATABASE_URI
)
declare -A EXTRA_ENV_ASSIGNMENTS=(
  [aiomanager]="DB_TYPE=postgres"
)
POSTGRES_CONNECTION_STRING_LABEL="Paste a PostgreSQL connection string (Supabase, Neon, or any Postgres) that has enough access to create addon schemas and roles [POSTGRES_CONNECTION_STRING]"
POSTGRES_DB_PASSWORD_LABEL="Enter the database password so schema creation can authenticate successfully [POSTGRES_DB_PASSWORD]"

if [[ "${1:-}" == "--metadata" ]]; then
  printf 'scope=all\ndependencies=aiomanager,aiometadata,aiostreams\norder=110\n'
  printf 'param=connection_string|string|false|%s\n' "${POSTGRES_CONNECTION_STRING_LABEL}"
  printf 'param=db_password|secret|false|%s\n' "${POSTGRES_DB_PASSWORD_LABEL}"
  exit 0
fi

[[ -n "${HOSTING_CONFIG_DIR:-}" ]] || die "HOSTING_CONFIG_DIR is not set"
[[ -n "${HOSTING_SELECTED_MODULES_FILE:-}" ]] || die "HOSTING_SELECTED_MODULES_FILE is not set"

simulate_schema_rows() {
  local base_connection_string="$1"
  shift
  HOSTING_SIMULATED_BASE_CONNECTION="${base_connection_string}" \
  HOSTING_SIMULATED_ADDONS="$(printf '%s\n' "$@")" \
  python3 - <<'PY'
import os
import re

base = os.environ["HOSTING_SIMULATED_BASE_CONNECTION"]
addons = [line.strip() for line in os.environ.get("HOSTING_SIMULATED_ADDONS", "").splitlines() if line.strip()]

match = re.match(r'^([^:]+://)([^:]+)(:.*)$', base)
if not match:
    raise SystemExit("Could not extract the database user from the connection string")

prefix, parsed_user, suffix = match.groups()
for addon in addons:
    clean_name = re.sub(r'[^a-zA-Z0-9_]', '_', addon).lower()
    if re.match(r'^[0-9]', clean_name):
        clean_name = f'addon_{clean_name}'
    schema_name = clean_name
    role_name = f'{clean_name}_user'
    if '.' in parsed_user:
        replacement_user = role_name + parsed_user[parsed_user.index('.'):]
    else:
        replacement_user = role_name
    addon_connection = f'{prefix}{replacement_user}{suffix}'
    print('\t'.join([addon, schema_name, role_name, addon_connection]))
PY
}

selected_addons=()
if [[ -n "${HOSTING_MODULE_HOOK_TARGETS_FILE:-}" && -f "${HOSTING_MODULE_HOOK_TARGETS_FILE}" ]]; then
  while IFS= read -r module; do
    if array_contains "${module}" "${SUPPORTED_ADDONS[@]}" && selected_module_enabled "${module}"; then
      selected_addons+=("${module}")
    fi
  done < <(read_lines_file "${HOSTING_MODULE_HOOK_TARGETS_FILE}")
else
  while IFS= read -r module; do
    if array_contains "${module}" "${SUPPORTED_ADDONS[@]}"; then
      selected_addons+=("${module}")
    fi
  done < <(read_lines_file "${HOSTING_SELECTED_MODULES_FILE}")
fi

(( ${#selected_addons[@]} > 0 )) || exit 0

connection_string=""
database_password=""
connection_string_uses_placeholder=0

connection_string_env_var="$(module_param_env_var "${MODULE_NAME}" "connection_string")"
if [[ -z "${!connection_string_env_var:-}" ]] && is_interactive; then
  section "PostgreSQL option"
  log "The selected AIO addons can use PostgreSQL instead of local SQLite: $(join_by ', ' "${selected_addons[@]}")"
  show_message "PostgreSQL Option" "The selected AIO addons can use any PostgreSQL database instead of their default local SQLite databases: $(join_by ', ' "${selected_addons[@]}").

Any Postgres provider works. Two common options:

Supabase:
1. Create a project and save its database password.
2. Open Connect > Direct connection > Session pooler.
3. Copy the URI (it contains the [YOUR-PASSWORD] placeholder).

Neon:
1. Create a project.
2. Open Connect and copy the pooled connection string (it already includes the password).

If you want to keep the default local SQLite databases, leave the next field blank and continue.

When you provide a connection string, the script creates one schema and one login role per selected addon, then writes the generated connection strings into each staged addon .env file automatically."
  warn "Use a new database, not one already used for unrelated data."
fi

connection_string="$(module_get_param "connection_string" "string" "false" \
  "${POSTGRES_CONNECTION_STRING_LABEL}")" || true

if [[ -z "${connection_string}" ]]; then
  log "No PostgreSQL connection string supplied; keeping local SQLite for $(join_by ', ' "${selected_addons[@]}")"
  exit 0
fi

if [[ "${connection_string}" == *"[YOUR-PASSWORD]"* ]]; then
  connection_string_uses_placeholder=1
fi

database_password_env_var="$(module_param_env_var "${MODULE_NAME}" "db_password")"
database_password="${!database_password_env_var:-}"

if [[ -z "${database_password}" ]]; then
  if (( connection_string_uses_placeholder )); then
    database_password="$(module_get_param "db_password" "secret" "false" \
      "${POSTGRES_DB_PASSWORD_LABEL}")" || true
  else
    database_password="$(extract_connection_string_password "${connection_string}")"
    if [[ -z "${database_password}" ]]; then
      database_password="$(module_get_param "db_password" "secret" "false" \
        "${POSTGRES_DB_PASSWORD_LABEL}")" || true
    fi
  fi
fi

[[ -n "${connection_string}" ]] || die "PostgreSQL connection string is required for ${selected_addons[*]}"
[[ -n "${database_password}" ]] || die "Database password is required for ${selected_addons[*]}"

addons_csv="$(join_by ',' "${selected_addons[@]}")"
if is_interactive && ! prompt_yes_no "Create or update the PostgreSQL schemas and login roles now for ${addons_csv}, then write the generated connection strings into the staged addon .env files?" yes; then
  log "Skipping PostgreSQL schema deployment and keeping local SQLite for ${addons_csv}"
  exit 0
fi

log "Creating PostgreSQL schemas for: ${addons_csv}"
connection_string="${connection_string//\[YOUR-PASSWORD\]/${database_password}}"
if hosting_is_dry_run; then
  dry_run_log "Simulating PostgreSQL schema deletion for ${addons_csv}."
  dry_run_log "Simulating PostgreSQL schema creation for ${addons_csv}."
  mapfile -t schema_rows < <(simulate_schema_rows "${connection_string}" "${selected_addons[@]}")
else
  "${SCRIPT_DIR}/db/delete-addon-schemas.sh" --connection-string "${connection_string}" --addons "${addons_csv}"
  schema_output="$("${SCRIPT_DIR}/db/create-addon-schemas.sh" --connection-string "${connection_string}" --addons "${addons_csv}" --password "${database_password}")" \
    || die "PostgreSQL schema creation failed for ${addons_csv}"
  mapfile -t schema_rows <<< "${schema_output}"
fi

(( ${#schema_rows[@]} > 0 )) || die "PostgreSQL schema creation returned no rows for ${addons_csv}"

for row in "${schema_rows[@]}"; do
  IFS=$'\t' read -r addon_name schema_name role_name addon_connection <<< "${row}"
  [[ -n "${addon_connection:-}" ]] || continue

  env_file="${HOSTING_CONFIG_DIR}/$(module_prefix "${addon_name}").env"
  database_key="${DATABASE_URL_KEYS[${addon_name}]:-}"
  [[ -n "${database_key}" ]] || die "No database env key configured for addon: ${addon_name}"
  [[ -f "${env_file}" ]] || die "Missing staged env file for addon: ${env_file}"

  if [[ -n "${EXTRA_ENV_ASSIGNMENTS[${addon_name}]:-}" ]]; then
    IFS='=' read -r extra_key extra_value <<< "${EXTRA_ENV_ASSIGNMENTS[${addon_name}]}"
    env_upsert "${env_file}" "${extra_key}" "${extra_value}"
  fi

  env_upsert "${env_file}" "${database_key}" "${addon_connection}"
  log "PostgreSQL connection prepared for ${addon_name}: ${role_name}"
done

success "Configured PostgreSQL connection strings for $(join_by ', ' "${selected_addons[@]}")"
