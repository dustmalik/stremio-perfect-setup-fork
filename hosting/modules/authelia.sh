#!/usr/bin/env bash

# Configures Authelia secrets and initialises the user database.
#
# Purpose:
#   Generates the three Authelia secrets (AUTHELIA_SESSION_SECRET,
#   AUTHELIA_STORAGE_ENCRYPTION_KEY, AUTHELIA_JWT_SECRET) into the staged root
#   .env. When running interactively, also prompts for the initial Authelia user
#   account details (username, display name, password, email) and writes an
#   updated users.yml into the staged Authelia config directory.
#
# Called automatically by main.sh when authelia is a selected module.
#
# Manual hook contract:
#
#   HOSTING_TEMPLATE_DIR=./hosting/.work/docker \
#   HOSTING_CONFIG_DIR=./hosting/.work/config \
#   HOSTING_MANIFEST_FILE=./hosting/.work/config/.stage-map.tsv \
#   HOSTING_SELECTED_MODULES_FILE=./hosting/.work/selected-modules.txt \
#   HOSTING_ROOT_ENV=./hosting/.work/config/.env \
#   HOSTING_AUTHELIA_USERNAME='myuser' \
#   HOSTING_AUTHELIA_DISPLAYNAME='My User' \
#   HOSTING_AUTHELIA_EMAIL='user@example.com' \
#   HOSTING_AUTHELIA_PASSWORD='plaintextpassword' \
#   ./hosting/modules/authelia.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/template.sh"
ensure_dialog_ui "Authelia setup"

MODULE_NAME=authelia
USERS_YAML_REL="apps/authelia/config/users.yml"

if [[ "${1:-}" == "--metadata" ]]; then
  printf 'scope=module\nmodule=%s\norder=85\n' "${MODULE_NAME}"
  exit 0
fi

[[ -n "${HOSTING_TEMPLATE_DIR:-}" ]] || die "HOSTING_TEMPLATE_DIR is not set"
[[ -n "${HOSTING_CONFIG_DIR:-}" ]] || die "HOSTING_CONFIG_DIR is not set"
[[ -n "${HOSTING_MANIFEST_FILE:-}" ]] || die "HOSTING_MANIFEST_FILE is not set"
[[ -n "${HOSTING_SELECTED_MODULES_FILE:-}" ]] || die "HOSTING_SELECTED_MODULES_FILE is not set"
[[ -n "${HOSTING_ROOT_ENV:-}" ]] || die "HOSTING_ROOT_ENV is not set"

if ! selected_module_enabled "${MODULE_NAME}"; then
  exit 0
fi

# ── secrets ───────────────────────────────────────────────────────────────────

root_session_default="$(env_get "${HOSTING_ROOT_ENV}" AUTHELIA_SESSION_SECRET || true)"
root_storage_default="$(env_get "${HOSTING_ROOT_ENV}" AUTHELIA_STORAGE_ENCRYPTION_KEY || true)"
root_jwt_default="$(env_get "${HOSTING_ROOT_ENV}" AUTHELIA_JWT_SECRET || true)"
env_value_is_placeholder "${root_session_default}" && root_session_default=""
env_value_is_placeholder "${root_storage_default}" && root_storage_default=""
env_value_is_placeholder "${root_jwt_default}" && root_jwt_default=""

env_upsert "${HOSTING_ROOT_ENV}" AUTHELIA_SESSION_SECRET \
  "${HOSTING_AUTHELIA_SESSION_SECRET:-${root_session_default:-$(generate_secret_base64)}}"
env_upsert "${HOSTING_ROOT_ENV}" AUTHELIA_STORAGE_ENCRYPTION_KEY \
  "${HOSTING_AUTHELIA_STORAGE_ENCRYPTION_KEY:-${root_storage_default:-$(generate_secret_base64)}}"
env_upsert "${HOSTING_ROOT_ENV}" AUTHELIA_JWT_SECRET \
  "${HOSTING_AUTHELIA_JWT_SECRET:-${root_jwt_default:-$(generate_secret_base64)}}"

# ── users.yml ─────────────────────────────────────────────────────────────────

if [[ ! -f "${HOSTING_TEMPLATE_DIR}/${USERS_YAML_REL}" ]]; then
  warn "Authelia users.yml not found in template; skipping user configuration."
  success "Authelia secrets written to root .env."
  exit 0
fi

stage_item "${MODULE_NAME}" "apps/${MODULE_NAME}/config" \
  "${HOSTING_MANIFEST_FILE}" "${HOSTING_TEMPLATE_DIR}" "${HOSTING_CONFIG_DIR}"

users_yaml_staged="${HOSTING_CONFIG_DIR}/$(stage_name_for "${MODULE_NAME}" "config")/users.yml"

# ── collect user details ──────────────────────────────────────────────────────

authelia_username="${HOSTING_AUTHELIA_USERNAME:-}"
authelia_displayname="${HOSTING_AUTHELIA_DISPLAYNAME:-}"
authelia_email="${HOSTING_AUTHELIA_EMAIL:-}"
authelia_password="${HOSTING_AUTHELIA_PASSWORD:-}"

validate_username() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

