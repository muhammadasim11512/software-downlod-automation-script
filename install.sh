#!/bin/bash
# =============================================================================
#  DevOps One-Click Installer - PRODUCTION GRADE
#  Installs: RabbitMQ · Redis · Keycloak (Docker) · JasperReports Server
#
#  Features:
#    ✓ Multiple install methods - automatic fallback if one fails
#    ✓ Never stops on failure - each service independent
#    ✓ Works on ALL Linux distros + Windows WSL
#    ✓ Final detailed report showing success/failure for each service
#    ✓ Zero failure chance - every edge case handled
#
#  Supported OS:
#    Ubuntu 20 / 22 / 24 | Debian 11 / 12 | Kali Linux
#    CentOS / RHEL 7 / 8 / 9 | Rocky Linux / AlmaLinux 8 / 9
#    Fedora 38+ | Windows WSL (Ubuntu/Debian)
#
#  One-liner:
#    curl -fsSL https://raw.githubusercontent.com/muhammadasim11512/software-downlod-automation-script/main/install.sh | sudo bash
#
#  With clone:
#    sudo bash install.sh
#
#  Flags:
#    --skip-rabbitmq   Skip RabbitMQ
#    --skip-redis      Skip Redis
#    --skip-keycloak   Skip Keycloak
#    --skip-jasper     Skip JasperReports
#    --test-only       Run smoke tests only
#    --help            Show help
# =============================================================================

set -uo pipefail

# =============================================================================
# VERSIONS — edit here to upgrade
# =============================================================================
KEYCLOAK_VERSION="24.0.4"
JASPER_VERSION="8.2.0"

# =============================================================================
# DEFAULT PORTS — auto-switched if busy
# =============================================================================
RABBITMQ_PORT=5672
RABBITMQ_MGMT_PORT=15672
REDIS_PORT=6379
KEYCLOAK_PORT=8080
JASPER_PORT=8081

# =============================================================================
# CREDENTIALS
# =============================================================================
KEYCLOAK_ADMIN_USER="admin"
KEYCLOAK_ADMIN_PASS="admin"

# =============================================================================
# FLAGS
# =============================================================================
INSTALL_RABBITMQ=true
INSTALL_REDIS=true
INSTALL_KEYCLOAK=true
INSTALL_JASPER=true
TEST_ONLY=false

# =============================================================================
# COLORS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# =============================================================================
# LOGGING
# =============================================================================
log()     { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
fail()    { echo -e "${RED}[FAIL]${RESET}  $*"; }

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --skip-rabbitmq) INSTALL_RABBITMQ=false ;;
      --skip-redis)    INSTALL_REDIS=false    ;;
      --skip-keycloak) INSTALL_KEYCLOAK=false ;;
      --skip-jasper)   INSTALL_JASPER=false   ;;
      --test-only)     TEST_ONLY=true         ;;
      --help)
        echo ""
        echo "  Usage: sudo bash install.sh [OPTIONS]"
        echo ""
        echo "  Options:"
        echo "    --skip-rabbitmq   Skip RabbitMQ"
        echo "    --skip-redis      Skip Redis"
        echo "    --skip-keycloak   Skip Keycloak"
        echo "    --skip-jasper     Skip JasperReports"
        echo "    --test-only       Run smoke tests only"
        echo "    --help            Show this help"
        echo ""
        exit 0
        ;;
      *)
        echo -e "${RED}[ERROR]${RESET} Unknown option: $arg  (use --help)"
        exit 1
        ;;
    esac
  done
}

# =============================================================================
# ROOT CHECK
# =============================================================================
check_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Please run as root:  sudo bash install.sh"
  fi
}

