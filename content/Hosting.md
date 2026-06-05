---
layout: guide
title: "🖥️ Hosting"
---

# 🖥️ Hosting

Self-hosting is the next level for achieving the ultimate streaming experience. It's totally optional, but it might be necessary in a few cases that we will discuss further below. This guide covers running personal instances of multiple addons and tools on a VPS using the scripts in my [**hosting/**](https://github.com/luckynumb3rs/stremio-perfect-setup/tree/main/hosting) GitHub repo folder. The great news is that I've tried to make it as automated as it can be. You only answer a few questions, and the scripts take care of the rest. Important to note however that you still need to have at least some basic technical skills to go through with this: working with a terminal, a few commands, connecting to a remove server, etc. It's not for everyone, but also most don't need it, so if you feel you have a use case for it, let's walk through it step by step.

## 🤔 Why Self-Host?

* **Your own private instances**: You get exclusive access to your addon instances, not shared with anyone else.
* **No rate limits and reliability issues**: Public shared instances sometimes have rate limiting or may be more prone to downtime or reachability issues. Your own instance gives you full access without those constraints.
* **Full control over your configuration**: Everything is yours to customize, update, and manage as you see fit on an admin level.
* **Easy updates, backups, and restores**: The setup scripts make it simple to update your stack, back it up, and restore it on a new server if needed.
* **Privacy and independence**: Your data stays on your own server, giving you complete control and peace of mind.
* **Usenet**: Last but not least, the king of self-hosting use cases in the Stremio ecosystem. There's really no other/bigger reason for wanting to self-host besides being able to use Usenet, because as it currently stands, it's practically impossible use it reliably without self-hosting. Check out my Usenet section in [**🛠️ Additional Stuff**](7-Additional-Stuff.md#usenet) to learn more.

## 🧰 What You Will Need

* **Server / VPS**: Obviously the most important component for self-hosting, either a local server at home, or a cloud VPS. Check out [**Viren's Guide**](https://guides.viren070.me/selfhosting/oracle) for instructions on how to prepare one of the best free VPS solutions currently around.
* **Domain Name**: Needed for publicly accessing your instances through HTTPS URLs like `aiostreams.yourdomain.com`.
* **Cloudflare Account**: Optional, but highly recommended to protect your server's IP and access by proxying it through Cloudflare, and if you want *Cloudflare DDNS* to automatically update DNS records when you make changes.
* **Supabase Account**: Optional if you want to separate the data layer by storing the tables (currently automated for *AIOStreams*, *AIOMetadata*, and/or *AIOManager*) on a cloud database instead of locally.

>**📢 DISCLAIMER:**
>* The setup scripts guide you step by step through everything. Normally you don't need to understand Docker, DNS, or server administration beforehand. However, as mentioned in the beginning, you do need to have at least some basic technical understanding to be able to work through this, and even debug in case issues arise. These are complex topics and may vary depending on many factors, and I cannot address them all. Please take everything with a grain of salt and tread carefully. 
> This guide and scripts are currently a work in progress. I am not responsible for anything that might happen to your data, server, configurations, or anything else. The files are openly available for anyone to study and tinker with, and I'm doing this for fun and just trying to help. Please don't come to me with any complaints or asking for support on this, I really can't help you.
>* 🙏 This guide is based of the amazing work of [**Viren**](https://guides.viren070.me/selfhosting), and the scripts here actually fetch [**Viren's Docker Templates**](https://github.com/Viren070/docker-compose-template) from GitHub dynamically to make use of the latest configurations and modules and adds the automation layer on top. So a big thanks to **Viren** for all the effort put into the templates.

## 🧭 Two Ways to Run the Setup

The setup script (`main.sh`) is smart about where it runs. When you start it, it asks one simple question first: are you on the VPS, or on your own computer? You pick whichever fits you, and the script handles the rest.

* **From your local computer (recommended for most people):** You run the script on your laptop or desktop. It prepares an SSH key and connection alias, copies the hosting files up to your VPS for you, and then runs the entire setup on the server through that connection. You never have to manually copy files or log in to the VPS yourself.
* **Directly on the VPS:** If you are already logged in to your server (for example after using `init.sh` to download the files there), you run the script on the VPS and it does everything right there. SSH is already taken care of because you used it to get in.

Both paths ask you the exact same setup questions and produce the exact same result. Pick the one that feels most comfortable.

## 💻 Option A: Run It From Your Local Computer (Recommended)

This is the smoothest path. Everything starts and is driven from your own machine.

1. Get the scripts onto your computer. Either clone the repository:

```bash
git clone https://github.com/luckynumb3rs/stremio-perfect-setup.git
cd stremio-perfect-setup
```

   or download just the `hosting/` folder with the bootstrapper (`init.sh`) as shown in Option B below.

2. Start the setup:

```bash
./hosting/main.sh
```

3. When it asks **"Where are you running this?"**, choose **"I am on my local computer"**.

From here the script walks you through everything:

* It helps you create or pick an SSH key and choose a short alias (we recommend `streaming`).
* It reminds you to add that public key to your VPS, either during the provider's instance creation, through their SSH-key panel, or with the `ssh-copy-id` command it shows you, for example:

```bash
ssh-copy-id -i ~/.ssh/streaming.pub root@YOUR_VPS_IP
```

* It checks that it can reach your VPS. If it cannot log in without a password yet, it pauses and tells you exactly what to do, then lets you retry once the key is in place.
* It copies the hosting files up to your VPS automatically.
* It runs the full guided setup on the server, showing you the questions and screens right there in your terminal.

When it finishes, you are back on your local machine and your stack is live on the VPS. That is it.

## 🖥️ Option B: Run It Directly On the VPS

Prefer to work on the server yourself? You can. First get the files onto the VPS, then run the setup there.

### Step 1: Connect to your VPS

Prepare an SSH key and alias on your local machine if you have not already. You can let `main.sh` do it for you (Option A), or run the helper directly:

```bash
./hosting/steps/prepare-ssh.sh
```

This asks whether to generate a new key or reuse one, what to name it, your VPS IP address, your SSH username (often `root`), and an alias. After installing the public key on the VPS, connect with:

```bash
ssh streaming
```

Everything from here runs on the VPS.

### Step 2: Download the setup scripts

The `init.sh` script bootstraps the `hosting/` folder onto your VPS without pulling the whole repository:

```bash
chmod +x init.sh
./init.sh
cd hosting
```

### Step 3: Run the setup

```bash
./main.sh
```

When it asks **"Where are you running this?"**, choose **"I am on the VPS"**. Because you are already on the server, the script skips all the SSH and copying steps and goes straight to the setup.

## 🚀 What the Setup Does

However you started it, once the setup is running on the VPS it launches a visual checklist interface using `whiptail`. If `whiptail` is not installed, the script auto-installs it, and if that fails it falls back to simple terminal prompts.

The setup moves through several phases:

1. **Docker Setup:** Installs Docker and Docker Compose if they are not already present, asking for confirmation first.

2. **Deployment Target:** Asks where the Docker files should live (usually something like `/opt/streaming`). If a previous setup already exists there, it offers to continue from it or overwrite it.

3. **Template Fetch:** Downloads the upstream Docker configuration into a temporary work area for staging.

4. **Module Selection:** Shows a checklist of addons and services to enable or disable. Required modules like Traefik cannot be toggled off.

5. **Config Staging:** Copies the selected module configs into a safe staging area for review.

6. **Core Environment Questions:** Asks for timezone, domain name, and Let's Encrypt email address.

7. **Module Automation:** Runs module-specific setup for things like Cloudflare DDNS or Supabase.

8. **Manual Review:** Pauses and shows you where the staged files are so you can inspect them.

9. **Deployment Confirmation:** Asks for final confirmation before copying files into the Docker directory.

10. **Backup ZIP:** Creates a backup of your configuration for safekeeping.

11. **Start Stack:** Asks if you want to start the Docker containers now.

The script pauses before any destructive step and always asks for confirmation first.

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
* **AIOStreams**, **AIOMetadata**, **AIOManager**: the three main Stremio addons. Pick the ones you want to self-host.
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

If you run this from the VPS, copy your backup ZIP there first. If you run it from your local computer, the script copies the ZIP to the VPS for you. Either way, the script imports the backed up configuration, lets you pick modules, and redeploys everything. Great for migrating to a new VPS.

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
>* *You can start `./main.sh` from either your local computer or the VPS. The script asks which at the start, and when you run it locally it handles SSH and copying the files to the VPS for you automatically.*
>* *After the first install, Docker group membership may require a fresh login before Docker works without `sudo`.*
>* *The temporary `.work/` folder used during setup is cleaned up automatically when the script finishes.*
>* *Supabase is entirely optional and can be added later.*
>* *If you want to inspect staged config files before they are deployed, the script pauses at "Phase 9: Manual Review" and shows you exactly where to find them.*

---

[🔙 Back to 📝 1. Accounts Preparation](1-Accounts.md) | [Next to 🎛️ AIOManager ➜](AIOManager-Setup.md)
