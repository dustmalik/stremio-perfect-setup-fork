---
layout: guide
title: "🖥️ Self Hosting"
---

# 🖥️ Self Hosting

This guide covers running personal instances of **AIOStreams**, **AIOMetadata**, and **AIOManager** on a VPS using the `hosting/` scripts. The great news is that almost everything is automated. You only answer a few questions, and the scripts take care of the rest. Let's walk through this step by step.

## 🤔 Why Self Host?

* **Your own private URLs**: You get exclusive access to your addon instances, not shared with anyone else
* **No rate limits**: Public shared instances sometimes have rate limiting. Your own instance gives you full access without those constraints
* **Full control over your configuration**: Everything is yours to customize, update, and manage as you see fit
* **Easy updates, backups, and restores**: The setup scripts make it simple to update your stack, back it up, and restore it on a new server if needed
* **Privacy and independence**: Your data stays on your own server, giving you complete control and peace of mind

## 🧰 What You Will Need

* **Linux VPS** (a cheap cloud server from providers like Hetzner, Vultr, or DigitalOcean where you can rent compute power by the hour)
* **SSH access** (the standard way to connect to a remote server from your terminal)
* **Domain name** (for public HTTPS URLs like `aiostreams.example.com`; optional but recommended for a clean setup)
* **Cloudflare account** (only if you want Cloudflare DDNS to automatically update DNS records when your server IP changes; otherwise optional)
* **Supabase account** (only if you want a cloud Postgres database instead of local SQLite files; fully optional, we will explain this later)

The setup scripts guide you step by step through everything. You do not need to understand Docker, DNS, or server administration beforehand.

## 🔗 Step 1: Connect to Your VPS

### Sub step A: Prepare SSH Alias on Your Local Machine

Start by preparing an easy SSH shortcut on your own computer (not the VPS yet).

Run this command in your terminal:

```bash
./hosting/steps/prepare-ssh.sh
```

This script will ask you for:
* Your VPS IP address
* Your SSH username (often `root`)
* Whether to generate a new SSH key or use an existing one
* What alias name you want (we recommend something like `streaming`)

After running the script, you will see instructions to copy your public key to the VPS. Usually this looks like:

```bash
ssh-copy-id -i ~/.ssh/streaming.pub root@YOUR_VPS_IP
```

This command copies your SSH public key to the VPS so you can log in without typing a password.

**Important:** The command in Step 1A runs on your local machine (your laptop/desktop). Starting with Step 1B, all remaining commands in this guide run on the VPS.

### Sub step B: Test Your Connection

Once the public key is on the VPS, test your connection by running:

```bash
ssh streaming
```

If this works, you are now connected to the VPS and all remaining commands in this guide should be run here.

## 📥 Step 2: Download the Setup Scripts

The `init.sh` script bootstraps the entire `hosting/` folder onto your VPS.

1. Copy `init.sh` to the VPS, or clone the repository and navigate to it. You can either:
   * Download just `init.sh` and run it, or
   * Clone the full repository and navigate to the `hosting/` folder

2. Make the script executable:

```bash
chmod +x init.sh
```

3. Run the bootstrapper:

```bash
./init.sh
```

This lightweight script clones only the `hosting/` folder from the repository and places it in your current directory. It will not download the entire repository, keeping things clean and fast.

After it finishes, move into the hosting directory:

```bash
cd hosting
```

That is the only manual download you need to do. Everything else is handled by the main setup script.

## 🚀 Step 3: Run the Setup

Start the guided setup with:

```bash
./main.sh
```

This launches a visual checklist interface using `whiptail`. If `whiptail` is not installed, the script will auto install it. If that fails, it falls back to simple terminal prompts.

The setup moves through 12 phases. Here is what each one does:

1. **Phase 1: SSH Preparation Offer**: The script may ask if you want to set up SSH again. Skip this if you already have working SSH access.

2. **Phase 2: Docker Setup**: Installs Docker and Docker Compose if not already present. The script asks for confirmation before proceeding.

3. **Phase 3: Deployment Target**: Asks where you want the Docker files to live (usually something like `/opt/streaming`). If a previous setup already exists there, the script offers to continue from it or overwrite it.

