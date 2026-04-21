#!/bin/bash
# =============================================================================
#  DevOps One-Click Installer + Smoke Tests
#  Installs: RabbitMQ · Redis · Keycloak · JasperReports Server
#
#  Supported OS:
#    Ubuntu 20 / 22 / 24
#    Debian 11 / 12
#    CentOS / RHEL 7 / 8 / 9
#    Rocky Linux / AlmaLinux 8 / 9
#    Fedora 38+
#
#  One-liner (no clone needed):
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
#    --test-only       Run smoke tests only (no install)
#    --help            Show this help
# =============================================================================

set -uo pipefail

# =============================================================================
# PINNED VERSIONS  (edit here to upgrade)
# =============================================================================
KEYCLOAK_VERSION="24.0.4"
JASPER_VERSION="8.2.0"

# =============================================================================
# DEFAULT PORTS  (auto-switched if port is busy)
# =============================================================================
RABBITMQ_PORT=5672
RABBITMQ_MGMT_PORT=15672
REDIS_PORT=6379
KEYCLOAK_PORT=8080
JASPER_PORT=8080

# =============================================================================
# INSTALL FLAGS
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
        echo "    --skip-rabbitmq   Skip RabbitMQ installation"
        echo "    --skip-redis      Skip Redis installation"
        echo "    --skip-keycloak   Skip Keycloak installation"
        echo "    --skip-jasper     Skip JasperReports installation"
        echo "    --test-only       Run smoke tests only (no install)"
        echo "    --help            Show this help message"
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
# LOGGING
# =============================================================================
log()     { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

# =============================================================================
# ROOT CHECK
# =============================================================================
check_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Please run as root:  sudo bash install.sh"
  fi
}

# =============================================================================
# OS DETECTION
# =============================================================================
OS=""
OS_VERSION=""

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS — /etc/os-release not found."
  fi

  # shellcheck source=/dev/null
  source /etc/os-release
  OS="${ID,,}"
  OS_VERSION="${VERSION_ID:-0}"

  log "Detected OS: ${PRETTY_NAME:-$OS} (version: $OS_VERSION)"

  case "$OS" in
    ubuntu|debian|centos|rhel|fedora|rocky|almalinux) ;;
    *) error "Unsupported OS: $OS. Supported: Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky, AlmaLinux" ;;
  esac
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
# Finds next available port starting from given port
# =============================================================================
find_free_port() {
  local port="$1"
  while ss -tlnp 2>/dev/null | grep -q ":${port} "; do
    warn "Port $port is busy — trying port $((port + 1))..."
    port=$((port + 1))
  done
  echo "$port"
}

# =============================================================================
# DOWNLOAD WITH RETRY
# =============================================================================
download_file() {
  local url="$1"
  local dest="$2"
  local label="$3"
  local attempts=3
  local delay=5
  local i

  for ((i=1; i<=attempts; i++)); do
    log "Downloading $label (attempt $i/$attempts)..."
    if wget -q --show-progress --timeout=60 --tries=1 -O "$dest" "$url"; then
      success "$label downloaded"
      return 0
    fi
    warn "Download failed. Retrying in ${delay}s..."
    sleep "$delay"
    rm -f "$dest"
  done

  error "Failed to download $label after $attempts attempts. Check your internet or the version number."
}

# =============================================================================
# PACKAGE MANAGER WRAPPERS
# =============================================================================
pkg_update() {
  case "$OS" in
    ubuntu|debian)               apt-get update -y -qq ;;
    centos|rhel|rocky|almalinux) yum makecache -y -q   ;;
    fedora)                      dnf makecache -y -q   ;;
  esac
}

pkg_install() {
  case "$OS" in
    ubuntu|debian)               apt-get install -y -qq "$@" ;;
    centos|rhel|rocky|almalinux) yum install -y -q "$@"     ;;
    fedora)                      dnf install -y -q "$@"     ;;
  esac
}

# =============================================================================
# SYSTEMD SERVICE HELPER
# =============================================================================
service_enable() {
  local svc="$1"

  systemctl daemon-reload
  systemctl enable "$svc" --quiet
  systemctl restart "$svc"

  local i
  for i in {1..20}; do
    if systemctl is-active --quiet "$svc"; then
      success "$svc is running"
      return 0
    fi
    sleep 1
  done

  error "$svc failed to start after 20s. Run: journalctl -u $svc -n 50"
}

