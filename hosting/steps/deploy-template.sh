#!/usr/bin/env bash

# Restores staged files and syncs the prepared template into DOCKER_DIR.
#
# Purpose:
#   This is the transition from staging back to a runnable Compose tree. It
#   reads the stage manifest, copies each staged file or directory back to its
#   original template path, creates/fixes permissions on the target directory,
#   and rsyncs the prepared template into DOCKER_DIR.
#
#   In --modify-mode it does not replace the whole tree: it updates the root
#   .env and compose, installs the newly added modules (--install-modules-file),
#   re-syncs already-present modules whose config changed (--update-modules-file,
#   e.g. hostname-sync edits to authelia/honey/cloudflare and the traefik compose
#   that cloudflare-ddns rewrites), and stops + removes deselected modules
#   (--removed-modules-file). Runtime data under DOCKER_DATA_DIR is preserved.
#
# Usage:
#   ./hosting/steps/deploy-template.sh \
#     --template-dir ./hosting/.work/docker \
#     --config-dir ./hosting/.work/config \
#     --manifest-file ./hosting/.work/config/.stage-map.tsv
#
# Safety:
#   The target is synced with rsync --delete so it matches the prepared
#   template. The script chowns DOCKER_DIR to the current user when needed so
#   normal file operations do not require sudo afterward.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/template.sh"

TEMPLATE_DIR_ARG=""
CONFIG_DIR_ARG=""
MANIFEST_FILE=""
TARGET_DIR_ARG=""
FIX_PERMISSIONS=1
MODIFY_MODE=0
INSTALL_MODULES_FILE=""
REMOVED_MODULES_FILE=""
UPDATE_MODULES_FILE=""

while (( $# > 0 )); do
  case "$1" in
    --template-dir)
      TEMPLATE_DIR_ARG="$2"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR_ARG="$2"
      shift 2
      ;;
    --manifest-file)
      MANIFEST_FILE="$2"
      shift 2
      ;;
    --target-dir)
      TARGET_DIR_ARG="$2"
      shift 2
      ;;
    --modify-mode)
      MODIFY_MODE=1
      shift
      ;;
    --install-modules-file)
      INSTALL_MODULES_FILE="$2"
      shift 2
      ;;
    --removed-modules-file)
      REMOVED_MODULES_FILE="$2"
      shift 2
      ;;
    --update-modules-file)
      UPDATE_MODULES_FILE="$2"
      shift 2
      ;;
    --no-fix-permissions)
      FIX_PERMISSIONS=0
      shift
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${TEMPLATE_DIR_ARG}" ]] || die "--template-dir is required"
[[ -n "${CONFIG_DIR_ARG}" ]] || die "--config-dir is required"
[[ -n "${MANIFEST_FILE}" ]] || die "--manifest-file is required"
[[ -d "${TEMPLATE_DIR_ARG}" ]] || die "Template directory does not exist: ${TEMPLATE_DIR_ARG}"
[[ -d "${CONFIG_DIR_ARG}" ]] || die "Config directory does not exist: ${CONFIG_DIR_ARG}"
[[ -f "${MANIFEST_FILE}" ]] || die "Manifest file does not exist: ${MANIFEST_FILE}"
if (( MODIFY_MODE )); then
  [[ -n "${INSTALL_MODULES_FILE}" ]] || die "--install-modules-file is required in --modify-mode"
  [[ -f "${INSTALL_MODULES_FILE}" ]] || die "Install modules file does not exist: ${INSTALL_MODULES_FILE}"
  [[ -n "${REMOVED_MODULES_FILE}" ]] || die "--removed-modules-file is required in --modify-mode"
fi

TARGET_DIR_ARG="${TARGET_DIR_ARG:-$(env_get "${CONFIG_DIR_ARG}/.env" DOCKER_DIR)}"
[[ -n "${TARGET_DIR_ARG}" ]] || die "DOCKER_DIR is not set in ${CONFIG_DIR_ARG}/.env"
TARGET_DIR_ARG="$(absolute_path "${TARGET_DIR_ARG}")"

target_data_dir="$(env_get_resolved "${CONFIG_DIR_ARG}/.env" DOCKER_DATA_DIR || true)"
target_data_dir="$(absolute_path "${target_data_dir:-}")"
target_data_rel=""
target_dir_prefix="${TARGET_DIR_ARG%/}/"
if [[ -n "${target_data_dir}" && "${target_data_dir}" != "${TARGET_DIR_ARG}" ]]; then
  case "${target_data_dir}/" in
    "${target_dir_prefix}"*)
      target_data_rel="${target_data_dir#${target_dir_prefix}}"
      target_data_rel="${target_data_rel%/}"
      ;;
  esac