4. **Phase 4: Template Fetch**: Downloads the upstream Docker configuration into a temporary work area for staging.

5. **Phase 5: Module Selection**: Shows a checklist of addons and services you can enable or disable. Required modules like Traefik cannot be toggled off.

6. **Phase 6: Config Staging**: Copies the selected module configs into a safe staging area where they can be reviewed or edited before deployment.

7. **Phase 7: Core Environment Questions**: Asks for timezone, domain name, and Let's Encrypt email address.

8. **Phase 8: Module Automation**: Runs module specific setup for things like Cloudflare DDNS or Supabase configuration.

9. **Phase 9: Manual Review**: Pauses and shows you where the staged files are. You can inspect them before deployment.

10. **Phase 10: Deployment Confirmation**: Asks for final confirmation before copying files into the Docker directory.

11. **Phase 11: Backup ZIP**: Creates a backup of your configuration for safekeeping.

12. **Phase 12: Start Stack**: Asks if you want to start the Docker containers now.

The script pauses before any destructive steps and always asks for confirmation first.

## 🔑 The Values You Will Need

When the script runs, it will prompt you for several values. Here is what each one means:

**Timezone (TZ)**

Your server timezone, for example `Europe/Berlin` or `America/New_York`. Just pick the timezone closest to you or where your VPS is located. The script shows a list to choose from.

**Domain (DOMAIN)**

Your base domain, for example `example.com`. All addon URLs will be subdomains like `aiostreams.example.com` and `aiometadata.example.com`. If you do not have a domain yet, try registrars like Namecheap or Porkbun. You can skip this for now and configure it later.

**Let's Encrypt Email (LETSENCRYPT_EMAIL)**

Your email address. Traefik (the reverse proxy) uses this to request free SSL certificates via Let's Encrypt so your services get HTTPS. Just enter your email; nothing else is needed.

**Cloudflare API Token (only if using Cloudflare DDNS)**

If you want Cloudflare DDNS to automatically update your DNS records when your server IP changes, you need a token. To get it:

1. Log in to your Cloudflare dashboard
2. Go to "My Profile" then "API Tokens"
3. Click "Create Token"
4. Use the "Edit zone DNS" template
5. Set "Zone Resources" to your domain
6. Copy the token shown (you can only see it once, so save it somewhere safe)

If you do not use Cloudflare DDNS, you will manually create DNS A records pointing each subdomain to your server IP after setup finishes. The script shows exactly which records to create.

## 📦 Picking Your Modules

During Phase 5, you will see a checklist where you toggle modules with Space and confirm with Enter.

**Required modules** are always included and cannot be toggled off:
* **Traefik**: the reverse proxy that handles HTTPS and routes traffic to your services

**Optional modules** you can enable or disable based on your needs:
* **AIOStreams**, **AIOMetadata**, **AIOManager**: the three main Stremio addons. Pick the ones you want to self host.
* **Authelia**: adds a login screen to protect your services from unauthorized access. Highly recommended.
* **Cloudflare DDNS**: keeps your DNS records updated automatically if your server IP changes. Only useful if your domain is on Cloudflare.
* **Honey**: a visual homepage showing all your services with clickable links. Nice to have for easy access.
* **StremThru**: a Debrid proxy layer for advanced users. Optional.

Do not worry about picking the wrong modules. You can always add or remove modules later by rerunning the script (see the "Other Things the Script Can Do" section below).

## ⚙️ What the Script Sets Up Automatically

After you select your modules, the script runs automated hooks for each addon. You do not need to edit any config files manually.

**AIOStreams**

The script automatically injects the correct template URLs for the Stremio Perfect Setup guide templates, sets the featured template, configures torrent URL mirrors to working sources, and generates a secret key for your instance. It also asks if you want to add proxy authentication (a username and password to restrict access to just you).

**AIOManager and AIOMetadata**

Encryption keys and JWT secrets are generated automatically.

**Authelia**

All three cryptographic secrets (session key, storage key, JWT key) are generated automatically. You only need to set your admin username, display name, email, and password.

**Honey**

The dashboard configuration is automatically filtered to show only the services you enabled, with correct URLs already filled in.

**Secrets and Keys**