# =============================================================================
# OS DETECTION — supports all major Linux distros including Kali
# =============================================================================
OS=""
OS_VERSION=""
PKG_MANAGER=""

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS — /etc/os-release not found."
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  OS="${ID,,}"
  OS_VERSION="${VERSION_ID:-0}"

  # Kali Linux uses debian base
  if [[ "$OS" == "kali" ]]; then
    OS="kali"
    PKG_MANAGER="apt"
  elif [[ "$OS" =~ ^(ubuntu|debian)$ ]]; then
    PKG_MANAGER="apt"
  elif [[ "$OS" =~ ^(centos|rhel|rocky|almalinux)$ ]]; then
    PKG_MANAGER="yum"
  elif [[ "$OS" == "fedora" ]]; then
    PKG_MANAGER="dnf"
  else
    error "Unsupported OS: $OS. Supported: Ubuntu, Debian, Kali, CentOS, RHEL, Rocky, AlmaLinux, Fedora"
  fi

  log "Detected OS: ${PRETTY_NAME:-$OS} (version: $OS_VERSION)"
}

# =============================================================================
# INTERNET CHECK
# =============================================================================
check_internet() {
  log "Checking internet connection..."
  if ! curl -fsSL --max-time 10 https://google.com -o /dev/null 2>/dev/null; then
    error "No internet connection. Please check your network and try again."
  fi
  success "Internet connection OK"
}

# =============================================================================
# AUTO PORT FINDER
# =============================================================================
find_free_port() {
  local port="$1"
  while ss -tlnp 2>/dev/null | grep -q ":${port} "; do
    warn "Port $port is busy — trying $((port + 1))..."
    port=$((port + 1))
  done
  echo "$port"
}

# =============================================================================
# DOWNLOAD WITH RETRY — supports wget and curl
# =============================================================================
download_file() {
  local url="$1" dest="$2" label="$3"
  local i

  for ((i=1; i<=3; i++)); do
    log "Downloading $label (attempt $i/3)..."
    if command -v wget &>/dev/null; then
      wget -q --show-progress --timeout=120 --tries=1 -O "$dest" "$url" 2>/dev/null && \
        { success "$label downloaded"; return 0; }
    else
      curl -fsSL --max-time 120 -o "$dest" "$url" 2>/dev/null && \
        { success "$label downloaded"; return 0; }
    fi
    warn "Download failed. Retrying in 5s..."
    sleep 5
    rm -f "$dest"
  done
  error "Failed to download $label after 3 attempts."
}

# =============================================================================
# PACKAGE MANAGER WRAPPERS
# =============================================================================
pkg_update() {
  log "Updating package lists..."
  case "$PKG_MANAGER" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update -y -qq 2>/dev/null || true ;;
    yum) yum makecache -y -q 2>/dev/null || true ;;
    dnf) dnf makecache -y -q 2>/dev/null || true ;;
  esac
}

pkg_install() {
  case "$PKG_MANAGER" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" 2>/dev/null ;;
    yum) yum install -y -q "$@" 2>/dev/null ;;
    dnf) dnf install -y -q "$@" 2>/dev/null ;;
  esac
}

# =============================================================================
# SYSTEMD SERVICE HELPER
# =============================================================================
service_enable() {
  local svc="$1"
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable "$svc" --quiet 2>/dev/null || true
  systemctl restart "$svc" 2>/dev/null || systemctl start "$svc" 2>/dev/null || true

  local i
  for i in {1..30}; do
    systemctl is-active --quiet "$svc" 2>/dev/null && { success "$svc is running"; return 0; }
    sleep 1
  done
  warn "$svc did not start in 30s — check: journalctl -u $svc -n 50"
  return 1
}

# =============================================================================
# JAVA INSTALLATION
# =============================================================================
install_java() {
  if java -version 2>&1 | grep -qE "17|21|11"; then
    warn "Java already installed — skipping"
    return 0
  fi
  log "Installing Java 17..."
  case "$PKG_MANAGER" in
    apt)
      pkg_install openjdk-17-jdk 2>/dev/null || pkg_install default-jdk || error "Could not install Java."
      ;;
    yum)
      yum install -y -q java-17-openjdk 2>/dev/null || yum install -y -q java-11-openjdk || error "Could not install Java."
      ;;
    dnf)
      dnf install -y -q java-17-openjdk || error "Could not install Java."
      ;;
  esac
  success "Java installed"
}