# =============================================================================
# JAVA INSTALLATION
# =============================================================================
install_java() {
  if java -version 2>&1 | grep -qE "17|21"; then
    warn "Java already installed — skipping"
    return 0
  fi

  log "Installing Java 17..."
  case "$OS" in
    ubuntu|debian)
      if ! pkg_install openjdk-17-jdk 2>/dev/null; then
        pkg_install default-jdk || error "Could not install Java. Install Java 17 manually and re-run."
      fi
      ;;
    centos|rhel|rocky|almalinux)
      if ! pkg_install java-17-openjdk 2>/dev/null; then
        pkg_install java-11-openjdk || error "Could not install Java. Install Java 17 manually and re-run."
      fi
      ;;
    fedora)
      pkg_install java-17-openjdk || error "Could not install Java 17."
      ;;
  esac
}

# =============================================================================
# PREREQUISITES
# =============================================================================
install_prerequisites() {
  log "Installing prerequisites..."
  pkg_update

  case "$OS" in
    ubuntu|debian)
      pkg_install curl wget gnupg lsb-release unzip net-tools
      ;;
    centos|rhel|rocky|almalinux)
      yum install -y -q epel-release 2>/dev/null || true
      pkg_install curl wget unzip net-tools
      ;;
    fedora)
      pkg_install curl wget unzip net-tools
      ;;
  esac

  install_java
  success "Prerequisites installed"
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

  # Auto find free ports
  RABBITMQ_PORT=$(find_free_port "$RABBITMQ_PORT")
  RABBITMQ_MGMT_PORT=$(find_free_port "$RABBITMQ_MGMT_PORT")

  case "$OS" in
    ubuntu|debian)
      curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey \
        | gpg --dearmor -o /usr/share/keyrings/rabbitmq.gpg 2>/dev/null

      echo "deb [signed-by=/usr/share/keyrings/rabbitmq.gpg] \
https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/rabbitmq.list

      apt-get update -y -qq
      pkg_install rabbitmq-server
      ;;

    centos|rhel|rocky|almalinux|fedora)
      curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey \
        -o /tmp/rabbitmq.gpg
      rpm --import /tmp/rabbitmq.gpg 2>/dev/null || true
      rm -f /tmp/rabbitmq.gpg
      pkg_install rabbitmq-server
      ;;
  esac

  # Apply custom ports if they were changed
  local conf="/etc/rabbitmq/rabbitmq.conf"
  mkdir -p /etc/rabbitmq
  cat > "$conf" <<EOF
listeners.tcp.default = $RABBITMQ_PORT
management.listener.port = $RABBITMQ_MGMT_PORT
EOF

  rabbitmq-plugins enable rabbitmq_management --offline >/dev/null 2>&1 \
    || rabbitmq-plugins enable rabbitmq_management >/dev/null 2>&1 \
    || warn "Could not enable RabbitMQ management plugin — enable manually if needed."

  service_enable rabbitmq-server
  success "RabbitMQ ready → AMQP: $RABBITMQ_PORT | UI: http://localhost:$RABBITMQ_MGMT_PORT  (guest / guest)"
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

  # Auto find free port
  REDIS_PORT=$(find_free_port "$REDIS_PORT")

  case "$OS" in
    ubuntu|debian)
      pkg_install redis-server
      local conf="/etc/redis/redis.conf"
      if [[ -f "$conf" ]]; then
        sed -i 's/^bind .*/bind 127.0.0.1/' "$conf"
        sed -i "s/^port .*/port $REDIS_PORT/" "$conf"
      fi
      service_enable redis-server
      ;;

    centos|rhel|rocky|almalinux|fedora)
      pkg_install redis
      local conf="/etc/redis.conf"
      if [[ -f "$conf" ]]; then
        sed -i 's/^bind .*/bind 127.0.0.1/' "$conf"
        sed -i "s/^port .*/port $REDIS_PORT/" "$conf"
      fi
      service_enable redis
      ;;
  esac

  success "Redis ready → Port: $REDIS_PORT"
}

