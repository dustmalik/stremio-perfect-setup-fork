#!/usr/bin/env bash

# Main end-to-end entrypoint for preparing and deploying the hosting stack.
#
# Purpose:
#   This script implements the full prompt.md flow. It installs Docker, fetches
#   the upstream docker-compose-template into a temporary work directory, lets
#   the user choose modules, stages editable config files, applies module hooks,
#   restores staged files into the fetched template, deploys the prepared tree
#   into DOCKER_DIR, optionally backs up the staged config, starts Compose, and
#   prints DNS guidance.
#
# Interactive usage:
#   ./hosting/main.sh
#   ./hosting/main.sh /path/to/streaming-backup.zip
#
# Unattended usage:
#   ./hosting/main.sh \
#     --modules aiostreams,aiometadata,honey,cloudflare-ddns \
#     --domain example.com \
#     --letsencrypt-email admin@example.com \
#     --skip-review
#
# Key options:
#   --backup                     Backup an existing deployed Docker tree with prompts.
#   --backup-quick               Backup an existing deployed Docker tree using defaults.
#   --modules                     Comma-separated optional modules.
#   --timezone                    TZ database identifier, for example Europe/Berlin.
#   --docker-dir                  Final Docker Compose directory, default /opt/docker.
#   --domain                      Base public domain for Traefik hostnames.
#   --letsencrypt-email           Email address passed to Let's Encrypt.
#   --cloudflare-api-token        Token used by cloudflare-ddns when selected.
#   --cloudflare-proxied          Cloudflare DDNS proxy mode when that module is enabled.
#   --supabase-connection-string  Supabase direct session pooler IPv4 URL.
#   --supabase-db-password        Password replacing [YOUR-PASSWORD].
#   --backup-zip                  Resume from a previously generated config backup ZIP.
#   --backup-dir                  Folder where the config ZIP backup is written.
#   --template-source             upstream or local.
#   --dry-run                     Exercise file-preparation flow without changing system state.
#   --prepare-ssh                 Run the SSH helper before Docker preparation.
#   --skip-ssh                    Skip the interactive SSH preparation prompt.
#   --skip-review                 Do not pause for manual staged-config review.
#   --skip-backup                 Do not create a config ZIP backup.
#   --skip-start                  Deploy files but do not start Docker Compose.
#
# Positional input:
#   backup.zip                    Optional path to a previously generated backup ZIP.
#                                 When supplied, main.sh imports it into staging and
#                                 skips fresh config staging plus module hooks.
#
# Supabase behavior:
#   Supabase is intentionally offered only for aiomanager, aiometadata, and
#   aiostreams. If the user declines or no connection string is supplied in
#   unattended mode, those addons keep their upstream SQLite defaults.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/template.sh"

load_defaults

WORK_ROOT_ABS="${HOSTING_ROOT}/${WORK_ROOT:-.work}"
TEMPLATE_DIR_ABS="${HOSTING_ROOT}/${TEMPLATE_DIR:-.work/docker}"
CONFIG_DIR_ABS="${HOSTING_ROOT}/${CONFIG_DIR:-.work/config}"
MANIFEST_FILE="${CONFIG_DIR_ABS}/.stage-map.tsv"
SELECTED_MODULES_FILE="${WORK_ROOT_ABS}/selected-modules.txt"
BACKUP_AVAILABLE_MODULES_FILE="${WORK_ROOT_ABS}/backup-modules.txt"
BACKUP_METADATA_MODULES_FILE="${WORK_ROOT_ABS}/backup-selected-modules.txt"
CLOUDFLARE_DDNS_MODULE=cloudflare-ddns

MODULES_CSV=""
TIMEZONE_VALUE=""
DOCKER_DIR_VALUE=""
DOMAIN_VALUE=""
LETSENCRYPT_EMAIL_VALUE=""
CLOUDFLARE_API_TOKEN_VALUE=""
CLOUDFLARE_PROXIED_VALUE=""
SUPABASE_CONNECTION_STRING_VALUE=""
SUPABASE_DB_PASSWORD_VALUE=""
BACKUP_DIR_VALUE="${BACKUP_OUTPUT_DIR:-$HOME}"
TEMPLATE_SOURCE_VALUE="${TEMPLATE_SOURCE:-upstream}"
BACKUP_ZIP_INPUT=""
DRY_RUN=0
SKIP_REVIEW=0
SKIP_BACKUP=0
SKIP_START=0
PREPARE_SSH=0
SKIP_SSH=0
BACKUP_MODE=0
BACKUP_QUICK_MODE=0
BACKUP_DIR_SET=0
DOCKER_DIR_SET=0