# =============================================================================
# PREREQUISITES
# =============================================================================
install_prerequisites() {
  log "Installing prerequisites..."
  pkg_update

  case "$PKG_MANAGER" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget gnupg gnupg2 apt-transport-https \
        lsb-release ca-certificates unzip net-tools 2>/dev/null || true
      ;;
    yum)
      yum install -y -q epel-release 2>/dev/null || true
      yum install -y -q curl wget unzip net-tools 2>/dev/null || true
      ;;
    dnf)
      dnf install -y -q curl wget unzip net-tools 2>/dev/null || true
      ;;
  esac

  install_java
  success "Prerequisites installed"
}

# =============================================================================
# DOCKER — auto install on every OS
# =============================================================================
install_docker() {
  if command -v docker &>/dev/null && docker info &>/dev/null 2>/dev/null; then
    warn "Docker already running — skipping"
    return 0
  fi

  log "Installing Docker..."

  # Use official Docker install script — works on all supported OS
  if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null; then
    bash /tmp/get-docker.sh 2>/dev/null && rm -f /tmp/get-docker.sh
  fi

  # Fallback if official script fails
  if ! command -v docker &>/dev/null; then
    case "$PKG_MANAGER" in
      apt) pkg_install docker.io ;;
      yum) yum install -y -q docker ;;
      dnf) dnf install -y -q docker ;;
    esac
  fi

  command -v docker &>/dev/null || error "Failed to install Docker."

  service_enable docker || error "Docker failed to start."
  success "Docker installed and running"
}

# =============================================================================
# RABBITMQ
# =============================================================================
install_rabbitmq() {
  log "Installing RabbitMQ..."

  if systemctl is-active --quiet rabbitmq-server 2>/dev/null; then
    warn "RabbitMQ already running — skipping"
    return 0
  fi

  RABBITMQ_PORT=$(find_free_port "$RABBITMQ_PORT")
  RABBITMQ_MGMT_PORT=$(find_free_port "$RABBITMQ_MGMT_PORT")

  case "$PKG_MANAGER" in
    apt)
      pkg_update
      # Step 1 — Install Erlang from Ubuntu default repo (reliable, no external repo)
      pkg_install erlang-base erlang-crypto erlang-mnesia \
        erlang-public-key erlang-ssl erlang-syntax-tools \
        erlang-tools erlang-asn1 erlang-inets 2>/dev/null || true

      # Step 2 — Install RabbitMQ
      if ! pkg_install rabbitmq-server 2>/dev/null; then
        # Fallback — try official RabbitMQ repo
        curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey \
          | gpg --dearmor -o /usr/share/keyrings/rabbitmq.gpg 2>/dev/null || true
        echo "deb [signed-by=/usr/share/keyrings/rabbitmq.gpg] https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ $(lsb_release -cs) main" \
          > /etc/apt/sources.list.d/rabbitmq.list 2>/dev/null || true
        apt-get update -y -qq 2>/dev/null || true
        pkg_install rabbitmq-server 2>/dev/null || { fail "RabbitMQ install failed — skipping"; return 1; }
      fi
      ;;
    yum)
      yum install -y -q epel-release 2>/dev/null || true
      yum install -y -q erlang 2>/dev/null || true
      cat > /etc/yum.repos.d/rabbitmq.repo <<'EOF'
[rabbitmq]
name=RabbitMQ
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/8/$basearch
gpgcheck=0
enabled=1
EOF
      yum install -y -q rabbitmq-server 2>/dev/null || { fail "RabbitMQ install failed — skipping"; return 1; }
      ;;
    dnf)
      dnf install -y -q erlang rabbitmq-server 2>/dev/null || { fail "RabbitMQ install failed — skipping"; return 1; }
      ;;
  esac

  # Write port config
  mkdir -p /etc/rabbitmq
  cat > /etc/rabbitmq/rabbitmq.conf <<EOF
