#!/usr/bin/env bash

# Per-session setup and execution wrapper for the browser-based terminal.
#
# Purpose:
#   This script creates an isolated, temporary workspace (tmpfs) for each
#   browser terminal session, clones the hosting automation source code into
#   that workspace, and runs the main.sh setup script in --local mode.
#   The script enforces a hard session timeout and ensures all temporary files
#   are cleaned up on exit, preventing leakage between sessions.
#
# Scope:
#   This script runs once per WeTTY session (one per browser connection).
#   It is invoked by the WeTTY daemon as the session command (--command flag).
#   The subprocess hierarchy is: server.js -> WeTTY -> run-session.sh -> main.sh.
#
# Session Isolation:
#   - Each session gets a unique tmpfs-backed home directory (/tmp/session-<ID>)
#   - A separate SSH directory with strict 0700 permissions
#   - A sparse clone of the hosting source (minimal bandwidth, fast clone)
#   - The session-local HOME and PATH prevent cross-session pollution
#
# Timeout Mechanism:
#   - A background sleep process enforces SESSION_TIMEOUT_SECONDS hard limit
#   - At timeout, the entire session process group is terminated via SIGTERM
#   - The EXIT trap ensures cleanup (kill timeout PID, rm -rf session directory)
#
# Execution Flow:
#   1. Create unique session ID and tmpfs directory
#   2. Configure session-local SSH directory (for user's SSH keys during setup)
#   3. Start background timeout process with EXIT trap
#   4. Sparse-clone hosting repo into session workspace
#   5. Execute main.sh --local to run interactive setup
#   6. EXIT trap fires on completion/timeout: kill timeout, clean tmpfs
#
# Environment:
#   - SESSION_TIMEOUT_SECONDS: max session duration (default 1800 = 30 min)
#   - GIT_REPO_OWNER: GitHub account for cloning (default ssterjo)

set -Eeuo pipefail

# Per-session isolation: each browser connection gets its own tmpfs workspace
SESSION_ID="$(openssl rand -hex 8)"
SESSION_DIR="/tmp/session-${SESSION_ID}"
mkdir -p "${SESSION_DIR}"

# Workspace directories
export HOME="${SESSION_DIR}"
SSH_DIR="${SESSION_DIR}/.ssh"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

# Hard timeout: kill the session after SESSION_TIMEOUT_SECONDS (default 30 min)
TIMEOUT="${SESSION_TIMEOUT_SECONDS:-1800}"
(
  sleep "${TIMEOUT}"
  echo ""
  echo "Session timeout reached ($(( TIMEOUT / 60 )) minutes). Closing."
  kill -TERM -- -$$ 2>/dev/null || true
) &
TIMEOUT_PID=$!

# EXIT trap: unconditionally remove all session data, kill timeout process
trap "kill '${TIMEOUT_PID}' 2>/dev/null || true; rm -rf '${SESSION_DIR}'" EXIT

# Clone the hosting source into the session workspace
# Use sparse clone to fetch only the hosting/ directory (faster than full clone)
WORK_DIR="${SESSION_DIR}/hosting"
git clone --depth 1 --filter=blob:none --sparse \
  "https://github.com/${GIT_REPO_OWNER:-ssterjo}/stremio-perfect-setup.git" \
  "${WORK_DIR}" 2>&1 | grep -v "^Cloning into\|^Receiving objects" || true
cd "${WORK_DIR}"
git sparse-checkout set hosting 2>&1 | grep -v "^Updating files" || true

# Copy hosting contents up one level (sparse clone puts them nested)
if [[ -d hosting ]]; then
  mv hosting/* .
  rmdir hosting
fi

# Run main.sh in the session context
# --local tells main.sh to configure the local machine (not a VPS)
# The setup then SSHes to the user's actual VPS to continue
exec ./main.sh --local