# =============================================================================
# KEYCLOAK
# =============================================================================
install_keycloak() {
  log "Installing Keycloak ${KEYCLOAK_VERSION}..."

  # Auto find free port
  KEYCLOAK_PORT=$(find_free_port "$KEYCLOAK_PORT")

  if [[ ! -d /opt/keycloak ]]; then
    local url="https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz"
    download_file "$url" /tmp/keycloak.tar.gz "Keycloak ${KEYCLOAK_VERSION}"
    tar -xzf /tmp/keycloak.tar.gz -C /opt/
    mv "/opt/keycloak-${KEYCLOAK_VERSION}" /opt/keycloak
    rm -f /tmp/keycloak.tar.gz
  else
    warn "Keycloak already at /opt/keycloak — skipping download"
  fi

  if ! id keycloak &>/dev/null; then
    useradd --system --no-create-home --shell /sbin/nologin keycloak
  fi

  chown -R keycloak:keycloak /opt/keycloak

  cat > /etc/systemd/system/keycloak.service <<EOF
[Unit]
Description=Keycloak Identity Provider
After=network.target

[Service]
User=keycloak
Group=keycloak
ExecStart=/opt/keycloak/bin/kc.sh start-dev --http-port=${KEYCLOAK_PORT}
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  service_enable keycloak
  success "Keycloak ready → http://localhost:${KEYCLOAK_PORT}"
}

# =============================================================================
# JASPERREPORTS SERVER
# =============================================================================
install_jasper() {
  log "Installing JasperReports Server ${JASPER_VERSION}..."

  # Auto find free port (use different port from keycloak)
  local jasper_start=$((KEYCLOAK_PORT + 1))
  JASPER_PORT=$(find_free_port "$jasper_start")

  local install_dir="/opt/jasperreports-server"

  if [[ ! -d "$install_dir" ]]; then
    local url="https://downloads.sourceforge.net/project/jasperserver/JasperReports%20Server/${JASPER_VERSION}/TIB_js-jrs-cp_${JASPER_VERSION}_bin.zip"
    download_file "$url" /tmp/jasper.zip "JasperReports ${JASPER_VERSION}"
    mkdir -p "$install_dir"
    unzip -q /tmp/jasper.zip -d "$install_dir"
    rm -f /tmp/jasper.zip
  else
    warn "JasperReports already at $install_dir — skipping download"
  fi

  local installer
  installer=$(find "$install_dir" -maxdepth 3 -name "js-install-ce.sh" 2>/dev/null | head -1)

  if [[ -z "$installer" ]]; then
    warn "JasperReports installer not found in $install_dir"
    warn "Navigate to $install_dir and run: sudo bash js-install-ce.sh"
    return 0
  fi

  chmod +x "$installer"
  log "Running JasperReports installer..."

  local props
  props=$(find "$install_dir" -maxdepth 3 -name "default_master.properties" 2>/dev/null | head -1)

  if [[ -n "$props" ]]; then
    # Inject custom port into properties
    sed -i "s/^httpPort=.*/httpPort=${JASPER_PORT}/" "$props" 2>/dev/null || true
    if bash "$installer" "$props"; then
      success "JasperReports installed → http://localhost:${JASPER_PORT}/jasperserver"
    else
      warn "JasperReports installer exited with errors. Check logs in $install_dir"
    fi
  else
    if bash "$installer"; then
      success "JasperReports installed → http://localhost:${JASPER_PORT}/jasperserver"
    else
      warn "JasperReports installer exited with errors. Check logs in $install_dir"
    fi
  fi
}

# =============================================================================
# SMOKE TESTS
# =============================================================================
PASS=0
FAIL=0

check_test() {
  local name="$1"
  local cmd="$2"

  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${RESET} $name"
    ((PASS++))
  else
    echo -e "  ${RED}[FAIL]${RESET} $name"
    ((FAIL++))
  fi
}

check_optional_test() {
  local name="$1"
  local cmd="$2"

  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${RESET} $name"
    ((PASS++))
  else
    echo -e "  ${YELLOW}[SKIP]${RESET} $name (service may have been skipped during install)"
  fi
}