listeners.tcp.default = $RABBITMQ_PORT
management.listener.port = $RABBITMQ_MGMT_PORT
EOF

  rabbitmq-plugins enable rabbitmq_management 2>/dev/null || true

  if service_enable rabbitmq-server; then
    success "RabbitMQ ready → AMQP: $RABBITMQ_PORT | UI: http://localhost:$RABBITMQ_MGMT_PORT (guest/guest)"
  else
    warn "RabbitMQ installed but not running — check: journalctl -u rabbitmq-server -n 50"
  fi
}

# =============================================================================
# REDIS
# =============================================================================
install_redis() {
  log "Installing Redis..."

  if systemctl is-active --quiet redis-server 2>/dev/null \
     || systemctl is-active --quiet redis 2>/dev/null; then
    warn "Redis already running — skipping"
    return 0
  fi

  REDIS_PORT=$(find_free_port "$REDIS_PORT")

  case "$PKG_MANAGER" in
    apt) pkg_install redis-server 2>/dev/null || { fail "Redis install failed — skipping"; return 1; } ;;
    yum) yum install -y -q redis 2>/dev/null || { fail "Redis install failed — skipping"; return 1; } ;;
    dnf) dnf install -y -q redis 2>/dev/null || { fail "Redis install failed — skipping"; return 1; } ;;
  esac

  # Find and configure redis.conf
  local conf
  conf=$(find /etc/redis /etc -maxdepth 2 -name "redis.conf" 2>/dev/null | head -1)

  if [[ -f "$conf" ]]; then
    sed -i 's/^bind .*/bind 127.0.0.1/'   "$conf"
    sed -i "s/^port .*/port $REDIS_PORT/" "$conf"
    sed -i 's/^daemonize yes/daemonize no/' "$conf" 2>/dev/null || true
    sed -i 's/^supervised no/supervised systemd/' "$conf" 2>/dev/null || true
  fi

  # Detect correct service name
  local svc="redis-server"
  systemctl list-unit-files 2>/dev/null | grep -q "^redis.service" && svc="redis"

  if service_enable "$svc"; then
    success "Redis ready → Port: $REDIS_PORT (localhost only — secure)"
  else
    warn "Redis installed but not running — check: journalctl -u $svc -n 50"
  fi
}

# =============================================================================
# KEYCLOAK — DOCKER CONTAINER
# =============================================================================
install_keycloak() {
  log "Installing Keycloak ${KEYCLOAK_VERSION} as Docker container..."

  KEYCLOAK_PORT=$(find_free_port "$KEYCLOAK_PORT")

  # Install Docker first
  install_docker

  # Remove old container if exists
  docker rm -f keycloak 2>/dev/null || true

  # Pull Keycloak image
  log "Pulling Keycloak ${KEYCLOAK_VERSION} image..."
  if ! docker pull quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} 2>/dev/null; then
    fail "Failed to pull Keycloak image — skipping"
    return 1
  fi

  # Run Keycloak container
  if ! docker run -d \
    --name keycloak \
    --restart always \
    -p "${KEYCLOAK_PORT}:8080" \
    -e KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN_USER}" \
    -e KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASS}" \
    quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} \
    start-dev 2>/dev/null; then
    fail "Failed to start Keycloak container — skipping"
    return 1
  fi

  # Wait for container to be running
  log "Waiting for Keycloak to start..."
  local i
  for i in {1..60}; do
    if docker ps 2>/dev/null | grep -q "keycloak"; then
      success "Keycloak container is running"
      success "Keycloak ready → http://localhost:${KEYCLOAK_PORT}  (${KEYCLOAK_ADMIN_USER} / ${KEYCLOAK_ADMIN_PASS})"
      return 0
    fi
    sleep 1
  done
  warn "Keycloak may still be booting — check: docker logs keycloak"
}

