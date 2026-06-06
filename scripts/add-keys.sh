#!/usr/bin/env bash
#
# add-keys.sh
# ===============
# Batch-adds API keys to wizard/config.json by extracting them from a pasted block,
# encoding them with encode.sh, and storing them in the appropriate arrays.
#
# Supports TMDB (API keys + read tokens) and TVDB (UUID keys).
#
# USAGE
# -----
#   1. Copy your TVDB or TMDB key block
#   2. Run:  scripts/add-api-keys.sh <service> <passphrase>
#      where <service> is either "tvdb" or "tmdb"
#   3. Paste your key block when prompted (Ctrl+D to finish)
#   4. Keys will be encoded and added to config.json
#
# SUPPORTED FORMATS
# -----------------
#
# TVDB Format (2-line repeating):
#   ```
#   username / email / password
#   5831859d-937d-4e33-a40c-509ad88e48fc
#
#   another-username / email / password
#   1f7facba-012a-48f8-8d85-ff9ffaa1e64b
#   ```
#   Extracts: the UUID keys (every 2nd line, skipping blanks)
#
# TMDB Format (3-line repeating):
#   ```
#   account-name
#   API: 03d1a14361e545ef4fb61f40a07fb26f
#   Token: eyJhbGciOiJIUzI1NiJ9...
#
#   another-account
#   API: 12ae7b4991b87220b4a570b5543e6fba
#   Token: eyJhbGciOiJIUzI1NiJ9...
#   ```
#   Extracts: API keys → tmdbApiKeys, Token values → tmdbReadAccessTokens
#
# EXAMPLES
# --------
#   scripts/add-api-keys.sh tvdb "my-passphrase"
#   scripts/add-api-keys.sh tmdb "my-passphrase"
#

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
config_file="$project_root/wizard/config.json"
encode_script="$script_dir/encode.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate inputs
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <service> <passphrase>" >&2
  echo "  service: 'tvdb' or 'tmdb'" >&2
  exit 1
fi

service=$(echo "$1" | tr '[:upper:]' '[:lower:]')
passphrase="$2"

if [[ "$service" != "tvdb" && "$service" != "tmdb" ]]; then
  echo -e "${RED}Error: service must be 'tvdb' or 'tmdb'${NC}" >&2
  exit 1
fi

if [[ ! -f "$encode_script" ]]; then
  echo -e "${RED}Error: encode.sh not found at $encode_script${NC}" >&2
  exit 1
fi

if [[ ! -f "$config_file" ]]; then
  echo -e "${RED}Error: config.json not found at $config_file${NC}" >&2
  exit 1
fi

# Read multiline input from user
echo -e "${YELLOW}Paste your $service key block below (Ctrl+D when done):${NC}"
echo "(blank lines and account info lines will be ignored)"
echo ""

input=""
while IFS= read -r line || [[ -n "$line" ]]; do
  input+="$line"$'\n'
done

if [[ -z "$input" ]]; then
  echo -e "${RED}Error: no input provided${NC}" >&2
  exit 1
fi

# Parse keys based on service type
declare -a keys_to_add
declare array_name
declare key_prefix=""