fi

sync_path_into_target() {
  local source_path="$1"
  local target_path="$2"

  ensure_directory "$(dirname "${target_path}")"
  if [[ -w "$(dirname "${target_path}")" && ( ! -e "${target_path}" || -w "${target_path}" ) ]]; then
    rsync -a --delete "${source_path}" "${target_path}"
  else
    run_privileged rsync -a --delete "${source_path}" "${target_path}"
  fi
}

copy_seed_data_for_module() {
  local module="$1"
  local seed_source=""
  local seed_target=""

  [[ -n "${target_data_dir}" ]] || return 0
  seed_source="${TEMPLATE_DIR_ARG}/data/${module}"
  [[ -e "${seed_source}" ]] || return 0

  seed_target="${target_data_dir}/${module}"
  if [[ -d "${seed_source}" ]]; then
    ensure_directory "${seed_target}"
    if [[ -w "${seed_target}" ]]; then
      rsync -a "${seed_source}/" "${seed_target}/"
    else
      run_privileged mkdir -p "${seed_target}"
      run_privileged rsync -a "${seed_source}/" "${seed_target}/"
    fi
  else
    ensure_directory "$(dirname "${seed_target}")"
    if [[ -w "$(dirname "${seed_target}")" ]]; then
      rsync -a "${seed_source}" "${seed_target}"
    else
      run_privileged rsync -a "${seed_source}" "${seed_target}"
    fi
  fi
}

stop_and_remove_module_profile() {
  local module="$1"

  [[ -n "${module}" ]] || return 0
  command -v docker >/dev/null 2>&1 || return 0
  [[ -d "${TARGET_DIR_ARG}" ]] || return 0
  [[ -f "${TARGET_DIR_ARG}/.env" ]] || return 0

  if [[ -f "${TARGET_DIR_ARG}/compose.yaml" || -f "${TARGET_DIR_ARG}/compose.yml" ]]; then
    (
      cd "${TARGET_DIR_ARG}"
      run_docker_compose --profile "${module}" rm -f -s || true
    )
  fi
}

install_modules=()
removed_modules=()
update_modules=()
restore_modules=()
if (( MODIFY_MODE )); then
  mapfile -t install_modules < <(read_lines_file "${INSTALL_MODULES_FILE}")
  if [[ -n "${REMOVED_MODULES_FILE}" && -f "${REMOVED_MODULES_FILE}" ]]; then
    mapfile -t removed_modules < <(read_lines_file "${REMOVED_MODULES_FILE}")
  fi
  if [[ -n "${UPDATE_MODULES_FILE}" && -f "${UPDATE_MODULES_FILE}" ]]; then
    mapfile -t update_modules < <(read_lines_file "${UPDATE_MODULES_FILE}")
  fi
  # Modules whose staged files should be restored to the template and synced
  # into the target: newly installed modules plus already-present modules whose
  # config was refreshed by hostname-sync hooks (authelia/honey/cloudflare-ddns).
  restore_modules=("${install_modules[@]+"${install_modules[@]}"}" "${update_modules[@]+"${update_modules[@]}"}")
fi

while IFS=$'\t' read -r module source_rel stage_rel item_type; do
  [[ -n "${source_rel}" ]] || continue
  if (( MODIFY_MODE )) && [[ "${module}" != "root" ]] && ! array_contains "${module}" "${restore_modules[@]+"${restore_modules[@]}"}"; then
    continue
  fi
  local_source="${TEMPLATE_DIR_ARG}/${source_rel}"
  local_stage="${CONFIG_DIR_ARG}/${stage_rel}"

  [[ -e "${local_stage}" ]] || die "Staged path missing for ${source_rel}: ${local_stage}"
  rm -rf "${local_source}"
  ensure_directory "$(dirname "${local_source}")"
  cp -a "${local_stage}" "${local_source}"
done < "${MANIFEST_FILE}"

# Drop upstream repository metadata so it does not clutter the deployed tree.
for cruft in .git .gitignore README.md LICENSE CLAUDE.md; do
  rm -rf "${TEMPLATE_DIR_ARG:?}/${cruft}"
done

ensure_apt_packages rsync
require_commands rsync

if mkdir -p "${TARGET_DIR_ARG}" 2>/dev/null; then
  :
else
  run_privileged mkdir -p "${TARGET_DIR_ARG}"
fi

