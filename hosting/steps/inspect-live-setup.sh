#!/usr/bin/env bash

# Inspects an already deployed Docker tree before module selection.
#
# Purpose:
#   This step makes the modules from an existing live DOCKER_DIR visible to the
#   fetched template before the user chooses whether to keep, add, or remove
#   modules. Enabled module directories from the live tree replace the fetched
#   template copies so downstream staging uses the current on-disk setup.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/template.sh"

DOCKER_DIR_ARG=""
TEMPLATE_DIR_ARG=""
ENABLED_MODULES_FILE=""
PRESENT_MODULES_FILE=""

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
    --enabled-modules-file)
      ENABLED_MODULES_FILE="$2"
      shift 2
      ;;
    --present-modules-file)
      PRESENT_MODULES_FILE="$2"
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
[[ -n "${ENABLED_MODULES_FILE}" ]] || die "--enabled-modules-file is required"
[[ -n "${PRESENT_MODULES_FILE}" ]] || die "--present-modules-file is required"

root_compose_path="$(template_root_compose_path "${DOCKER_DIR_ARG}")"
mapfile -t enabled_modules < <(list_included_modules "${root_compose_path}" | dedupe_lines)
(( ${#enabled_modules[@]} > 0 )) || die "No enabled modules found in root compose include list: ${root_compose_path}"

mapfile -t present_modules < <(list_app_modules "${DOCKER_DIR_ARG}")
(( ${#present_modules[@]} > 0 )) || die "No app modules found in live Docker tree: ${DOCKER_DIR_ARG}/apps"

for module in "${present_modules[@]}"; do
  [[ -d "${DOCKER_DIR_ARG}/apps/${module}" ]] || die "Live module directory missing from Docker tree: ${DOCKER_DIR_ARG}/apps/${module}"
  rm -rf "${TEMPLATE_DIR_ARG}/apps/${module}"
  cp -a "${DOCKER_DIR_ARG}/apps/${module}" "${TEMPLATE_DIR_ARG}/apps/${module}"
done

write_lines_file "${ENABLED_MODULES_FILE}" "${enabled_modules[@]}"
write_lines_file "${PRESENT_MODULES_FILE}" "${present_modules[@]}"
success "Live setup modules merged into fetched template: ${DOCKER_DIR_ARG}"