if [[ -z "${authelia_username}" || -z "${authelia_displayname}" || \
      -z "${authelia_email}" || -z "${authelia_password}" ]] && is_interactive; then

  section "Authelia user account"
  show_message "Authelia User Setup" "Set up the initial Authelia user account. The username must contain only letters, digits, hyphens, and underscores. The password will be hashed using argon2 via Docker."

  if dialog_ui_available; then
    while true; do
      form_output="$(
        whiptail_capture_on_tty \
          --title "Authelia User Account" \
          --mixedform "Enter the initial Authelia user account details:" \
          18 78 4 \
          "Username:"     1 1 "${authelia_username}"    1 20 50 0 0 \
          "Display Name:" 2 1 "${authelia_displayname}" 2 20 50 0 0 \
          "Password:"     3 1 ""                        3 20 50 0 1 \
          "Email:"        4 1 "${authelia_email}"       4 20 50 0 0
      )" || die "Prompt cancelled."

      mapfile -t form_fields <<< "${form_output}"
      authelia_username="${form_fields[0]:-}"
      authelia_displayname="${form_fields[1]:-}"
      authelia_password="${form_fields[2]:-}"
      authelia_email="${form_fields[3]:-}"

      if [[ -z "${authelia_username}" || -z "${authelia_displayname}" || \
            -z "${authelia_password}" || -z "${authelia_email}" ]]; then
        whiptail_on_tty --title "Validation Error" \
          --msgbox "All fields are required. Please fill in every field." 10 60
        continue
      fi

      if ! validate_username "${authelia_username}"; then
        whiptail_on_tty --title "Invalid Username" \
          --msgbox "Username '${authelia_username}' is not valid.\nUse only letters, digits, hyphens, and underscores." \
          10 70
        authelia_username=""
        continue
      fi

      break
    done
  else
    while true; do
      authelia_username="$(prompt_value "Enter the Authelia username (letters, digits, hyphens, underscores only) [AUTHELIA_USERNAME]" "${authelia_username}")"
      if [[ -z "${authelia_username}" ]]; then
        warn "Username is required."
        continue
      fi
      if ! validate_username "${authelia_username}"; then
        warn "Invalid username '${authelia_username}'. Use only letters, digits, hyphens, and underscores."
        authelia_username=""
        continue
      fi
      break
    done
    authelia_displayname="$(prompt_value "Enter the Authelia display name [AUTHELIA_DISPLAYNAME]" "${authelia_displayname}")"
    [[ -n "${authelia_displayname}" ]] || die "Display name is required."
    authelia_password="$(prompt_secret "Enter the Authelia password (will be argon2-hashed) [AUTHELIA_PASSWORD]")"
    [[ -n "${authelia_password}" ]] || die "Password is required."
    authelia_email="$(prompt_value "Enter the Authelia user email [AUTHELIA_EMAIL]" "${authelia_email}")"
    [[ -n "${authelia_email}" ]] || die "Email is required."
  fi
fi

if [[ -z "${authelia_username}" || -z "${authelia_displayname}" || \
      -z "${authelia_password}" || -z "${authelia_email}" ]]; then
  warn "Authelia user details not supplied in unattended mode; skipping users.yml configuration."
  success "Authelia secrets written to root .env."
  exit 0
fi

validate_username "${authelia_username}" || \
  die "Invalid Authelia username '${authelia_username}'. Use only letters, digits, hyphens, and underscores."

# ── hash password ─────────────────────────────────────────────────────────────

require_commands docker

run_authelia_docker() {
  if docker info >/dev/null 2>&1; then
    docker run "$@"
  else
    run_privileged docker run "$@"
  fi
}

log "Hashing Authelia password via Docker (this may pull the image on first run)..."
password_hash="$(
  run_authelia_docker --rm authelia/authelia:latest \
    authelia crypto hash generate argon2 \
    --password "${authelia_password}" 2>&1 \
  | awk '/^Digest:/ { print $2 }'
)"

[[ -n "${password_hash}" ]] || die "Failed to generate argon2 password hash via Docker."

# ── patch users.yml ───────────────────────────────────────────────────────────

AUTHELIA_USERNAME="${authelia_username}" \
AUTHELIA_DISPLAYNAME="${authelia_displayname}" \
AUTHELIA_EMAIL="${authelia_email}" \
AUTHELIA_PASSWORD_HASH="${password_hash}" \
python3 - "${users_yaml_staged}" <<'PY'
import os
import re
import sys

users_yaml_path  = sys.argv[1]
username         = os.environ["AUTHELIA_USERNAME"]
displayname      = os.environ["AUTHELIA_DISPLAYNAME"]
email            = os.environ["AUTHELIA_EMAIL"]
password_hash    = os.environ["AUTHELIA_PASSWORD_HASH"]

with open(users_yaml_path, "r", encoding="utf-8") as fh:
    lines = fh.readlines()

new_lines = []
in_users_block      = False
first_user_replaced = False
user_key_re         = re.compile(r'^  \S.*:')

for line in lines:
    if re.match(r'^users:\s*$', line):
        in_users_block = True
        new_lines.append(line)
        continue

    if in_users_block and not first_user_replaced and user_key_re.match(line):
        new_lines.append(f'  {username}:\n')
        first_user_replaced = True
        continue

    if first_user_replaced:
        if re.match(r'^\s+displayname:', line):
            new_lines.append(f'    displayname: "{displayname}"\n')
            continue
        if re.match(r'^\s+password:', line):
            new_lines.append(f'    password: "{password_hash}"\n')
            continue
        if re.match(r'^\s+email:', line):
            new_lines.append(f'    email: {email}\n')
            continue

    new_lines.append(line)

with open(users_yaml_path, "w", encoding="utf-8") as fh:
    fh.writelines(new_lines)
PY

success "Authelia secrets and user account configured."