run_smoke_tests() {
  echo ""
  echo -e "${BOLD}  ── Smoke Tests ──────────────────────────────${RESET}"
  echo ""

  if [[ "$INSTALL_RABBITMQ" == true ]]; then
    echo -e "${BOLD}  RabbitMQ${RESET}"
    check_test          "  Service is running"                  "systemctl is-active rabbitmq-server"
    check_test          "  AMQP port $RABBITMQ_PORT open"       "ss -tlnp | grep -q ':${RABBITMQ_PORT}'"
    check_test          "  Management port $RABBITMQ_MGMT_PORT" "ss -tlnp | grep -q ':${RABBITMQ_MGMT_PORT}'"
    echo ""
  fi

  if [[ "$INSTALL_REDIS" == true ]]; then
    echo -e "${BOLD}  Redis${RESET}"
    check_test          "  Service is running"                  "systemctl is-active redis-server || systemctl is-active redis"
    check_test          "  Port $REDIS_PORT open"               "ss -tlnp | grep -q ':${REDIS_PORT}'"
    check_test          "  Responds to PING"                    "redis-cli -p ${REDIS_PORT} ping | grep -qi pong"
    echo ""
  fi

  if [[ "$INSTALL_KEYCLOAK" == true ]]; then
    echo -e "${BOLD}  Keycloak${RESET}"
    check_test          "  Service is running"                  "systemctl is-active keycloak"
    check_test          "  Port $KEYCLOAK_PORT open"            "ss -tlnp | grep -q ':${KEYCLOAK_PORT}'"
    echo ""
  fi

  if [[ "$INSTALL_JASPER" == true ]]; then
    echo -e "${BOLD}  JasperReports${RESET}"
    check_optional_test "  Install directory exists"            "test -d /opt/jasperreports-server"
    echo ""
  fi

  echo -e "${BOLD}  System${RESET}"
  check_test            "  Java 17+ installed"                  "java -version 2>&1 | grep -qE '17|21'"

  echo ""
  echo -e "  ──────────────────────────────────────────────"

  local total=$(( PASS + FAIL ))
  if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All tests passed ($PASS/$total)${RESET}"
  else
    echo -e "  ${RED}${BOLD}$FAIL test(s) failed — $PASS/$total passed${RESET}"
    echo ""
    echo -e "  ${YELLOW}Tip:${RESET} Check logs with:  journalctl -u <service-name> -n 50"
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
  echo -e "  ${BOLD}Service         URL / Port                          Credentials${RESET}"
  echo -e "  ──────────────────────────────────────────────────────────────────"

  if [[ "$INSTALL_RABBITMQ" == true ]]; then
    echo -e "  ${CYAN}RabbitMQ${RESET}        AMQP  → localhost:${RABBITMQ_PORT}"
    echo -e "                  UI    → http://localhost:${RABBITMQ_MGMT_PORT}       guest / guest"
  fi

  if [[ "$INSTALL_REDIS" == true ]]; then
    echo -e "  ${CYAN}Redis${RESET}           Port  → localhost:${REDIS_PORT}              No password"
  fi

  if [[ "$INSTALL_KEYCLOAK" == true ]]; then
    echo -e "  ${CYAN}Keycloak${RESET}        UI    → http://localhost:${KEYCLOAK_PORT}            Set on first login"
  fi

  if [[ "$INSTALL_JASPER" == true ]]; then
    echo -e "  ${CYAN}JasperReports${RESET}   UI    → http://localhost:${JASPER_PORT}/jasperserver  jasperadmin / jasperadmin"
  fi

  echo -e "  ──────────────────────────────────────────────────────────────────"
  echo ""
  echo -e "  ${YELLOW}Note:${RESET} Replace 'localhost' with your server IP to access from browser."
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

  if [[ "$INSTALL_RABBITMQ" == true ]]; then install_rabbitmq; fi
  if [[ "$INSTALL_REDIS"    == true ]]; then install_redis;    fi
  if [[ "$INSTALL_KEYCLOAK" == true ]]; then install_keycloak; fi
  if [[ "$INSTALL_JASPER"   == true ]]; then install_jasper;   fi

  print_summary
  run_smoke_tests
}

main "$@"
