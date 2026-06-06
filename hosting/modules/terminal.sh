#!/usr/bin/env bash

# Configures the browser-based terminal service for interactive setup automation.
#
# Purpose:
#   This module hook prompts for Cloudflare Turnstile challenge keys, extracts
#   or prompts for the terminal hostname, and generates cryptographic secrets
#   required by the terminal service. It is responsible for preparing the
#   TERMINAL.env configuration file that will be mounted into the Docker
#   container running the terminal service.
#
# Scope:
#   This script runs as part of the main hosting automation pipeline during
#   the "modules" phase (order 75). It only configures the terminal service;
#   it does not deploy, build, or start containers. Those tasks are handled by
#   Docker Compose and other orchestration steps.
#
# Configuration Outputs:
#   - Populates hosting/config/TERMINAL.env with Turnstile credentials
#   - Generates COOKIE_SECRET for HMAC session cookie signing
#   - Records TERMINAL_HOSTNAME in the root .env (HOSTING_ROOT_ENV)
#
# Dependencies:
#   - Cloudflare Turnstile account with a site created and API keys ready
#   - A valid domain or hostname for the terminal service (e.g., setup.example.com)
#
# Usage:
#   This script is invoked automatically by hosting/main.sh during the module
#   configuration phase. Do not run directly unless advancing a partial setup.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

MODULE_NAME=terminal

if [[ "${1:-}" == "--metadata" ]]; then
  printf 'scope=module\nmodule=%s\norder=75\n' "${MODULE_NAME}"
  exit 0
fi

[[ -n "${HOSTING_CONFIG_DIR:-}" ]] || die "HOSTING_CONFIG_DIR is not set"
[[ -n "${HOSTING_TEMPLATE_DIR:-}" ]] || die "HOSTING_TEMPLATE_DIR is not set"
[[ -n "${HOSTING_ROOT_ENV:-}" ]] || die "HOSTING_ROOT_ENV is not set"

if ! hook_target_enabled "${MODULE_NAME}"; then exit 0; fi
if ! selected_module_enabled "${MODULE_NAME}"; then exit 0; fi

TERMINAL_ENV="${HOSTING_CONFIG_DIR}/TERMINAL.env"
[[ -f "${TERMINAL_ENV}" ]] || die "Missing staged terminal env file: ${TERMINAL_ENV}"

# Prompt for Turnstile Site Key
current_site_key="$(env_get "${TERMINAL_ENV}" TURNSTILE_SITE_KEY || true)"
if [[ -z "${current_site_key}" ]] && is_interactive; then
  current_site_key="$(
    prompt_value \
      "Enter your Cloudflare Turnstile Site Key (from https://dash.cloudflare.com/): " \
      ""
  )" || die "Turnstile Site Key is required."
fi
env_upsert "${TERMINAL_ENV}" TURNSTILE_SITE_KEY "${current_site_key}"

# Prompt for Turnstile Secret Key
current_secret_key="$(env_get "${TERMINAL_ENV}" TURNSTILE_SECRET_KEY || true)"
if [[ -z "${current_secret_key}" ]] && is_interactive; then
  current_secret_key="$(
    prompt_secret "Enter your Cloudflare Turnstile Secret Key"
  )" || die "Turnstile Secret Key is required."
fi
env_upsert "${TERMINAL_ENV}" TURNSTILE_SECRET_KEY "${current_secret_key}"

# Generate COOKIE_SECRET if not already set
current_cookie_secret="$(env_get "${TERMINAL_ENV}" COOKIE_SECRET || true)"
if [[ -z "${current_cookie_secret}" ]]; then
  current_cookie_secret="$(openssl rand -hex 32)"
  log "Generated COOKIE_SECRET for terminal service"
fi
env_upsert "${TERMINAL_ENV}" COOKIE_SECRET "${current_cookie_secret}"

# Prompt for Terminal Hostname
TERMINAL_HOSTNAME="$(env_get "${HOSTING_ROOT_ENV}" TERMINAL_HOSTNAME || true)"
if [[ -z "${TERMINAL_HOSTNAME}" ]] && is_interactive; then
  TERMINAL_HOSTNAME="$(
    prompt_value \
      "Enter the hostname for the setup terminal service (e.g., setup.example.com): " \
      "setup.${DOMAIN:-example.com}"
  )" || die "Terminal hostname is required."
fi

# Update root .env with TERMINAL_HOSTNAME
env_upsert "${HOSTING_ROOT_ENV}" TERMINAL_HOSTNAME "${TERMINAL_HOSTNAME}"

success "Configured terminal service: ${TERMINAL_HOSTNAME} (COOKIE_SECRET auto-generated)"
