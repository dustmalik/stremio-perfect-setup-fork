#!/usr/bin/env bash

# Imports a live Docker tree into the staging layout.
#
# Purpose:
#   This step resumes from an already deployed DOCKER_DIR without creating a
#   backup ZIP first. It restores the live root .env into staging, then stages
#   the selected modules' editable files from the merged template tree so kept
#   modules retain their current config while newly added modules use upstream
#   defaults.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/template.sh"

DOCKER_DIR_ARG=""
TEMPLATE_DIR_ARG=""
CONFIG_DIR_ARG=""
MANIFEST_FILE=""
MODULES_FILE=""

while (( $# > 0 )); do
  case "$1" in
    --docker-dir)
      DOCKER_DIR_ARG="$2"
      shift 2
      ;;
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
    --modules-file)
      MODULES_FILE="$2"
      shift 2
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${DOCKER_DIR_ARG}" ]] || die "--docker-dir is required"
DOCKER_DIR_ARG="$(absolute_path "${DOCKER_DIR_ARG}")"
[[ -d "${DOCKER_DIR_ARG}" ]] || die "Docker directory does not exist: ${DOCKER_DIR_ARG}"
[[ -f "${DOCKER_DIR_ARG}/.env" ]] || die "Docker directory does not contain a root .env: ${DOCKER_DIR_ARG}/.env"
[[ -n "${TEMPLATE_DIR_ARG}" ]] || die "--template-dir is required"
[[ -d "${TEMPLATE_DIR_ARG}" ]] || die "Template directory does not exist: ${TEMPLATE_DIR_ARG}"
[[ -n "${CONFIG_DIR_ARG}" ]] || die "--config-dir is required"
[[ -n "${MANIFEST_FILE}" ]] || die "--manifest-file is required"
[[ -n "${MODULES_FILE}" ]] || die "--modules-file is required"
[[ -f "${MODULES_FILE}" ]] || die "Modules file does not exist: ${MODULES_FILE}"

rm -rf "${CONFIG_DIR_ARG}"
ensure_directory "${CONFIG_DIR_ARG}"
: > "${MANIFEST_FILE}"

cp -a "${DOCKER_DIR_ARG}/.env" "${CONFIG_DIR_ARG}/.env"
printf 'root\t.env\t.env\tfile\n' >> "${MANIFEST_FILE}"

while IFS= read -r module; do
  [[ -n "${module}" ]] || continue

  while IFS= read -r entry; do
    [[ -n "${entry}" ]] || continue
    stage_item "${module}" "apps/${module}/${entry}" "${MANIFEST_FILE}" "${TEMPLATE_DIR_ARG}" "${CONFIG_DIR_ARG}"
  done < <(module_stageable_entries "${TEMPLATE_DIR_ARG}" "${module}")
done < <(read_lines_file "${MODULES_FILE}")

success "Imported live Docker setup into staging: ${DOCKER_DIR_ARG}"
