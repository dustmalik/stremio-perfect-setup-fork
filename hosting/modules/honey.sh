#!/usr/bin/env bash

# Configures the staged Honey dashboard JSON.
#
# Purpose:
#   Honey's upstream dashboard lists many services whether or not they are
#   selected. This hook rewrites HONEY_HOSTNAME to tools.${DOMAIN}, replaces
#   trusted-domain placeholders with the configured DOMAIN, resolves selected
#   module hostnames, removes upstream dashboard services whose href host does
#   not belong to the selected module set, and appends any missing services
#   from the local Honey service catalog for enabled modules.
#
# Called automatically by main.sh when honey is selected.
#
# Manual hook contract:
#
#   HOSTING_TEMPLATE_DIR=./hosting/.work/docker \
#   HOSTING_CONFIG_DIR=./hosting/.work/config \
#   HOSTING_SELECTED_MODULES_FILE=./hosting/.work/selected-modules.txt \
#   HOSTING_ROOT_ENV=./hosting/.work/config/.env \
#   ./hosting/modules/honey.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/template.sh"

MODULE_NAME=honey
HONEY_HOSTNAME_VALUE='tools.${DOMAIN}'
HONEY_RESOURCES_CONFIG="${SCRIPT_DIR}/configs/honey.json"

if [[ "${1:-}" == "--metadata" ]]; then
    printf 'scope=module\nmodule=%s\norder=50\n' "${MODULE_NAME}"
  exit 0
fi

[[ -n "${HOSTING_TEMPLATE_DIR:-}" ]] || die "HOSTING_TEMPLATE_DIR is not set"
[[ -n "${HOSTING_CONFIG_DIR:-}" ]] || die "HOSTING_CONFIG_DIR is not set"
[[ -n "${HOSTING_SELECTED_MODULES_FILE:-}" ]] || die "HOSTING_SELECTED_MODULES_FILE is not set"
[[ -n "${HOSTING_ROOT_ENV:-}" ]] || die "HOSTING_ROOT_ENV is not set"
[[ -f "${HONEY_RESOURCES_CONFIG}" ]] || die "Honey resource catalog is missing: ${HONEY_RESOURCES_CONFIG}"

HONEY_CONFIG="${HOSTING_CONFIG_DIR}/$(stage_name_for "${MODULE_NAME}" config.json)"
[[ -f "${HONEY_CONFIG}" ]] || exit 0

DOMAIN_VALUE="$(env_get "${HOSTING_ROOT_ENV}" DOMAIN)"
[[ -n "${DOMAIN_VALUE}" ]] || die "DOMAIN must be set before running the honey module"

env_upsert "${HOSTING_ROOT_ENV}" HONEY_HOSTNAME "${HONEY_HOSTNAME_VALUE}"

selected_modules=()
hostname_env_vars=()
while IFS= read -r module; do
  [[ -n "${module}" ]] || continue
  selected_modules+=("${module}")
  while IFS= read -r env_var; do
    [[ -n "${env_var}" ]] || continue
    hostname_env_vars+=("${env_var}")
  done < <(module_host_env_vars "${HOSTING_TEMPLATE_DIR}" "${module}")
done < <(read_lines_file "${HOSTING_SELECTED_MODULES_FILE}")

HOSTING_HONEY_DOMAIN="${DOMAIN_VALUE}" \
HOSTING_HONEY_SELECTED_MODULES="$(printf '%s\n' "${selected_modules[@]}" | dedupe_lines)" \
HOSTING_HONEY_HOST_ENV_VARS="$(printf '%s\n' "${hostname_env_vars[@]}" | dedupe_lines)" \
python3 - "${HONEY_CONFIG}" "${HONEY_RESOURCES_CONFIG}" "${HOSTING_ROOT_ENV}" <<'PY'
import json
import os
import re
import sys
from urllib.parse import urlparse

config_path = sys.argv[1]
resource_path = sys.argv[2]
env_path = sys.argv[3]
target_domain = os.environ["HOSTING_HONEY_DOMAIN"]
selected_modules = [line for line in os.environ.get("HOSTING_HONEY_SELECTED_MODULES", "").splitlines() if line]
host_env_vars = [line for line in os.environ.get("HOSTING_HONEY_HOST_ENV_VARS", "").splitlines() if line]

pattern = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:?[-?])([^}]*))?\}")

raw_env = {}
with open(env_path, "r", encoding="utf-8") as handle:
    for line in handle:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, raw = line.rstrip("\n").split("=", 1)
        raw_env[key] = raw.strip().strip('"').strip("'")

resolved_env = {}

def resolve_value(value):
    if not isinstance(value, str):
        return value

    def replace(match):
        key = match.group(1)
        operator = match.group(2)
        fallback = match.group(3) or ""
        current = resolve_env(key)
        if current:
            return current
        if operator == ":-":
            return fallback
        return ""

    for _ in range(10):
        new_value = pattern.sub(replace, value)
        if new_value == value:
            break
        value = new_value
    return value

def resolve_env(key):
    if key in resolved_env:
        return resolved_env[key]
    resolved_env[key] = resolve_value(raw_env.get(key, ""))
    return resolved_env[key]

keep_hosts = {resolve_env(env_var) for env_var in host_env_vars if resolve_env(env_var)}

with open(config_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

with open(resource_path, "r", encoding="utf-8") as handle:
    resources = json.load(handle)

old_domains = list(data.get("ui", {}).get("trusted_domains", []))

def replace_domain(value):
    if isinstance(value, str):
        for old_domain in old_domains:
            value = value.replace(old_domain, target_domain)
        return value
    if isinstance(value, list):
        return [replace_domain(item) for item in value]
    if isinstance(value, dict):
        return {key: replace_domain(item) for key, item in value.items()}
    return value

data = replace_domain(data)
data.setdefault("ui", {})["trusted_domains"] = [target_domain]

filtered_services = []
seen_hrefs = set()
for service in data.get("services", []):
    host = urlparse(service.get("href", "")).hostname
    if host and host in keep_hosts:
        filtered_services.append(service)
        href = service.get("href")
        if href:
            seen_hrefs.add(href)

for module in selected_modules:
    for entry in resources.get("modules", {}).get(module, []):
        hostname_env = entry.get("hostname_env")
        if not hostname_env:
            continue
        hostname = resolve_env(hostname_env)
        if not hostname:
            continue
        href = resolve_value(entry.get("href_template", ""))
        if not href or href in seen_hrefs:
            continue

        service = {
            "name": entry.get("name", module),
            "desc": entry.get("desc", ""),
            "href": href,
            "icon": entry.get("icon", ""),
        }
        filtered_services.append(service)
        seen_hrefs.add(href)

data["services"] = filtered_services

with open(config_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

success "Updated Honey dashboard config for the selected modules"
