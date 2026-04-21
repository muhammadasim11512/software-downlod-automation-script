# DevOps One-Click Installer

A single script that automatically installs and configures **RabbitMQ**, **Redis**, **Keycloak (Docker Container)**, and **JasperReports Server** on any Linux server.

No manual steps. No technical knowledge needed. Just run one command.

---

## What Gets Installed

| Software       | Type             | Purpose                          | Default Port            |
|----------------|------------------|----------------------------------|-------------------------|
| RabbitMQ       | Native install   | Message broker / queue           | 5672 (app), 15672 (UI)  |
| Redis          | Native install   | Fast in-memory cache             | 6379                    |
| Keycloak       | Docker container | User login / SSO / OAuth2        | 8080                    |
| JasperReports  | Native install   | Reports and dashboards           | 8081                    |
| Docker         | Auto installed   | Required to run Keycloak         | —                       |
| Java 17        | Auto installed   | Required by JasperReports        | —                       |

---

## Supported Linux Systems

| Operating System          | Versions        |
|---------------------------|-----------------|
| Ubuntu                    | 20, 22, 24      |
| Debian                    | 11, 12          |
| Kali Linux                | Latest          |
| CentOS / RHEL             | 7, 8, 9         |
| Rocky Linux / AlmaLinux   | 8, 9            |
| Fedora                    | 38+             |

---

## Requirements

- Linux server (see supported list above)
- sudo or root access
- Internet connection

That is all. Script installs everything else automatically.

---

## How To Run

### Method 1 — One Command (No Clone Needed)

```bash
curl -fsSL https://raw.githubusercontent.com/muhammadasim11512/software-downlod-automation-script/main/install.sh | sudo bash
```

### Method 2 — With Git Clone

```bash
git clone https://github.com/muhammadasim11512/software-downlod-automation-script.git
cd software-downlod-automation-script
sudo bash install.sh
```

---

## All Commands

```bash
# Install everything
sudo bash install.sh

# One liner without clone
curl -fsSL https://raw.githubusercontent.com/muhammadasim11512/software-downlod-automation-script/main/install.sh | sudo bash

# Skip specific services
sudo bash install.sh --skip-rabbitmq
sudo bash install.sh --skip-redis
sudo bash install.sh --skip-keycloak
sudo bash install.sh --skip-jasper

# Skip multiple services
sudo bash install.sh --skip-keycloak --skip-jasper
sudo bash install.sh --skip-rabbitmq --skip-redis

# Run smoke tests only — no install
sudo bash install.sh --test-only

# Show help
sudo bash install.sh --help
```

---

## What Happens Step by Step

```
Step 1  →  Check you are running as root
Step 2  →  Detect Linux OS automatically (Ubuntu, Kali, CentOS, etc.)
Step 3  →  Check internet connection
Step 4  →  Install prerequisites (curl, wget, Java 17)
Step 5  →  Install RabbitMQ + Erlang + enable management UI
Step 6  →  Install Redis + bind to localhost (secure)
Step 7  →  Install Docker automatically
Step 8  →  Pull and run Keycloak as Docker container
Step 9  →  Download and install JasperReports Server
Step 10 →  Print final summary with all URLs and credentials
Step 11 →  Run smoke tests — verify every service is working
```

---

## Final Result — What You See at the End

```
╔══════════════════════════════════════════════════════════════╗
║              Installation Complete!                          ║
╚══════════════════════════════════════════════════════════════╝

  Service            URL / Port                         Credentials
  ───────────────────────────────────────────────────────────────────────
  RabbitMQ           AMQP → localhost:5672
                     UI   → http://localhost:15672        guest / guest
  Redis              Port → localhost:6379               No password (localhost only)
  Keycloak (Docker)  UI   → http://localhost:8080         admin / admin
  JasperReports      UI   → http://localhost:8081/jasperserver  jasperadmin / jasperadmin
  ───────────────────────────────────────────────────────────────────────

  Note: Replace 'localhost' with your server IP to access from browser.

  Useful Commands:
  Keycloak  → docker ps | docker logs keycloak | docker restart keycloak
  RabbitMQ  → systemctl status rabbitmq-server
  Redis     → systemctl status redis-server
```

---

## Default Credentials

| Service       | Username    | Password    | Notes                        |
|---------------|-------------|-------------|------------------------------|
| RabbitMQ UI   | guest       | guest       | Change after install         |
| Keycloak      | admin       | admin       | Change after first login     |
| JasperReports | jasperadmin | jasperadmin | Change after first login     |
| Redis         | —           | No password | Localhost only — secure      |

---

## Access Your Services

Replace `YOUR_SERVER_IP` with your actual server IP address:

| Service       | URL                                           |
|---------------|-----------------------------------------------|
| RabbitMQ UI   | http://YOUR_SERVER_IP:15672                   |
| Keycloak      | http://YOUR_SERVER_IP:8080                    |
| JasperReports | http://YOUR_SERVER_IP:8081/jasperserver        |
| Redis         | localhost:6379 (local access only)            |

---

## Manage Keycloak Docker Container

```bash
# Check if running
docker ps

# View logs
docker logs keycloak

# Restart
docker restart keycloak

# Stop
docker stop keycloak

# Start
docker start keycloak

# Remove and reinstall
docker rm -f keycloak
sudo bash install.sh --skip-rabbitmq --skip-redis --skip-jasper
```

---

## Manage Other Services

```bash
# RabbitMQ
systemctl status rabbitmq-server
systemctl restart rabbitmq-server
systemctl stop rabbitmq-server

# Redis
systemctl status redis-server
systemctl restart redis-server
systemctl stop redis-server
```

---

## Security Features

| Feature                 | Details                                                      |
|-------------------------|--------------------------------------------------------------|
| Redis localhost only    | Redis only accepts connections from the same server          |
| Keycloak Docker         | Runs in isolated container — no host system access           |
| Auto port switching     | Finds next free port if default port is busy                 |
| Keycloak restart policy | Container auto-restarts if it crashes                        |
| Java sandboxed          | JasperReports runs with limited JVM memory settings          |

---

## Safety Features

| Feature              | What It Does                                                    |
|----------------------|-----------------------------------------------------------------|
| Idempotent           | Safe to run multiple times — already running services skipped   |
| Download retry       | Failed downloads retry 3 times automatically                    |
| Docker auto install  | Docker installed automatically before Keycloak                  |
| Auto start on reboot | All services start automatically when server restarts           |
| Built-in smoke tests | Verifies every service is working after install                 |
| Clear error messages | Shows exactly what failed and how to fix it                     |

---

## Troubleshooting

### RabbitMQ not starting
```bash
journalctl -u rabbitmq-server -n 50
sudo systemctl restart rabbitmq-server
```

### Redis not starting
```bash
journalctl -u redis-server -n 50
sudo systemctl restart redis-server
```

### Keycloak container not running
```bash
docker logs keycloak
docker restart keycloak
```

### Check all ports
```bash
ss -tlnp | grep -E '5672|6379|8080|8081|15672'
```

### Re-run installer
```bash
sudo bash install.sh
```

### Run tests only
```bash
sudo bash install.sh --test-only
```

---

## Project Structure

```
software-downlod-automation-script/
├── install.sh    ← The only file you need
└── README.md     ← This file
```

---

## License

MIT — free to use, modify, and distribute.