All security secrets are autogenerated using `openssl`. You never come up with them yourself.

## 🗄️ Supabase: A Better Database (Optional)

By default, **AIOStreams**, **AIOMetadata**, and **AIOManager** store data in local SQLite files inside containers. This works fine for personal use. However, Supabase is a free hosted Postgres service that gives you a more robust and portable database, making backups easier and more reliable.

Here is the clever part: instead of needing three separate Supabase projects, the script creates one isolated schema and one database user per addon inside a single Supabase project. Each addon only sees its own data, so they stay completely separate.

To set up Supabase:

1. Create a free account at supabase.com and start a new project
2. Once your project is ready, go to "Project Settings" then "Database"
3. Under "Connection string", copy the "URI" value (it looks like `postgresql://postgres:[YOUR-PASSWORD]@...`)
4. When the script asks for the Supabase connection string, paste ONLY the URI value (the `postgresql://...` string), not any surrounding text
5. The script will ask for the database password separately (the `[YOUR-PASSWORD]` part from the connection string)
6. Everything else is automated: schemas, roles, and permissions are created by the included SQL scripts

If you skip Supabase, everything uses local SQLite. You can always add Supabase later by rerunning the script in modify mode.

## 🔄 Other Things the Script Can Do

After your first setup, the script can do much more. Here are the other modes:

**Back up your setup**

```bash
./main.sh --backup
```

Creates a ZIP file with all your configuration. Keep this somewhere safe. You can use it to restore your exact setup on a new server in minutes.

**Restore from a backup**

```bash
./main.sh /path/to/your-backup.zip
```

Copy your backup ZIP file to the VPS first, then run this command from inside the hosting folder. The script imports the backed up configuration, lets you pick modules, and redeploys everything. Great for migrating to a new VPS.

**Add or remove modules**

If your stack is already running in Docker, the script detects it automatically and switches to modify mode. It imports your current setup, lets you toggle modules on or off, runs hooks only for the changes you made, and does a targeted update without touching things that did not change.

**Quick backup without prompts**

```bash
./main.sh --backup-quick
```

Same as backup mode but uses default paths without asking any questions.

## 🗂️ How the Project Is Structured

*(You do not need to understand this to use the scripts, but here it is if you are curious)*

* **`main.sh`**: The main orchestrator script. All setup phases go through here.

* **`init.sh`**: The bootstrapper that downloads the `hosting/` folder from GitHub onto your VPS.

* **`steps/`**: Individual reusable building blocks like Docker install, template download, backup creation, and deployment. The main script calls these in order.

* **`modules/`**: One script per addon or integration task. Each file handles automated setup for one thing (for example, `aiostreams.sh` sets up AIOStreams defaults, `all.supabase.sh` provisions Supabase schemas). The main script discovers and runs all module files automatically based on which modules you selected. This is where you would add your own automation if you wanted to extend the setup for a custom addon or task.

* **`lib/`**: Shared helper functions used by all scripts for logging, interactive prompts, `.env` file manipulation, ZIP creation, and more.

* **`db/`**: SQL scripts for creating and deleting Supabase schemas. You can run these manually if needed.

* **`configs/`**: Extra config files. For example, `honey.json` is the full service catalog telling Honey which services to show, with icons and URL templates for every supported module.

* **`defaults.env`**: Default values for all configurable settings. These are fallback values when you do not pass a flag to the script.

If you want to understand how a specific addon is configured, look at the `modules/` folder. Each file is self contained and well commented.

## 💡 Notes and Tips

>**📢 NOTES:**
>* *Run `./main.sh` on the VPS itself, not your local machine (unless your local machine is running Docker).*
>* *After the first install, Docker group membership may require a fresh login before Docker works without `sudo`.*
>* *The temporary `.work/` folder used during setup is cleaned up automatically when the script finishes.*
>* *Supabase is entirely optional and can be added later.*
>* *If you want to inspect staged config files before they are deployed, the script pauses at "Phase 9: Manual Review" and shows you exactly where to find them.*

---

[🔙 Back to 📝 1. Accounts Preparation](1-Accounts.md) | [Next to 🎛️ AIOManager ➜](AIOManager-Setup.md)