while (( $# > 0 )); do
  case "$1" in
    --backup)
      BACKUP_MODE=1
      shift
      ;;
    --backup-quick)
      BACKUP_QUICK_MODE=1
      shift
      ;;
    --modules)
      MODULES_CSV="$2"
      shift 2
      ;;
    --timezone)
      TIMEZONE_VALUE="$2"
      shift 2
      ;;
    --docker-dir)
      DOCKER_DIR_VALUE="$2"
      DOCKER_DIR_SET=1
      shift 2
      ;;
    --domain)
      DOMAIN_VALUE="$2"
      shift 2
      ;;
    --letsencrypt-email)
      LETSENCRYPT_EMAIL_VALUE="$2"
      shift 2
      ;;
    --cloudflare-api-token)
      CLOUDFLARE_API_TOKEN_VALUE="$2"
      shift 2
      ;;
    --cloudflare-proxied)
      CLOUDFLARE_PROXIED_VALUE="$2"
      shift 2
      ;;
    --supabase-connection-string)
      SUPABASE_CONNECTION_STRING_VALUE="$2"
      shift 2
      ;;
    --supabase-db-password)
      SUPABASE_DB_PASSWORD_VALUE="$2"
      shift 2
      ;;
    --backup-dir)
      BACKUP_DIR_VALUE="$2"
      BACKUP_DIR_SET=1
      shift 2
      ;;
    --backup-zip)
      BACKUP_ZIP_INPUT="$2"
      shift 2
      ;;
    --template-source)
      TEMPLATE_SOURCE_VALUE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-review)
      SKIP_REVIEW=1
      shift
      ;;
    --skip-backup)
      SKIP_BACKUP=1
      shift
      ;;
    --skip-start)
      SKIP_START=1
      shift
      ;;
    --prepare-ssh)
      PREPARE_SSH=1
      shift
      ;;
    --skip-ssh)
      SKIP_SSH=1
      shift
      ;;
    -*)
      die "Unknown argument: $1"
      ;;
    *)
      [[ -z "${BACKUP_ZIP_INPUT}" ]] || die "Unexpected extra argument: $1"
      BACKUP_ZIP_INPUT="$1"
      shift
      ;;
  esac
done

if [[ -n "${BACKUP_ZIP_INPUT}" ]]; then
  BACKUP_ZIP_INPUT="$(absolute_path "${BACKUP_ZIP_INPUT}")"
fi

run_existing_docker_backup() {
  local docker_dir_default=""
  local backup_dir_default=""

  docker_dir_default="${DEFAULT_DOCKER_DIR:-/opt/docker}"
  backup_dir_default="${BACKUP_DIR_VALUE:-${BACKUP_OUTPUT_DIR:-$HOME}}"

  section "Docker configuration backup"
  require_commands python3

  if (( BACKUP_MODE )); then
    if (( ! DOCKER_DIR_SET )); then
      DOCKER_DIR_VALUE="$(prompt_value "Enter the deployed Docker Compose directory that should be backed up. This is the live stack folder that currently contains the root .env and compose files [DOCKER_DIR]" "${docker_dir_default}")"
    fi
    if (( ! BACKUP_DIR_SET )); then
      BACKUP_DIR_VALUE="$(prompt_value "Enter the directory where the backup ZIP should be written so you can restore this stack later [BACKUP_OUTPUT_DIR]" "${backup_dir_default}")"
    fi
  fi

  DOCKER_DIR_VALUE="${DOCKER_DIR_VALUE:-${docker_dir_default}}"
  BACKUP_DIR_VALUE="${BACKUP_DIR_VALUE:-${backup_dir_default}}"

  [[ -n "${DOCKER_DIR_VALUE}" ]] || die "Docker Compose directory is required for backup mode"
  [[ -n "${BACKUP_DIR_VALUE}" ]] || die "Backup output directory is required for backup mode"

  DOCKER_DIR_VALUE="$(absolute_path "${DOCKER_DIR_VALUE}")"
  BACKUP_DIR_VALUE="$(absolute_path "${BACKUP_DIR_VALUE}")"

  log "Source Docker directory: ${DOCKER_DIR_VALUE}"
  log "Backup output directory: ${BACKUP_DIR_VALUE}"

  "${HOSTING_ROOT}/steps/backup-docker-config.sh" \
    --docker-dir "${DOCKER_DIR_VALUE}" \
    --output-dir "${BACKUP_DIR_VALUE}"
}

if (( BACKUP_MODE && BACKUP_QUICK_MODE )); then
  die "Use either --backup or --backup-quick, not both"
fi

