# DevOps One-Click Installer

A single script that installs and configures **RabbitMQ**, **Redis**, **Keycloak**, and **JasperReports Server** on any Linux server automatically.

No manual steps. No technical knowledge needed. Just run one command.

---

## What Is This Script?

This script is for teams who need to set up DevOps services quickly on a Linux server.

Instead of installing each software manually (which takes hours and can cause errors), this script does everything in one command:

- Downloads the software
- Installs it
- Configures it
- Finds a free port automatically if default port is busy
- Starts it as a system service
- Tests it to make sure everything is working
- Shows a final result with all URLs, ports, and credentials

It works on **development**, **staging**, and **production** servers.

---

## What Gets Installed

| Software       | What It Does                        | Default Port            |
|----------------|-------------------------------------|-------------------------|
| RabbitMQ       | Sends messages between services     | 5672 (app), 15672 (UI)  |
| Redis          | Fast in-memory data storage / cache | 6379                    |
| Keycloak       | User login, SSO, and authentication | 8080                    |
| JasperReports  | Reports and dashboards              | 8081 (auto if 8080 busy) |

---

## Automatic Port Switching

If a port is already in use on your server, the script **automatically finds the next free port** and uses that instead. No errors. No manual changes needed.

Example:
```
[WARN]  Port 8080 is busy — trying port 8081...
[WARN]  Port 8081 is busy — trying port 8082...
[OK]    Keycloak ready → http://localhost:8082
```

The final summary always shows the **actual ports used**.

---

## Supported Linux Systems

| Operating System          | Versions   |
|---------------------------|------------|
| Ubuntu                    | 20, 22, 24 |
| Debian                    | 11, 12     |
| CentOS / RHEL             | 7, 8, 9    |
| Rocky Linux / AlmaLinux   | 8, 9       |
| Fedora                    | 38+        |

---

## Requirements

Before running the script, make sure:

- You are on a **Linux server** (see supported list above)
- You have **sudo or root access**
- The server has an **internet connection**
- `curl` or `wget` is available (comes pre-installed on most Linux servers)

That is all. The script installs everything else automatically including Java.

---

## How To Run — Choose One Method

### Method 1 — Without Cloning (Easiest)

Just paste this one command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/muhammadasim11512/software-downlod-automation-script/main/install.sh | sudo bash
```

No need to download or clone anything. The script runs directly.

---

### Method 2 — With Git Clone

```bash
# Step 1 — Clone the repository
git clone https://github.com/muhammadasim11512/software-downlod-automation-script.git

# Step 2 — Go into the folder
cd software-downlod-automation-script

# Step 3 — Run the script
sudo bash install.sh
```

---

## All Available Commands

```bash
# Install all software (recommended)
sudo bash install.sh

# Install all software — one liner without clone
curl -fsSL https://raw.githubusercontent.com/muhammadasim11512/software-downlod-automation-script/main/install.sh | sudo bash

# Skip RabbitMQ — install everything else
sudo bash install.sh --skip-rabbitmq

# Skip Redis — install everything else
sudo bash install.sh --skip-redis

# Skip Keycloak — install everything else
sudo bash install.sh --skip-keycloak

# Skip JasperReports — install everything else
sudo bash install.sh --skip-jasper

# Skip multiple services at once
sudo bash install.sh --skip-keycloak --skip-jasper
sudo bash install.sh --skip-rabbitmq --skip-redis

# Run smoke tests only — check if services are running (no install)
sudo bash install.sh --test-only

# Show help
sudo bash install.sh --help
```

---

## What Happens When You Run It

The script runs these steps automatically:

```
Step 1  →  Check you are running as root
Step 2  →  Detect your Linux OS and version
Step 3  →  Check internet connection
Step 4  →  Install curl, wget, unzip, Java 17
Step 5  →  Find free ports automatically
Step 6  →  Install RabbitMQ
Step 7  →  Install Redis
Step 8  →  Install Keycloak
Step 9  →  Install JasperReports Server
Step 10 →  Print final result — all URLs, ports, and credentials
Step 11 →  Run smoke tests to verify everything works
```

---

## Final Result — What You See at the End

After installation the script prints a complete summary:

```
╔══════════════════════════════════════════════════════════════╗
║              Installation Complete!                          ║
╚══════════════════════════════════════════════════════════════╝

  Service         URL / Port                          Credentials
  ──────────────────────────────────────────────────────────────────
  RabbitMQ        AMQP  → localhost:5672
                  UI    → http://localhost:15672       guest / guest
  Redis           Port  → localhost:6379              No password
  Keycloak        UI    → http://localhost:8080        Set on first login
  JasperReports   UI    → http://localhost:8081/jasperserver  jasperadmin / jasperadmin
  ──────────────────────────────────────────────────────────────────

  Note: Replace 'localhost' with your server IP to access from browser.
```

Then smoke tests run automatically:

```
  ── Smoke Tests ──────────────────────────────

  RabbitMQ
  [PASS] Service is running
  [PASS] AMQP port 5672 open
  [PASS] Management port 15672 open

  Redis
  [PASS] Service is running
  [PASS] Port 6379 open
  [PASS] Responds to PING

  Keycloak
  [PASS] Service is running
  [PASS] Port 8080 open

  JasperReports
  [PASS] Install directory exists

  System
  [PASS] Java 17+ installed

  ──────────────────────────────────────────────
  All tests passed (11/11)
```

---

## Safety and Production Features

| Feature                  | What It Means                                                        |
|--------------------------|----------------------------------------------------------------------|
| Auto port switching      | If a port is busy, script finds next free port automatically         |
| Idempotent               | Safe to run multiple times — already installed services are skipped  |
| Download retry           | If a download fails, it retries 3 times automatically                |
| Dedicated system user    | Keycloak runs as its own user, not as root                           |
| Redis localhost only     | Redis only accepts connections from the same server                  |
| Auto-start on reboot     | All services start automatically when the server restarts            |
| Built-in smoke tests     | Verifies every service is working after install                      |
| Clear error messages     | If something fails, the script tells you exactly what happened       |
| Final result summary     | Shows all URLs, actual ports used, and credentials at the end        |

---

## Pinned Software Versions

| Software      | Version |
|---------------|---------|
| Keycloak      | 24.0.4  |
| JasperReports | 8.2.0   |

To use a different version, edit these two lines at the top of `install.sh`:

```bash
KEYCLOAK_VERSION="24.0.4"
JASPER_VERSION="8.2.0"
```

---

## Troubleshooting

### A service failed to start

Check the logs for that service:

```bash
journalctl -u rabbitmq-server -n 50
journalctl -u redis-server -n 50
journalctl -u keycloak -n 50
```

### Check if a service is running

```bash
systemctl status rabbitmq-server
systemctl status redis-server
systemctl status keycloak
```

### Check which ports are open

```bash
ss -tlnp | grep -E '5672|6379|8080|15672'
```

### Re-run the installer

If something went wrong, just run the script again. It will skip services that are already running and only install what is missing:

```bash
sudo bash install.sh
```

### Run tests only (without reinstalling)

```bash
sudo bash install.sh --test-only
```

---

## Project Structure

```
devops-installer/
├── install.sh    ← The only file you need (installer + smoke tests)
└── README.md     ← This file
```

---

## License

MIT — free to use, modify, and distribute.