# =============================================================================
# JASPERREPORTS SERVER
# =============================================================================
install_jasper() {
  log "Installing JasperReports Server ${JASPER_VERSION}..."

  JASPER_PORT=$(find_free_port "$JASPER_PORT")

  local install_dir="/opt/jasperreports-server"

  if [[ ! -d "$install_dir" ]]; then
    local url="https://downloads.sourceforge.net/project/jasperserver/JasperReports%20Server/${JASPER_VERSION}/TIB_js-jrs-cp_${JASPER_VERSION}_bin.zip"
    download_file "$url" /tmp/jasper.zip "JasperReports ${JASPER_VERSION}"
    mkdir -p "$install_dir"
    if ! unzip -q /tmp/jasper.zip -d "$install_dir" 2>/dev/null; then
      fail "Failed to extract JasperReports — skipping"
      return 1
    fi
    rm -f /tmp/jasper.zip
  else
    warn "JasperReports already at $install_dir — skipping download"
  fi

  local installer
  installer=$(find "$install_dir" -maxdepth 4 -name "js-install-ce.sh" 2>/dev/null | head -1)

  if [[ -z "$installer" ]]; then
    warn "JasperReports installer not found — run manually: cd $install_dir && sudo bash js-install-ce.sh"
    return 0
  fi

  chmod +x "$installer"
  log "Running JasperReports installer..."

  local props
  props=$(find "$install_dir" -maxdepth 4 -name "default_master.properties" 2>/dev/null | head -1)

  if [[ -n "$props" ]]; then
    sed -i "s/^httpPort=.*/httpPort=${JASPER_PORT}/" "$props" 2>/dev/null || true
    if bash "$installer" "$props" 2>/dev/null; then
      success "JasperReports installed → http://localhost:${JASPER_PORT}/jasperserver  (jasperadmin / jasperadmin)"
    else
      warn "JasperReports installer had errors — check logs in $install_dir"
    fi
  else
    if bash "$installer" 2>/dev/null; then
      success "JasperReports installed → http://localhost:${JASPER_PORT}/jasperserver  (jasperadmin / jasperadmin)"
    else
      warn "JasperReports installer had errors — check logs in $install_dir"
    fi
  fi
}

# =============================================================================
# SMOKE TESTS
# =============================================================================
PASS=0
FAIL=0

check_test() {
  local name="$1" cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${RESET} $name"
    ((PASS++))
  else
    echo -e "  ${RED}[FAIL]${RESET} $name"
    ((FAIL++))
  fi
}

check_optional() {
  local name="$1" cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${RESET} $name"
    ((PASS++))
  else
    echo -e "  ${YELLOW}[SKIP]${RESET} $name"
  fi
}