if (( BACKUP_MODE || BACKUP_QUICK_MODE )); then
  [[ -z "${BACKUP_ZIP_INPUT}" ]] || die "Backup ZIP import cannot be combined with --backup or --backup-quick"
  run_existing_docker_backup
  exit 0
fi

section "Hosting preparation"
prime_sudo_session "the hosting setup"
log "Work directory: ${WORK_ROOT_ABS}"
ensure_directory "${WORK_ROOT_ABS}"
ensure_apt_packages python3 openssl curl
setup_cleanup_trap
register_cleanup_path "${WORK_ROOT_ABS}"

if (( DRY_RUN )); then
  export HOSTING_DRY_RUN=1
  SKIP_REVIEW=1
  SKIP_START=1
  dry_run_log "SSH setup, Docker installation, Docker Compose start, external IP lookup, and Supabase changes are skipped."
  DOCKER_DIR_VALUE="${WORK_ROOT_ABS}/dry-run/deploy"
  if (( ! BACKUP_DIR_SET )); then
    BACKUP_DIR_VALUE="${WORK_ROOT_ABS}/dry-run/backup"
  fi
  ensure_directory "${DOCKER_DIR_VALUE}"
  ensure_directory "${BACKUP_DIR_VALUE}"
fi

ensure_dialog_ui "the hosting setup"

if is_interactive; then
  show_message "Hosting Setup" "This guided setup will prepare SSH access, verify Docker, download the upstream Docker template, let you choose which app modules to deploy, stage editable config files, and then deploy the final stack to your VPS. You will be asked to confirm each major step before the script makes changes."
fi

if (( DRY_RUN )); then
  dry_run_log "Skipping SSH setup."
elif (( PREPARE_SSH )); then
  section "SSH setup"
  "${HOSTING_ROOT}/steps/prepare-ssh.sh"
elif (( ! SKIP_SSH )) && is_interactive && prompt_yes_no "Prepare or update the local SSH key and alias configuration now? This is needed so you can connect to the VPS reliably from this machine." yes; then
  section "SSH setup"
  "${HOSTING_ROOT}/steps/prepare-ssh.sh"
fi

if (( DRY_RUN )); then
  dry_run_log "Skipping Docker installation."
else
  section "Docker setup"
  if is_interactive; then
    show_message "Docker Setup" "The next step verifies Docker and Docker Compose on this machine, installs them if they are missing, and makes sure your user can access Docker. This is required because the entire hosting stack is deployed with Docker Compose."
    prompt_yes_no "Check Docker now and install or configure it if needed so the hosting stack can be deployed later?" yes || die "Docker setup cancelled."
  fi
  HOSTING_DOCKER_PROMPTED=1 "${HOSTING_ROOT}/steps/install-docker.sh"
fi

section "Template fetch"
"${HOSTING_ROOT}/steps/fetch-template.sh" --source "${TEMPLATE_SOURCE_VALUE}" --template-dir "${TEMPLATE_DIR_ABS}"

if is_interactive; then
  show_message "Custom Modules" "The upstream template has been downloaded into ${TEMPLATE_DIR_ABS}. If you want to add any extra app folders under ${TEMPLATE_DIR_ABS}/apps now, do that before module discovery continues. Each extra module must live in its own folder and contain a compose.yaml or compose.yml file so the script can detect it."
  prompt_yes_no "Have you finished adding any custom app folders under ${TEMPLATE_DIR_ABS}/apps so module discovery can continue?" yes || die "Module discovery cancelled."
fi

backup_available_modules=()
backup_metadata_modules=()
backup_default_modules_csv=""
if [[ -n "${BACKUP_ZIP_INPUT}" ]]; then
  section "Backup inspection"
  "${HOSTING_ROOT}/steps/inspect-backup.sh" \
    --zip-file "${BACKUP_ZIP_INPUT}" \
    --template-dir "${TEMPLATE_DIR_ABS}" \
    --available-modules-file "${BACKUP_AVAILABLE_MODULES_FILE}" \
    --metadata-modules-file "${BACKUP_METADATA_MODULES_FILE}"
  if [[ -f "${BACKUP_AVAILABLE_MODULES_FILE}" ]]; then
    mapfile -t backup_available_modules < <(read_lines_file "${BACKUP_AVAILABLE_MODULES_FILE}")
  fi
  if [[ -f "${BACKUP_METADATA_MODULES_FILE}" ]]; then
    mapfile -t backup_metadata_modules < <(read_lines_file "${BACKUP_METADATA_MODULES_FILE}")
  fi
  backup_default_modules_csv="$(join_by ',' "${backup_available_modules[@]}")"
fi

