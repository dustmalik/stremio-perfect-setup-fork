# Final whiptail screens for hosting setup

## Goal

When `hosting/main.sh` finishes, show the user a final whiptail screen instead of
silently dropping back to the terminal:

- **Success:** a whiptail msgbox mirroring the console "Final summary" — stack
  location, public IP, hostnames, and the matching DNS guidance line.
- **Failure:** a whiptail msgbox for any non-zero exit (controlled `die` calls
  and unexpected crashes alike), so an error is seen on screen rather than only
  scrolled past in the terminal.

The existing console summary and stderr error output stay exactly as they are.
The whiptail screens are additive and only appear when a whiptail UI is
available.

## Scope decisions

- Error screen covers **all** failures (global trap), not just `die`.
- Unexpected crashes show the failing command + line number; `die` failures show
  the clean `die` message.
- Success screen appears for **real deploys only**, not dry runs. (The console
  summary still prints its dry-run wording.)

## Error capture mechanism

The script runs under `set -Eeuo pipefail` and installs one EXIT trap
(`cleanup_registered_paths`) via `setup_cleanup_trap` at `main.sh:637`. Rather
than touch every `die`/sub-step call site, capture is centralized on traps in
`lib/common.sh`:

1. **`die()`** records its message into a module-level `HOSTING_ERROR_MESSAGE`
   before `exit 1`. `die` already holds the clean, human-readable message.
2. A new **`ERR` trap** (`record_error`) stores `LINENO` and `BASH_COMMAND` for
   unexpected crashes — the cases `die` never sees. `set -E` already propagates
   the ERR trap into functions. Guarded commands (`if`, `||`, `&&`, `!`)
   correctly do not fire it, so the captured command is the genuinely fatal one.
3. The **EXIT trap** becomes the single decision point (`on_exit`):
   - capture `$?` into a local `exit_code` as the first line;
   - if `exit_code != 0` and `dialog_ui_available`, show the error dialog;
   - run the existing `cleanup_registered_paths`;
   - `exit "${exit_code}"` to preserve the original status (keeping the
     intent of the existing comment about a trap's last command becoming the
     script exit status).

No `die` call sites and no sub-step scripts change. Sub-step scripts are separate
processes; when one exits non-zero, the calling command in `main.sh` fails and
`main.sh`'s ERR trap captures that call.

### Error dialog content

- If `HOSTING_ERROR_MESSAGE` is non-empty: show that message.
- Else (raw crash): "Setup failed unexpectedly." plus the failing command and
  line number.
- Always append the exit code and: "Full output is in the terminal above —
  scroll up for details."
- Shown only when `dialog_ui_available`. When unavailable (non-interactive / no
  whiptail), behaviour is unchanged — stderr already carries the error.

## Success dialog

Added in `main.sh` immediately after the console "Final summary" block
(`main.sh:1373-1391`), which is left untouched. Gated on
`dialog_ui_available && ! DRY_RUN`. Reuses the already-computed `public_ip`,
`hostnames`, `final_modules`, and `DOCKER_DIR_VALUE`. Content mirrors the
console summary:

- "Stack deployed to: ${DOCKER_DIR_VALUE}"
- "Public IP: ${public_ip}" (when set)
- the deduped + sorted hostnames
- the matching guidance line: Cloudflare DDNS configured vs. "Create DNS A
  records pointing these hostnames to the public IP above."

Box height is computed from the number of content lines so variable-length
hostname lists fit.

## Code locations

- `lib/common.sh`:
  - new `HOSTING_ERROR_MESSAGE=""` module var
  - `die()` sets `HOSTING_ERROR_MESSAGE` before exit
  - new `record_error()` (ERR trap body) and `on_exit()` (EXIT trap body)
  - new `show_error_dialog()` helper
  - new `dialog_msgbox_height()` helper (line count → clamped box height)
  - `setup_cleanup_trap()` installs both `ERR` and `EXIT` traps
- `main.sh`:
  - success-dialog block appended after the console summary

## Testing

- `bash -n` syntax check on both files.
- A small sourced shell assertion: `die` populates `HOSTING_ERROR_MESSAGE`, and
  `dialog_msgbox_height` returns a sane clamped value for 0, few, and many lines.

The existing `wizard/test` harness is Node/`.mjs` and unrelated to this shell
module, so a tiny inline shell assertion is used rather than wiring into it.