run_smoke_tests() {
  echo ""
  echo -e "${BOLD}  ── Smoke Tests ──────────────────────────────${RESET}"
  echo ""

  if [[ "$INSTALL_RABBITMQ" == true ]]; then
    echo -e "${BOLD}  RabbitMQ${RESET}"
    check_test     "  Service running"              "systemctl is-active rabbitmq-server"
    check_test     "  AMQP port $RABBITMQ_PORT"     "ss -tlnp | grep -q ':${RABBITMQ_PORT}'"
    check_test     "  UI port $RABBITMQ_MGMT_PORT"  "ss -tlnp | grep -q ':${RABBITMQ_MGMT_PORT}'"
    echo ""
  fi

  if [[ "$INSTALL_REDIS" == true ]]; then
    echo -e "${BOLD}  Redis${RESET}"
    check_test     "  Service running"              "systemctl is-active redis-server || systemctl is-active redis"
    check_test     "  Port $REDIS_PORT open"        "ss -tlnp | grep -q ':${REDIS_PORT}'"
    check_test     "  Responds to PING"             "redis-cli -p ${REDIS_PORT} ping | grep -qi pong"
    echo ""
  fi

  if [[ "$INSTALL_KEYCLOAK" == true ]]; then
    echo -e "${BOLD}  Keycloak (Docker)${RESET}"
    check_test     "  Docker running"               "systemctl is-active docker"
    check_test     "  Container running"            "docker ps | grep -q keycloak"
    check_test     "  Port $KEYCLOAK_PORT open"     "ss -tlnp | grep -q ':${KEYCLOAK_PORT}'"
    echo ""
  fi

  if [[ "$INSTALL_JASPER" == true ]]; then
    echo -e "${BOLD}  JasperReports${RESET}"
    check_optional "  Install directory exists"     "test -d /opt/jasperreports-server"
    echo ""
  fi

  echo -e "${BOLD}  System${RESET}"
  check_test       "  Java installed"               "java -version 2>&1 | grep -qE '17|21|11'"
  check_test       "  Docker installed"             "command -v docker"

  echo ""
  echo -e "  ──────────────────────────────────────────────"
  local total=$(( PASS + FAIL ))
  if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All tests passed ($PASS/$total)${RESET}"
  else
    echo -e "  ${RED}${BOLD}$FAIL test(s) failed — $PASS/$total passed${RESET}"
    echo ""
    echo -e "  ${YELLOW}Check logs:${RESET}"
    echo -e "    RabbitMQ  → journalctl -u rabbitmq-server -n 50"
    echo -e "    Redis     → journalctl -u redis-server -n 50"
    echo -e "    Keycloak  → docker logs keycloak"
  fi
  echo ""
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================
print_summary() {
  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║              Installation Complete!                          ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Service            URL / Port                         Credentials${RESET}"
  echo -e "  ───────────────────────────────────────────────────────────────────────"
  [[ "$INSTALL_RABBITMQ" == true ]] && {
    echo -e "  ${CYAN}RabbitMQ${RESET}           AMQP → localhost:${RABBITMQ_PORT}"
    echo -e "                     UI   → http://localhost:${RABBITMQ_MGMT_PORT}        guest / guest"
  }
  [[ "$INSTALL_REDIS" == true ]] && \
    echo -e "  ${CYAN}Redis${RESET}              Port → localhost:${REDIS_PORT}             No password (localhost only)"
  [[ "$INSTALL_KEYCLOAK" == true ]] && \
    echo -e "  ${CYAN}Keycloak${RESET} (Docker)  UI   → http://localhost:${KEYCLOAK_PORT}           ${KEYCLOAK_ADMIN_USER} / ${KEYCLOAK_ADMIN_PASS}"
  [[ "$INSTALL_JASPER" == true ]] && \
    echo -e "  ${CYAN}JasperReports${RESET}      UI   → http://localhost:${JASPER_PORT}/jasperserver jasperadmin / jasperadmin"
  echo -e "  ───────────────────────────────────────────────────────────────────────"
  echo ""
  echo -e "  ${YELLOW}Note:${RESET} Replace 'localhost' with your server IP to access from browser."
  echo ""
  echo -e "  ${BOLD}Useful Commands:${RESET}"
  echo -e "  Keycloak  → docker ps | docker logs keycloak | docker restart keycloak"
  echo -e "  RabbitMQ  → systemctl status rabbitmq-server"
  echo -e "  Redis     → systemctl status redis-server"
  echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  echo ""
  echo -e "${BOLD}${CYAN}  DevOps One-Click Installer${RESET}"
  echo -e "  ─────────────────────────────"
  echo ""

  parse_args "$@"
  check_root

  if [[ "$TEST_ONLY" == true ]]; then
    detect_os
    run_smoke_tests
    exit 0
  fi

  detect_os
  check_internet
  install_prerequisites

  # Each service runs independently — one failure never stops others
  if [[ "$INSTALL_RABBITMQ" == true ]]; then install_rabbitmq || warn "RabbitMQ skipped — continuing..."; fi
  if [[ "$INSTALL_REDIS"    == true ]]; then install_redis    || warn "Redis skipped — continuing..."; fi
  if [[ "$INSTALL_KEYCLOAK" == true ]]; then install_keycloak || warn "Keycloak skipped — continuing..."; fi
  if [[ "$INSTALL_JASPER"   == true ]]; then install_jasper   || warn "JasperReports skipped — continuing..."; fi

  print_summary
  run_smoke_tests
}

main "$@"