all_modules=()
required_modules=()
optional_modules=()
discover_modules "${TEMPLATE_DIR_ABS}" all_modules required_modules optional_modules
success "Discovered ${#all_modules[@]} modules (${#required_modules[@]} required, ${#optional_modules[@]} optional)."

if [[ -n "${BACKUP_ZIP_INPUT}" ]]; then
  section "Module selection"
  selected_modules=()
  backup_default_modules_csv="$(join_by ',' "${backup_metadata_modules[@]}")"
  if [[ -z "${backup_default_modules_csv}" ]]; then
    backup_default_modules_csv="$(join_by ',' "${backup_available_modules[@]}")"
  fi
  if (( ${#backup_metadata_modules[@]} > 0 )); then
    selected_modules=("${backup_metadata_modules[@]}")
  else
    split_csv_into_array "${backup_default_modules_csv}" selected_modules
  fi
  if [[ -n "${MODULES_CSV}" ]]; then
    extra_modules=()
    split_csv_into_array "${MODULES_CSV}" extra_modules
    for module in "${extra_modules[@]}"; do
      [[ -n "${module}" ]] || continue
      array_contains "${module}" "${selected_modules[@]}" || selected_modules+=("${module}")
    done
  elif is_interactive; then
    select_modules_interactively "${TEMPLATE_DIR_ABS}" "${SELECTED_MODULES_FILE}" "${backup_default_modules_csv}"
    mapfile -t selected_modules < <(read_lines_file "${SELECTED_MODULES_FILE}")
  elif (( ${#backup_metadata_modules[@]} == 0 )); then
    die "Backup ZIP does not contain HOSTING_SELECTED_MODULES.txt. Run interactively or pass --modules."
  fi
  for module in "${required_modules[@]}"; do
    array_contains "${module}" "${selected_modules[@]}" || selected_modules+=("${module}")
  done
  for module in "${selected_modules[@]}"; do
    array_contains "${module}" "${all_modules[@]}" || die "Unknown module: ${module}"
  done
  write_lines_file "${SELECTED_MODULES_FILE}" "${selected_modules[@]}"
  success "Selected modules from backup: $(join_by ', ' "${selected_modules[@]}")"
elif [[ -n "${MODULES_CSV}" ]]; then
  section "Module selection"
  selected_modules=()
  split_csv_into_array "${MODULES_CSV}" selected_modules
  for module in "${required_modules[@]}"; do
    array_contains "${module}" "${selected_modules[@]}" || selected_modules+=("${module}")
  done
  for module in "${selected_modules[@]}"; do
    array_contains "${module}" "${all_modules[@]}" || die "Unknown module: ${module}"
  done
  write_lines_file "${SELECTED_MODULES_FILE}" "${selected_modules[@]}"
  success "Selected modules: $(join_by ', ' "${selected_modules[@]}")"
else
  select_modules_interactively "${TEMPLATE_DIR_ABS}" "${SELECTED_MODULES_FILE}"
fi
mapfile -t selected_modules < <(read_lines_file "${SELECTED_MODULES_FILE}")

if [[ -z "${BACKUP_ZIP_INPUT}" ]]; then
  section "Config staging"
  "${HOSTING_ROOT}/steps/stage-configs.sh" --template-dir "${TEMPLATE_DIR_ABS}" --config-dir "${CONFIG_DIR_ABS}" --modules-file "${SELECTED_MODULES_FILE}" --manifest-file "${MANIFEST_FILE}"
else
  section "Backup import"
  "${HOSTING_ROOT}/steps/import-backup.sh" \
    --zip-file "${BACKUP_ZIP_INPUT}" \
    --template-dir "${TEMPLATE_DIR_ABS}" \
    --config-dir "${CONFIG_DIR_ABS}" \
    --manifest-file "${MANIFEST_FILE}" \
    --modules-file "${SELECTED_MODULES_FILE}"
fi

ROOT_ENV="${CONFIG_DIR_ABS}/.env"
root_tz_default="$(env_get "${ROOT_ENV}" TZ || true)"
root_docker_dir_default="$(env_get "${ROOT_ENV}" DOCKER_DIR || true)"
root_domain_default="$(env_get "${ROOT_ENV}" DOMAIN || true)"
root_letsencrypt_default="$(env_get "${ROOT_ENV}" LETSENCRYPT_EMAIL || true)"
root_authelia_session_default="$(env_get "${ROOT_ENV}" AUTHELIA_SESSION_SECRET || true)"
root_authelia_storage_default="$(env_get "${ROOT_ENV}" AUTHELIA_STORAGE_ENCRYPTION_KEY || true)"
root_authelia_jwt_default="$(env_get "${ROOT_ENV}" AUTHELIA_JWT_SECRET || true)"

root_tz_default="${DEFAULT_TIMEZONE:-${root_tz_default:-Europe/Berlin}}"
root_docker_dir_default="${DEFAULT_DOCKER_DIR:-${root_docker_dir_default:-/opt/docker}}"
env_value_is_placeholder "${root_domain_default}" && root_domain_default=""
env_value_is_placeholder "${root_letsencrypt_default}" && root_letsencrypt_default=""

if is_interactive; then
  show_message "Environment Details" "Next, enter the core environment values for the stack: timezone, final Docker directory, public base domain, and the email address used for Let's Encrypt notifications. These values are written into the staged root .env and used across multiple services."
fi

TIMEZONE_VALUE="${TIMEZONE_VALUE:-$(prompt_value "Enter the server timezone using the TZ database identifier so containers log and schedule tasks correctly, for example Europe/Berlin [TZ]" "${root_tz_default}")}"
if (( DRY_RUN )); then
  dry_run_log "Overriding DOCKER_DIR with ${DOCKER_DIR_VALUE}"
else
  DOCKER_DIR_VALUE="${DOCKER_DIR_VALUE:-$(prompt_value "Enter the final Docker Compose directory where the prepared stack should be deployed on this machine. You can use ~, an absolute path, or a relative path [DOCKER_DIR]" "${root_docker_dir_default}")}"
fi
DOMAIN_VALUE="${DOMAIN_VALUE:-$(prompt_value "Enter the public base domain that Traefik-routed services should use for their hostnames, for example example.com [DOMAIN]" "${root_domain_default}")}"
LETSENCRYPT_EMAIL_VALUE="${LETSENCRYPT_EMAIL_VALUE:-$(prompt_value "Enter the email address that Let's Encrypt should use for expiry and certificate notifications [LETSENCRYPT_EMAIL]" "${root_letsencrypt_default}")}"

[[ -n "${TIMEZONE_VALUE}" ]] || die "Timezone is required"
[[ -n "${DOCKER_DIR_VALUE}" ]] || die "DOCKER_DIR is required"
[[ -n "${DOMAIN_VALUE}" ]] || die "DOMAIN is required"
[[ -n "${LETSENCRYPT_EMAIL_VALUE}" ]] || die "LETSENCRYPT_EMAIL is required"

DOCKER_DIR_VALUE="$(absolute_path "${DOCKER_DIR_VALUE}")"

env_upsert "${ROOT_ENV}" TZ "${TIMEZONE_VALUE}"
env_upsert "${ROOT_ENV}" DOCKER_DIR "${DOCKER_DIR_VALUE}"
env_upsert "${ROOT_ENV}" PUID "$(id -u)"
env_upsert "${ROOT_ENV}" PGID "$(id -g)"
env_upsert "${ROOT_ENV}" DOMAIN "${DOMAIN_VALUE}"
env_upsert "${ROOT_ENV}" LETSENCRYPT_EMAIL "${LETSENCRYPT_EMAIL_VALUE}"
env_upsert "${ROOT_ENV}" AUTHELIA_SESSION_SECRET "${HOSTING_AUTHELIA_SESSION_SECRET:-${root_authelia_session_default:-$(generate_secret_base64)}}"
env_upsert "${ROOT_ENV}" AUTHELIA_STORAGE_ENCRYPTION_KEY "${HOSTING_AUTHELIA_STORAGE_ENCRYPTION_KEY:-${root_authelia_storage_default:-$(generate_secret_base64)}}"
env_upsert "${ROOT_ENV}" AUTHELIA_JWT_SECRET "${HOSTING_AUTHELIA_JWT_SECRET:-${root_authelia_jwt_default:-$(generate_secret_base64)}}"
success "Root .env values and generated secrets are staged."

hostname_vars_missing=()
hostname_vars_modules=()
for module in "${selected_modules[@]}"; do
  while IFS= read -r env_var; do
    [[ -n "${env_var}" ]] || continue
    array_contains "${env_var}" "${hostname_vars_missing[@]}" && continue
    existing_val="$(env_get "${ROOT_ENV}" "${env_var}" || true)"
    env_value_is_placeholder "${existing_val}" || continue
    hostname_vars_missing+=("${env_var}")
    hostname_vars_modules+=("${module}")
  done < <(module_host_env_vars "${TEMPLATE_DIR_ABS}" "${module}")
done

if (( ${#hostname_vars_missing[@]} > 0 )); then
  section "Hostname configuration"
  if is_interactive; then
    show_message "Hostname Configuration" "The following service hostnames are missing from the root .env. For each one, enter the subdomain prefix and the script will store the full hostname as prefix.${DOMAIN_VALUE} in the root .env. Press Enter to accept the suggested prefix."
  fi
  for i in "${!hostname_vars_missing[@]}"; do
    env_var="${hostname_vars_missing[i]}"
    module="${hostname_vars_modules[i]}"
    suggested_subdomain="$(printf '%s' "${env_var}" | sed 's/_HOSTNAME$//' | tr '[:upper:]_' '[:lower:]-')"
    subdomain_prefix="$(prompt_value "Enter the subdomain prefix for the ${module} service so its hostname can be stored as prefix.${DOMAIN_VALUE} in the root .env [${env_var}]" "${suggested_subdomain}")"
    [[ -n "${subdomain_prefix}" ]] || subdomain_prefix="${suggested_subdomain}"
    env_upsert "${ROOT_ENV}" "${env_var}" "${subdomain_prefix}.${DOMAIN_VALUE}"
    success "${env_var}=${subdomain_prefix}.${DOMAIN_VALUE}"
  done
fi

sync_staged_configs_to_selected_modules() {
  local selected_modules_now=()
  local manifest_tmp=""
  local module="" source_rel="" stage_rel="" item_type=""

  manifest_tmp="$(mktemp "${WORK_ROOT_ABS}/stage-map.XXXXXX")"
  mapfile -t selected_modules_now < <(read_lines_file "${SELECTED_MODULES_FILE}")

  while IFS=$'\t' read -r module source_rel stage_rel item_type; do
    [[ -n "${source_rel}" ]] || continue
    if [[ "${module}" == "root" ]]; then
      printf '%s\t%s\t%s\t%s\n' "${module}" "${source_rel}" "${stage_rel}" "${item_type}" >> "${manifest_tmp}"
      continue
    fi

    if array_contains "${module}" "${selected_modules_now[@]}"; then
      [[ -e "${CONFIG_DIR_ABS}/${stage_rel}" ]] || die "Staged path missing for ${source_rel}: ${CONFIG_DIR_ABS}/${stage_rel}"
      printf '%s\t%s\t%s\t%s\n' "${module}" "${source_rel}" "${stage_rel}" "${item_type}" >> "${manifest_tmp}"
      continue
    fi

    rm -rf "${CONFIG_DIR_ABS}/${stage_rel}"
  done < "${MANIFEST_FILE}"

  mv "${manifest_tmp}" "${MANIFEST_FILE}"

  while IFS= read -r module; do
    [[ -n "${module}" ]] || continue
    while IFS= read -r entry; do
      [[ -n "${entry}" ]] || continue
      stage_item "${module}" "apps/${module}/${entry}" "${MANIFEST_FILE}" "${TEMPLATE_DIR_ABS}" "${CONFIG_DIR_ABS}"
    done < <(module_stageable_entries "${TEMPLATE_DIR_ABS}" "${module}")
  done < <(read_lines_file "${SELECTED_MODULES_FILE}")
}

module_hook_title() {
  local script_path="$1"
  local module_name="$2"
  local hook_name=""

  hook_name="$(basename "${script_path}" .sh)"
  case "${hook_name}" in
    all.supabase)
      printf 'Supabase setup'
      ;;
    cloudflare-ddns)
      printf 'Cloudflare DDNS setup'
      ;;
    *)
      if [[ -n "${module_name}" ]]; then
        printf 'Module setup: %s' "${module_name}"
      else
        printf 'Module setup: %s' "${hook_name}"
      fi
      ;;
  esac
}

run_module_hooks() {
  local hook_delim=$'\x1f'
  local script_path="" metadata="" scope="" module="" dependencies="" order=""
  local hook_modules=()
  local hook_title="" hook_target=""
  local hooks_file=""
  local hooks_interactive=0

  if is_interactive && tty_device_available; then
    hooks_interactive=1
  fi

  hooks_file="$(mktemp "${WORK_ROOT_ABS}/hook-order.XXXXXX")"

  while IFS= read -r script_path; do
    [[ -x "${script_path}" ]] || die "Module hook is not executable: ${script_path}"
    metadata="$("${script_path}" --metadata)"
    scope="$(printf '%s\n' "${metadata}" | awk -F= '$1 == "scope" { print $2 }')"
    module="$(printf '%s\n' "${metadata}" | awk -F= '$1 == "module" { print $2 }')"
    dependencies="$(printf '%s\n' "${metadata}" | awk -F= '$1 == "dependencies" { print $2 }')"
    order="$(printf '%s\n' "${metadata}" | awk -F= '$1 == "order" { print $2 }')"
    [[ -n "${scope}" ]] || die "Module hook did not report scope metadata: ${script_path}"
    printf '%s%s%s%s%s%s%s%s%s\n' \
      "${order:-100}" "${hook_delim}" \
      "${script_path}" "${hook_delim}" \
      "${scope}" "${hook_delim}" \
      "${module}" "${hook_delim}" \
      "${dependencies}" >> "${hooks_file}"
  done < <(find "${HOSTING_ROOT}/modules" -maxdepth 1 -type f -name '*.sh' | sort)

  while IFS="${hook_delim}" read -r order script_path scope module dependencies; do
    case "${scope}" in
      module)
        [[ -n "${module}" ]] || die "Module hook did not report module metadata: ${script_path}"
        hook_modules=("${module}")
        ;;
      all)
        [[ -n "${dependencies}" ]] || die "All-scope hook did not report dependencies metadata: ${script_path}"
        split_csv_into_array "${dependencies}" hook_modules
        ;;
      *)
        die "Unknown module scope '${scope}' in ${script_path}"
        ;;
    esac

    hook_title="$(module_hook_title "${script_path}" "${module}")"
    hook_target="$(join_by ', ' "${hook_modules[@]}")"
    section "${hook_title}"
    log "Running $(basename "${script_path}") for ${hook_target}"

    run_module_hook_script "${script_path}" "${hooks_interactive}" env \
      HOSTING_TEMPLATE_DIR="${TEMPLATE_DIR_ABS}" \
      HOSTING_CONFIG_DIR="${CONFIG_DIR_ABS}" \
      HOSTING_MANIFEST_FILE="${MANIFEST_FILE}" \
      HOSTING_SELECTED_MODULES_FILE="${SELECTED_MODULES_FILE}" \
      HOSTING_ROOT_ENV="${ROOT_ENV}" \
      HOSTING_CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN_VALUE}" \
      HOSTING_CLOUDFLARE_PROXIED="${CLOUDFLARE_PROXIED_VALUE}" \
      HOSTING_SUPABASE_CONNECTION_STRING="${SUPABASE_CONNECTION_STRING_VALUE}" \
      HOSTING_SUPABASE_DB_PASSWORD="${SUPABASE_DB_PASSWORD_VALUE}"
  done < <(sort -t "${hook_delim}" -k1,1n -k2,2 "${hooks_file}")

  rm -f "${hooks_file}"
}

run_module_hook_script() {
  local script_path="$1"
  local interactive_mode="${2:-0}"

  shift 2

  if [[ "${interactive_mode}" == "1" ]] && tty_device_available; then
    "$@" "${script_path}" </dev/tty
  else
    "$@" "${script_path}"
  fi
}

section "Module automation"
if [[ -n "${BACKUP_ZIP_INPUT}" ]]; then
  log "Skipping module hooks because the staged config was imported from a backup ZIP."
else
  run_module_hooks
fi
sync_staged_configs_to_selected_modules
success "Staged config directory synced to the final selected modules."

mapfile -t final_modules < <(read_lines_file "${SELECTED_MODULES_FILE}")
prune_template_to_modules "${TEMPLATE_DIR_ABS}" "${final_modules[@]}"
success "Template pruned to selected modules: $(join_by ', ' "${final_modules[@]}")"

pruned_modules=()
pruned_required_modules=()
pruned_optional_modules=()
discover_modules "${TEMPLATE_DIR_ABS}" pruned_modules pruned_required_modules pruned_optional_modules
(( ${#pruned_modules[@]} == ${#final_modules[@]} )) || die "Template pruning mismatch: expected ${#final_modules[@]} modules, found ${#pruned_modules[@]}"
for module in "${final_modules[@]}"; do
  array_contains "${module}" "${pruned_modules[@]}" || die "Template pruning mismatch: missing selected module ${module}"
done
for module in "${pruned_modules[@]}"; do
  array_contains "${module}" "${final_modules[@]}" || die "Template pruning mismatch: unexpected module remained after pruning: ${module}"
done

compose_profiles=()
while IFS= read -r profile; do
  [[ -n "${profile}" ]] || continue
  compose_profiles+=("${profile}")
done < <(template_profile_names "${TEMPLATE_DIR_ABS}" "${final_modules[@]}")
(( ${#compose_profiles[@]} > 0 )) || die "No compose profiles found in the pruned template"
required_profile="${REQUIRED_PROFILE:-required}"
array_contains "${required_profile}" "${compose_profiles[@]}" || compose_profiles=("${required_profile}" "${compose_profiles[@]}")

env_upsert "${ROOT_ENV}" COMPOSE_PROFILES "\"$(join_by ',' "${compose_profiles[@]}")\""
success "COMPOSE_PROFILES=$(join_by ',' "${compose_profiles[@]}")"

if (( ! SKIP_REVIEW )) && is_interactive; then
  section "Manual review"
  log "Review staged files in ${CONFIG_DIR_ABS}"
  warn "Do not rename staged files. Prefixes such as AIOSTREAMS., HONEY., and TRAEFIK. map files back to modules."
  show_message "Manual Review" "Review the staged files in ${CONFIG_DIR_ABS} before deployment. You can edit values there if needed, but do not rename the files because their names map back to source files in specific modules. Continue when you are satisfied with the staged configuration."
fi

if is_interactive; then
  prompt_yes_no "Deploy the prepared stack into ${DOCKER_DIR_VALUE} now? This will sync the generated files into that directory and make it the live Docker Compose tree for this setup." yes || die "Deployment cancelled."
fi

section "Deploy"
"${HOSTING_ROOT}/steps/deploy-template.sh" \
  --template-dir "${TEMPLATE_DIR_ABS}" \
  --config-dir "${CONFIG_DIR_ABS}" \
  --manifest-file "${MANIFEST_FILE}" \
  --target-dir "${DOCKER_DIR_VALUE}" \
  $([[ "${HOSTING_DRY_RUN:-0}" == "1" ]] && printf '%s' '--no-fix-permissions')

if (( ! SKIP_BACKUP )); then
  if ! is_interactive || prompt_yes_no "Create a backup ZIP of the prepared configuration now? This is recommended because it makes later restores and migrations much easier." yes; then
    if is_interactive && (( ! BACKUP_DIR_SET )); then
      BACKUP_DIR_VALUE="$(prompt_value "Enter the directory where the generated backup ZIP should be saved after deployment [BACKUP_OUTPUT_DIR]" "${BACKUP_DIR_VALUE}")"
    fi
    BACKUP_DIR_VALUE="$(absolute_path "${BACKUP_DIR_VALUE}")"
    section "Backup"
    "${HOSTING_ROOT}/steps/backup-configs.sh" --config-dir "${CONFIG_DIR_ABS}" --template-dir "${TEMPLATE_DIR_ABS}" --manifest-file "${MANIFEST_FILE}" --modules-file "${SELECTED_MODULES_FILE}" --output-dir "${BACKUP_DIR_VALUE}"
  fi
fi

if (( ! SKIP_START )); then
  if is_interactive; then
    prompt_yes_no "Start the Docker Compose stack now so Docker can launch the selected services immediately?" yes || {
      warn "Skipping Docker Compose start at your request."
      SKIP_START=1
    }
  fi
fi

if (( ! SKIP_START )); then
  section "Docker Compose start"
  "${HOSTING_ROOT}/steps/start-stack.sh" --target-dir "${DOCKER_DIR_VALUE}"
fi

public_ip="$(default_public_ip)"
hostnames=()
for module in "${final_modules[@]}"; do
  while IFS= read -r env_var; do
    value="$(env_get_resolved "${ROOT_ENV}" "${env_var}")"
    [[ -n "${value}" ]] && hostnames+=("${value}")
  done < <(module_host_env_vars "${TEMPLATE_DIR_ABS}" "${module}")
done

section "Final summary"
if (( DRY_RUN )); then
  success "Dry run prepared stack in ${DOCKER_DIR_VALUE}"
else
  success "Prepared stack deployed to ${DOCKER_DIR_VALUE}"
fi
if [[ -n "${public_ip}" ]]; then
  log "Public IP: ${public_ip}"
fi
if (( ${#hostnames[@]} > 0 )); then
  if (( DRY_RUN )); then
    log "Dry run generated these hostnames from the prepared config:"
  elif array_contains "${CLOUDFLARE_DDNS_MODULE}" "${final_modules[@]}"; then
    log "Cloudflare DDNS is configured for these hostnames:"
  else
    warn "Create DNS A records pointing these hostnames to the public IP above:"
  fi
  printf '  %s\n' $(printf '%s\n' "${hostnames[@]}" | dedupe_lines | sort)
fi

rm -rf "${TEMPLATE_DIR_ABS}" "${CONFIG_DIR_ABS}"
rm -f "${SELECTED_MODULES_FILE}"
rm -f "${BACKUP_AVAILABLE_MODULES_FILE}" "${BACKUP_METADATA_MODULES_FILE}"
rmdir "${WORK_ROOT_ABS}" 2>/dev/null || true
success "Temporary work directories cleaned up."
