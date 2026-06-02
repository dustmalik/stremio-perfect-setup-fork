# Hosting Guide for Beginners

This `hosting/` folder is a guided setup for turning a fresh VPS into a Docker-based streaming stack.

If you are new to SSH, Docker, or self-hosting in general, use this guide from top to bottom once before you start clicking through the script. The goal is to make the process predictable: first you prepare SSH access, then you get the `hosting/` folder onto the VPS, then you run the main setup script and follow the visual prompts.

## What This Setup Does

The hosting scripts do the heavy lifting for you:

- prepare an SSH key and alias for your VPS
- install Docker and Docker Compose when needed
- fetch the upstream Docker template
- let you choose which modules you want to run
- stage the important config files in an editable area
- ask for the values the stack cannot guess for you
- apply module-specific automation, such as Supabase or Cloudflare adjustments
- deploy the final stack into your Docker directory
- optionally create a restore-friendly backup ZIP
- optionally start the stack right away

The interactive flow is designed to use a visual `whiptail` UI across the whole setup. If `whiptail` is missing, the scripts try to install it automatically first, and only fall back to plain terminal prompts if that installation is not possible.

## Before You Start

You should have these things ready:

- a Linux VPS that will actually run Docker
- SSH access to that VPS from your current machine
- a domain name if you want public HTTPS services through Traefik
- Cloudflare nameservers already active if you plan to use `cloudflare-ddns`
- a Supabase project ready only if you want the AIO modules to use Postgres instead of local SQLite

Important: the `main.sh` script must run on the Linux machine that will host Docker. The easiest way is to SSH into the VPS first, then clone `hosting/` there, and run everything directly on the VPS.

## Step 1: Prepare an SSH Alias

If you already have a clean SSH alias for this VPS and it works, you can skip to Step 2.

If not, run the SSH helper from a machine where you normally open your terminal:

```bash
./hosting/steps/prepare-ssh.sh
```

What it will ask you:

- whether to use an existing SSH key or generate a new one
- what alias name you want, for example `streaming`
- the VPS IP address or hostname
- the SSH username for that VPS, often `root`

What it writes:

- your private key under `~/.ssh/` if you chose to generate one
- a `Host` block inside `~/.ssh/config`
- `HostName`, `User`, and `IdentityFile` entries for the alias

When it finishes, it will show you what to do next. This step only prepares your local SSH client. It does not magically install the key on the server for you.

You still need to place the public key on the VPS:

1. Copy the contents of the generated `.pub` file.
2. Add that public key to `~/.ssh/authorized_keys` for the target VPS user.
3. After that, test the alias with `ssh your-alias`.

If `ssh-copy-id` is available on your machine, the helper will also show you a command like this:

```bash
ssh-copy-id -i ~/.ssh/streaming.pub root@YOUR_VPS_IP
```

After the key is installed on the VPS, connect with the alias:

```bash
ssh streaming
```

From this point onward, the rest of the guide assumes you are inside the VPS shell.

## Step 2: Download Only the `hosting/` Folder

If you do not want the whole repository on the VPS, you can pull only the `hosting/` part.

Run these commands on the VPS after logging in:

```bash
git clone --filter=blob:none --sparse https://github.com/luckynumb3rs/stremio-perfect-setup.git temp-repo
cd temp-repo
git sparse-checkout set hosting
cd ..
cp -r temp-repo/hosting ./hosting
rm -rf temp-repo
cd hosting/
```

Otherwise copy `hosting/init.sh` to the working folder you want and execute it with `./init.sh`.
(You may have to make it executable first with `chmod +x init.sh`)

What this does:

- clones the repository in a lightweight way
- tells Git to fetch only the `hosting/` folder
- copies that folder into your current VPS directory as a standalone working folder
- removes the temporary clone when done and takes you to `hosting/`

## Step 3: Run the Main Setup Script

Start the guided setup with:

```bash
./main.sh
```

If `whiptail` is not installed yet, the script will try to install it automatically so the whole setup can stay inside the visual interface. Only if that cannot be done will it fall back to regular terminal prompts.

## Step 4: Follow the Setup Phases

The script is divided into clear phases. Knowing what each phase means makes the whole process much less intimidating.

### Phase 1: SSH Preparation Offer

If you launched `./main.sh` interactively, it may ask whether you want to run the SSH helper first.

Use this when:

- you have not set up an SSH alias yet
- you are not sure your VPS key setup is correct

Skip it when:

- `ssh your-alias` already works
- you already prepared SSH in Step 1

### Phase 2: Docker Setup

This is one of the important confirmation points.

If Docker is not already installed, the script will clearly tell you that it is about to:

- add Docker's official package repository
- install Docker Engine
- install the Docker Compose plugin
- add your current user to the `docker` group

You must confirm before it proceeds.

Good to know:

- the main setup now usually asks for `sudo` once near the beginning so later privileged steps can continue more smoothly
- this may ask for `sudo`
- after being added to the `docker` group, some systems need a logout/login before Docker works without `sudo`
- if Docker is already installed, this phase simply reports that and moves on

### Phase 3: Template Fetch

The script downloads the upstream Docker template into a temporary work area under `hosting/.work/`.

This is intentional. It does not directly edit your final deployment folder first. Instead, it prepares everything in a staging area so the script can validate and modify files before deployment.

### Phase 4: Module Selection

This is the checklist UI you mentioned.

You will see:

- required modules, which stay enabled automatically
- optional modules, which you can toggle on or off

Controls in the checklist:

- `Up` and `Down` move through the list
- `Space` toggles a module
- `Tab` moves between buttons
- `Enter` confirms

Choose only what you actually want to run. More modules means more configuration, more containers, and more moving parts.

### Phase 5: Config Staging

After module selection, the script copies the relevant config files into `hosting/.work/config/`.

This is the safe editing zone.

That means:

- the upstream template is still untouched
- the final deployment directory is still untouched
- all automatic edits happen in staging first

### Phase 6: Core Environment Questions

The script will then ask for the core values that cannot be guessed automatically:

- `TZ`
- `DOCKER_DIR`
- `DOMAIN`
- `LETSENCRYPT_EMAIL`

What they mean:

- `TZ`: your server timezone, for example `Europe/Berlin`
- `DOCKER_DIR`: where the final Docker stack should live, usually `/opt/docker`
- `DOMAIN`: the base domain used for public hostnames
- `LETSENCRYPT_EMAIL`: the email address used for certificate notices

The script also fills in:

- `PUID`
- `PGID`
- generated Authelia secrets

### Phase 7: Module Automation

Now the script applies module-specific logic based on what you selected.

Examples:

- `cloudflare-ddns` asks for a Cloudflare API token and adjusts DNS challenge settings
- AIO modules can offer Supabase instead of local SQLite
- some modules stage extra files or update hostnames automatically

These prompts now use the same visual UI style when possible.

Important: if you enable `cloudflare-ddns` but do not provide a token, the script disables that module instead of leaving it half-configured.

### Phase 8: Manual Review

Before deployment, the script pauses and tells you where the staged files are:

```bash
hosting/.work/config/
```

This is your chance to inspect the generated configuration.

Use this pause when:

- you want to double-check domains
- you want to edit module env files by hand
- you want to compare staged values with external service dashboards

Do not rename the staged files. Their names are mapped back to their original destinations automatically.

### Phase 9: Deployment Confirmation

This is another important confirmation point.

Before touching the final Docker folder, the script now explicitly asks whether it should deploy into your chosen `DOCKER_DIR`.

If you confirm, it will:

- restore the staged files back into the prepared template
- sync that prepared tree into the target Docker directory
- prune out unselected modules so the final tree contains only what you chose

### Phase 10: Backup ZIP

After deployment, the script can create a backup ZIP of the prepared configuration.

For most people, say yes.

Why it matters:

- it gives you an easy restore point
- it is useful before later experiments or upgrades
- it preserves the selected modules and the staged config files in a format the script can import again

### Phase 11: Start the Stack

The script now asks before starting Docker Compose.

If you confirm, it will:

1. start the required profile first
2. start the rest of the configured stack

If you are not ready yet, you can decline here, review files again, and start manually later.

## Step 5: Read the Final Summary

At the end, the script prints a summary with things like:

- where the stack was deployed
- your detected public IP
- which hostnames were generated
- whether Cloudflare DDNS is handling them, or whether you need to create DNS A records manually

Read this part carefully. It tells you what still has to happen outside the script, especially around DNS.

## Typical First-Time Workflow

If you just want the shortest possible beginner path, this is the usual order:

1. Run `./hosting/steps/prepare-ssh.sh` on your own machine.
2. Install the `.pub` key on the VPS.
3. Connect with `ssh your-alias`.
4. Run the sparse checkout commands on the VPS.
5. `cd hosting`
6. Run `./main.sh`
7. Confirm Docker installation if needed.
8. Select your modules.
9. Fill in timezone, Docker directory, domain, and Let's Encrypt email.
10. Complete any module-specific prompts such as Cloudflare or Supabase.
11. Review the staged config.
12. Confirm deployment.
13. Create the backup ZIP.
14. Start the stack.
15. Finish any DNS work shown in the final summary.

## Useful Commands

Run the full guided setup:

```bash
./main.sh
```

Import a previously created backup ZIP:

```bash
./main.sh /path/to/streaming-backup.zip
```

Create a backup from an existing deployed Docker directory:

```bash
./main.sh --backup
```

Create that backup non-interactively with defaults:

```bash
./main.sh --backup-quick
```

Test the file-preparation flow without making system-level changes:

```bash
./main.sh --dry-run --skip-ssh
```

## Common Notes and Pitfalls

- Run `./main.sh` on the VPS, not on your laptop, unless your laptop is the machine that will host Docker.
- If Docker group membership was just added, a fresh login may be needed before Docker works without `sudo`.
- `cloudflare-ddns` only makes sense when the domain is actually managed by Cloudflare.
- Supabase is optional. If you do not configure it, the supported addons stay on their default SQLite setup.
- The temporary work directory is cleaned up at the end, so if you want to keep artifacts from a dry run, send the backup ZIP to a directory outside `hosting/.work/`.

## Folder Layout

- `main.sh`: the main guided setup entrypoint
- `steps/`: reusable setup steps such as SSH prep, Docker install, deploy, backup, and start
- `modules/`: addon-specific automation hooks
- `db/`: Supabase-related helper scripts and SQL
- `lib/`: shared Bash helpers for prompts, staging, and template logic
- `defaults.env`: default values used by the scripts

## If You Want to Run Non-Interactively Later

Once you already understand the flow, you can pass values directly through flags such as:

- `--modules`
- `--timezone`
- `--docker-dir`
- `--domain`
- `--letsencrypt-email`
- `--cloudflare-api-token`
- `--supabase-connection-string`
- `--supabase-db-password`
- `--skip-review`

That is useful for repeat deployments, but for a first run, the guided interactive flow is the safer path.