if [[ "$service" == "tvdb" ]]; then
  array_name="tvdbApiKeys"
  # For TVDB: extract UUIDs (lines that match UUID pattern)
  # UUID pattern: 8-4-4-4-12 hex digits with hyphens
  while IFS= read -r line; do
    # Skip empty lines and lines without hyphens
    [[ -z "$line" ]] && continue
    [[ "$line" != *"-"* ]] && continue

    # Check if line looks like a UUID (rough check)
    if [[ "$line" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]; then
      keys_to_add+=("$line")
    fi
  done <<< "$input"

elif [[ "$service" == "tmdb" ]]; then
  array_name="tmdbApiKeys"
  declare -a token_keys

  # For TMDB: extract API keys and Token values
  api_key=""
  token_key=""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Extract API key
    if [[ "$line" =~ ^API:\ (.+)$ ]]; then
      api_key="${BASH_REMATCH[1]// /}"
    fi

    # Extract Token
    if [[ "$line" =~ ^Token:\ (.+)$ ]]; then
      token_key="${BASH_REMATCH[1]// /}"

      # If we have both API and Token, add them
      if [[ -n "$api_key" && -n "$token_key" ]]; then
        keys_to_add+=("$api_key")
        token_keys+=("$token_key")
        api_key=""
        token_key=""
      fi
    fi
  done <<< "$input"
fi

# Validate we found keys
if [[ ${#keys_to_add[@]} -eq 0 ]]; then
  echo -e "${RED}Error: No valid keys found in the provided block${NC}" >&2
  echo "Make sure the format matches the expected layout." >&2
  exit 1
fi

echo ""
echo -e "${GREEN}Found ${#keys_to_add[@]} key(s) to add${NC}"
echo ""

# Encode keys and prepare JSON array
declare -a encoded_keys

echo -e "${YELLOW}Encoding keys...${NC}"
for i in "${!keys_to_add[@]}"; do
  key="${keys_to_add[$i]}"
  echo -n "  [$((i+1))/${#keys_to_add[@]}] "

  # Use encode.sh to encode the key
  if encoded=$("$encode_script" "$passphrase" "$key"); then
    encoded_keys+=("$encoded")
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${RED}✗ Failed to encode${NC}" >&2
    exit 1
  fi
done

# For TMDB, also encode tokens
if [[ "$service" == "tmdb" ]]; then
  declare -a encoded_tokens
  echo -e "${YELLOW}Encoding tokens...${NC}"

  for i in "${!token_keys[@]}"; do
    token="${token_keys[$i]}"
    echo -n "  [$((i+1))/${#token_keys[@]}] "

    if encoded=$("$encode_script" "$passphrase" "$token"); then
      encoded_tokens+=("$encoded")
      echo -e "${GREEN}✓${NC}"
    else
      echo -e "${RED}✗ Failed to encode${NC}" >&2
      exit 1
    fi
  done
fi

# Update config.json using jq
echo ""
echo -e "${YELLOW}Updating config.json...${NC}"

# Build the jq filter to add the keys
jq_filter=".configurations[0].keys.$array_name += ["

for encoded in "${encoded_keys[@]}"; do
  jq_filter+="\"$encoded\","
done

# Remove trailing comma and close array
jq_filter="${jq_filter%,}]"

# For TMDB, add tokens in a separate update
if [[ "$service" == "tmdb" ]]; then
  # First add API keys
  if ! jq "$jq_filter" "$config_file" > "$config_file.tmp"; then
    echo -e "${RED}Error: Failed to update tmdbApiKeys${NC}" >&2
    exit 1
  fi
  mv "$config_file.tmp" "$config_file"

  # Then add tokens
  jq_filter=".configurations[0].keys.tmdbReadAccessTokens += ["
  for encoded in "${encoded_tokens[@]}"; do
    jq_filter+="\"$encoded\","
  done
  jq_filter="${jq_filter%,}]"

  if ! jq "$jq_filter" "$config_file" > "$config_file.tmp"; then
    echo -e "${RED}Error: Failed to update tmdbReadAccessTokens${NC}" >&2
    exit 1
  fi
  mv "$config_file.tmp" "$config_file"
else
  # For TVDB, just add the keys
  if ! jq "$jq_filter" "$config_file" > "$config_file.tmp"; then
    echo -e "${RED}Error: Failed to update $array_name${NC}" >&2
    exit 1
  fi
  mv "$config_file.tmp" "$config_file"
fi

echo -e "${GREEN}✓ config.json updated successfully${NC}"
echo ""
echo "Summary:"
echo "  Service:    $service"
echo "  Array:      $array_name"
echo "  Keys added: ${#keys_to_add[@]}"
echo ""
echo "Your keys are now available as fallback keys in the wizard."
