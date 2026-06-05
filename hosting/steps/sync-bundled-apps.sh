#!/usr/bin/env bash

# Overlays the bundled hosting/apps/* folders onto the fetched template.
#
# Purpose:
#   The upstream template ships its own apps/. Anything under hosting/apps/ is an
#   additional app that is NOT in upstream (e.g. watchly, cors-proxy). After the
#   template is fetched into the work dir, this step copies those folders into the
#   template's apps/ so they become discoverable, selectable modules. Existing
#   upstream apps are preserved (overlay, no --delete); a bundled app whose name
#   matches an upstream app overrides it. Each bundled app must contain a
#   compose.yaml or compose.yml or it is skipped.
#
# Usage:
#   ./hosting/steps/sync-bundled-apps.sh --template-dir ./hosting/.work/docker
#   ./hosting/steps/sync-bundled-apps.sh --template-dir DIR --apps-dir ./hosting/apps

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

TEMPLATE_DIR_ARG=""
APPS_DIR_ARG=""

while (( $# > 0 )); do
  case "$1" in
    --template-dir)
      TEMPLATE_DIR_ARG="$2"
      shift 2
      ;;
    --apps-dir)
      APPS_DIR_ARG="$2"
      shift 2
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${TEMPLATE_DIR_ARG}" ]] || die "--template-dir is required"
APPS_DIR_ARG="${APPS_DIR_ARG:-${HOSTING_ROOT}/apps}"

if [[ ! -d "${APPS_DIR_ARG}" ]]; then
  log "No bundled apps directory at ${APPS_DIR_ARG}; skipping."
  exit 0
fi

ensure_directory "${TEMPLATE_DIR_ARG}/apps"

added=()
shopt -s nullglob
for app_dir in "${APPS_DIR_ARG}"/*/; do
  app_name="$(basename "${app_dir}")"
  if [[ ! -f "${app_dir}compose.yaml" && ! -f "${app_dir}compose.yml" ]]; then
    warn "Skipping bundled app '${app_name}': no compose.yaml or compose.yml found."
    continue
  fi
  ensure_apt_packages rsync
  rsync -a "${app_dir}" "${TEMPLATE_DIR_ARG}/apps/${app_name}/"
  added+=("${app_name}")
done
shopt -u nullglob

if (( ${#added[@]} > 0 )); then
  success "Added bundled apps to template: $(join_by ', ' "${added[@]}")"
else
  log "No bundled apps to add."
fi