if (( FIX_PERMISSIONS )); then
  if [[ ! -w "${TARGET_DIR_ARG}" ]]; then
    run_privileged chown -R "$(id -u):$(id -g)" "${TARGET_DIR_ARG}"
  fi
fi

if (( MODIFY_MODE )); then
  for module in "${removed_modules[@]}"; do
    stop_and_remove_module_profile "${module}"
  done

  root_compose_source="$(template_root_compose_path "${TEMPLATE_DIR_ARG}")"
  root_compose_target="${TARGET_DIR_ARG}/$(basename "${root_compose_source}")"
  if [[ "${root_compose_target}" == *.yaml ]]; then
    alternate_root_compose="${TARGET_DIR_ARG}/compose.yml"
  else
    alternate_root_compose="${TARGET_DIR_ARG}/compose.yaml"
  fi
  sync_path_into_target "${CONFIG_DIR_ARG}/.env" "${TARGET_DIR_ARG}/.env"
  sync_path_into_target "${root_compose_source}" "${root_compose_target}"
  if [[ -e "${alternate_root_compose}" ]]; then
    if [[ -w "${alternate_root_compose}" ]]; then
      rm -f "${alternate_root_compose}"
    else
      run_privileged rm -f "${alternate_root_compose}"
    fi
  fi

  ensure_directory "${TARGET_DIR_ARG}/apps"
  for module in "${install_modules[@]}"; do
    [[ -d "${TEMPLATE_DIR_ARG}/apps/${module}" ]] || die "Install module missing from template: ${module}"
    sync_path_into_target "${TEMPLATE_DIR_ARG}/apps/${module}/" "${TARGET_DIR_ARG}/apps/${module}/"
    copy_seed_data_for_module "${module}"
  done

  # Re-sync already-present modules whose config was refreshed by hostname-sync
  # hooks. Their runtime state lives under DOCKER_DATA_DIR, not apps/<module>/,
  # so a data-preserving app-directory sync is safe. Skip any that are also in
  # install_modules (already synced above) or being removed.
  for module in "${update_modules[@]+"${update_modules[@]}"}"; do
    [[ -n "${module}" ]] || continue
    array_contains "${module}" "${install_modules[@]+"${install_modules[@]}"}" && continue
    array_contains "${module}" "${removed_modules[@]+"${removed_modules[@]}"}" && continue
    [[ -d "${TEMPLATE_DIR_ARG}/apps/${module}" ]] || continue
    sync_path_into_target "${TEMPLATE_DIR_ARG}/apps/${module}/" "${TARGET_DIR_ARG}/apps/${module}/"
  done

  for module in "${removed_modules[@]}"; do
    [[ -e "${TARGET_DIR_ARG}/apps/${module}" ]] || continue
    if [[ -w "$(dirname "${TARGET_DIR_ARG}/apps/${module}")" ]]; then
      rm -rf "${TARGET_DIR_ARG}/apps/${module}"
    else
      run_privileged rm -rf "${TARGET_DIR_ARG}/apps/${module}"
    fi
  done
elif [[ -n "${target_data_rel}" ]]; then
  log "Preserving live data directory during deploy: ${target_data_dir}"
  if [[ -w "${TARGET_DIR_ARG}" ]]; then
    rsync -a --delete --exclude="/${target_data_rel}/" "${TEMPLATE_DIR_ARG}/" "${TARGET_DIR_ARG}/"
  else
    run_privileged rsync -a --delete --exclude="/${target_data_rel}/" "${TEMPLATE_DIR_ARG}/" "${TARGET_DIR_ARG}/"
  fi

  if [[ -d "${TEMPLATE_DIR_ARG}/${target_data_rel}" ]]; then
    if [[ -w "${TARGET_DIR_ARG}" && ( ! -e "${TARGET_DIR_ARG}/${target_data_rel}" || -w "${TARGET_DIR_ARG}/${target_data_rel}" ) ]]; then
      rsync -a "${TEMPLATE_DIR_ARG}/${target_data_rel}/" "${TARGET_DIR_ARG}/${target_data_rel}/"
    else
      run_privileged rsync -a "${TEMPLATE_DIR_ARG}/${target_data_rel}/" "${TARGET_DIR_ARG}/${target_data_rel}/"
    fi
  fi
elif [[ -w "${TARGET_DIR_ARG}" ]]; then
  rsync -a --delete "${TEMPLATE_DIR_ARG}/" "${TARGET_DIR_ARG}/"
else
  run_privileged rsync -a --delete "${TEMPLATE_DIR_ARG}/" "${TARGET_DIR_ARG}/"
fi

success "Deployed prepared template to ${TARGET_DIR_ARG}"
