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
# PINNED VERSIONS
# =============================================================================
KEYCLOAK_VERSION="24.0.4"
JASPER_VERSION="8.2.0"

# =============================================================================
# DEFAULT PORTS  (auto-switched if busy)
# =============================================================================
RABBITMQ_PORT=5672
RABBITMQ_MGMT_PORT=15672
REDIS_PORT=6379
KEYCLOAK_PORT=8080
JASPER_PORT=8081

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
# LOGGING
# =============================================================================
log()     { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

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
    *) error "Unsupported OS: $OS" ;;
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
# DOWNLOAD WITH RETRY  (supports both wget and curl)
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
    if command -v wget &>/dev/null; then
      if wget -q --show-progress --timeout=120 --tries=1 -O "$dest" "$url" 2>/dev/null; then
        success "$label downloaded"
        return 0
      fi
    elif command -v curl &>/dev/null; then
      if curl -fsSL --max-time 120 -o "$dest" "$url" 2>/dev/null; then
        success "$label downloaded"
        return 0
      fi
    fi
    warn "Download failed. Retrying in ${delay}s..."
    sleep "$delay"
    rm -f "$dest"
  done
  error "Failed to download $label after $attempts attempts."
}

# =============================================================================
# PACKAGE MANAGER WRAPPERS
# =============================================================================
pkg_update() {
  log "Updating package lists..."
  case "$OS" in
    ubuntu|debian)
      DEBIAN_FRONTEND=noninteractive apt-get update -y -qq 2>/dev/null || true
      ;;
    centos|rhel|rocky|almalinux)
      yum makecache -y -q 2>/dev/null || true
      ;;
    fedora)
      dnf makecache -y -q 2>/dev/null || true
      ;;
  esac
}

pkg_install() {
  case "$OS" in
    ubuntu|debian)
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" 2>/dev/null
      ;;
    centos|rhel|rocky|almalinux)
      yum install -y -q "$@" 2>/dev/null
      ;;
    fedora)
      dnf install -y -q "$@" 2>/dev/null
      ;;
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
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      success "$svc is running"
      return 0
    fi
    sleep 1
  done
  warn "$svc did not start within 30s — check: journalctl -u $svc -n 50"
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
  case "$OS" in
    ubuntu|debian)
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-17-jdk 2>/dev/null \
        || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq default-jdk 2>/dev/null \
        || error "Could not install Java. Install Java 17 manually and re-run."
      ;;
    centos|rhel|rocky|almalinux)
      yum install -y -q java-17-openjdk 2>/dev/null \
        || yum install -y -q java-11-openjdk 2>/dev/null \
        || error "Could not install Java."
      ;;
    fedora)
      dnf install -y -q java-17-openjdk 2>/dev/null \
        || error "Could not install Java 17."
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

  case "$OS" in
    ubuntu|debian)
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget gnupg gnupg2 apt-transport-https \
        lsb-release ca-certificates unzip net-tools socat 2>/dev/null || true
      ;;
    centos|rhel|rocky|almalinux)
      yum install -y -q epel-release 2>/dev/null || true
      yum install -y -q curl wget unzip net-tools socat 2>/dev/null || true
      ;;
    fedora)
      dnf install -y -q curl wget unzip net-tools socat 2>/dev/null || true
      ;;
  esac

  install_java
  success "Prerequisites installed"
}

# =============================================================================
# RABBITMQ
# Uses official RabbitMQ team script — most reliable method
# =============================================================================
install_rabbitmq() {
  log "Installing RabbitMQ..."

  if systemctl is-active --quiet rabbitmq-server 2>/dev/null; then
    warn "RabbitMQ already running — skipping"
    return 0
  fi

  RABBITMQ_PORT=$(find_free_port "$RABBITMQ_PORT")
  RABBITMQ_MGMT_PORT=$(find_free_port "$RABBITMQ_MGMT_PORT")

  case "$OS" in
    ubuntu|debian)
      # Clean any previous failed setup
      rm -f /usr/share/keyrings/rabbitmq*.gpg
      rm -f /etc/apt/sources.list.d/rabbitmq*.list
      DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq rabbitmq-server 2>/dev/null || true
      DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq 2>/dev/null || true

      # Install Erlang first (RabbitMQ dependency)
      log "Installing Erlang..."
      curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
        | gpg --dearmor -o /usr/share/keyrings/erlang.gpg 2>/dev/null || true

      echo "deb [signed-by=/usr/share/keyrings/erlang.gpg] https://packages.erlang-solutions.com/ubuntu $(lsb_release -cs) contrib" \
        > /etc/apt/sources.list.d/erlang.list

      DEBIAN_FRONTEND=noninteractive apt-get update -y -qq 2>/dev/null || true
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq erlang 2>/dev/null \
        || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq erlang-base 2>/dev/null \
        || warn "Erlang install had issues — continuing..."

      # Install RabbitMQ
      curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey \
        | gpg --dearmor -o /usr/share/keyrings/rabbitmq.gpg 2>/dev/null || true

      echo "deb [signed-by=/usr/share/keyrings/rabbitmq.gpg] https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/rabbitmq.list

      DEBIAN_FRONTEND=noninteractive apt-get update -y -qq 2>/dev/null || true
      DEBIAN_FRONTEND=noninteractive apt-get -f install -y -qq 2>/dev/null || true
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rabbitmq-server 2>/dev/null \
        || error "Failed to install RabbitMQ. Run: apt-get install rabbitmq-server"
      ;;

    centos|rhel|rocky|almalinux)
      # Install Erlang first
      yum install -y -q epel-release 2>/dev/null || true
      yum install -y -q erlang 2>/dev/null || true

      curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey \
        -o /tmp/rabbitmq.gpg 2>/dev/null || true
      rpm --import /tmp/rabbitmq.gpg 2>/dev/null || true
      rm -f /tmp/rabbitmq.gpg

      cat > /etc/yum.repos.d/rabbitmq.repo <<'EOF'
[rabbitmq]
name=RabbitMQ
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/8/$basearch
gpgcheck=0
enabled=1
EOF
      yum install -y -q rabbitmq-server 2>/dev/null \
        || error "Failed to install RabbitMQ."
      ;;

    fedora)
      dnf install -y -q erlang rabbitmq-server 2>/dev/null \
        || error "Failed to install RabbitMQ."
      ;;
  esac

  # Configure ports
  mkdir -p /etc/rabbitmq
  cat > /etc/rabbitmq/rabbitmq.conf <<EOF
listeners.tcp.default = $RABBITMQ_PORT
management.listener.port = $RABBITMQ_MGMT_PORT
EOF

  # Enable management plugin
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

  case "$OS" in
    ubuntu|debian)
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq redis-server 2>/dev/null \
        || error "Failed to install Redis."

      local conf="/etc/redis/redis.conf"
      if [[ -f "$conf" ]]; then
        sed -i 's/^bind .*/bind 127.0.0.1/' "$conf"
        sed -i "s/^port .*/port $REDIS_PORT/" "$conf"
        # Allow systemd to manage redis
        sed -i 's/^daemonize yes/daemonize no/' "$conf" 2>/dev/null || true
        sed -i 's/^supervised no/supervised systemd/' "$conf" 2>/dev/null || true
      fi

      if service_enable redis-server; then
        success "Redis ready → Port: $REDIS_PORT"
      else
        warn "Redis installed but not running — check: journalctl -u redis-server -n 50"
      fi
      ;;

    centos|rhel|rocky|almalinux)
      yum install -y -q redis 2>/dev/null \
        || error "Failed to install Redis."

      local conf="/etc/redis.conf"
      if [[ -f "$conf" ]]; then
        sed -i 's/^bind .*/bind 127.0.0.1/' "$conf"
        sed -i "s/^port .*/port $REDIS_PORT/" "$conf"
      fi

      if service_enable redis; then
        success "Redis ready → Port: $REDIS_PORT"
      else
        warn "Redis installed but not running — check: journalctl -u redis -n 50"
      fi
      ;;

    fedora)
      dnf install -y -q redis 2>/dev/null \
        || error "Failed to install Redis."

      local conf="/etc/redis.conf"
      if [[ -f "$conf" ]]; then
        sed -i 's/^bind .*/bind 127.0.0.1/' "$conf"
        sed -i "s/^port .*/port $REDIS_PORT/" "$conf"
      fi

      if service_enable redis; then
        success "Redis ready → Port: $REDIS_PORT"
      else
        warn "Redis installed but not running — check: journalctl -u redis -n 50"
      fi
      ;;
  esac
}

# =============================================================================
# KEYCLOAK
# =============================================================================
install_keycloak() {
  log "Installing Keycloak ${KEYCLOAK_VERSION}..."

  KEYCLOAK_PORT=$(find_free_port "$KEYCLOAK_PORT")

  if [[ ! -d /opt/keycloak ]]; then
    local url="https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz"
    download_file "$url" /tmp/keycloak.tar.gz "Keycloak ${KEYCLOAK_VERSION}"

    tar -xzf /tmp/keycloak.tar.gz -C /opt/ 2>/dev/null \
      || error "Failed to extract Keycloak."
    mv "/opt/keycloak-${KEYCLOAK_VERSION}" /opt/keycloak
    rm -f /tmp/keycloak.tar.gz
  else
    warn "Keycloak already at /opt/keycloak — skipping download"
  fi

  # Create system user
  if ! id keycloak &>/dev/null; then
    useradd --system --no-create-home --shell /sbin/nologin keycloak 2>/dev/null || true
  fi

  chown -R keycloak:keycloak /opt/keycloak
  chmod +x /opt/keycloak/bin/kc.sh

  # Create systemd service
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
Environment=JAVA_OPTS="-Xms512m -Xmx1024m"

[Install]
WantedBy=multi-user.target
EOF

  if service_enable keycloak; then
    success "Keycloak ready → http://localhost:${KEYCLOAK_PORT}"
  else
    warn "Keycloak installed but not running — check: journalctl -u keycloak -n 50"
  fi
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
    unzip -q /tmp/jasper.zip -d "$install_dir" 2>/dev/null \
      || error "Failed to extract JasperReports."
    rm -f /tmp/jasper.zip
  else
    warn "JasperReports already at $install_dir — skipping download"
  fi

  local installer
  installer=$(find "$install_dir" -maxdepth 4 -name "js-install-ce.sh" 2>/dev/null | head -1)

  if [[ -z "$installer" ]]; then
    warn "JasperReports installer script not found in $install_dir"
    warn "Navigate to $install_dir and run: sudo bash js-install-ce.sh"
    return 0
  fi

  chmod +x "$installer"
  log "Running JasperReports installer..."

  local props
  props=$(find "$install_dir" -maxdepth 4 -name "default_master.properties" 2>/dev/null | head -1)

  if [[ -n "$props" ]]; then
    sed -i "s/^httpPort=.*/httpPort=${JASPER_PORT}/" "$props" 2>/dev/null || true
    if bash "$installer" "$props" 2>/dev/null; then
      success "JasperReports installed → http://localhost:${JASPER_PORT}/jasperserver"
    else
      warn "JasperReports installer had errors — check logs in $install_dir"
    fi
  else
    if bash "$installer" 2>/dev/null; then
      success "JasperReports installed → http://localhost:${JASPER_PORT}/jasperserver"
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
    echo -e "  ${YELLOW}[SKIP]${RESET} $name"
  fi
}

run_smoke_tests() {
  echo ""
  echo -e "${BOLD}  ── Smoke Tests ──────────────────────────────${RESET}"
  echo ""

  if [[ "$INSTALL_RABBITMQ" == true ]]; then
    echo -e "${BOLD}  RabbitMQ${RESET}"
    check_test          "  Service is running"                   "systemctl is-active rabbitmq-server"
    check_test          "  AMQP port $RABBITMQ_PORT open"        "ss -tlnp | grep -q ':${RABBITMQ_PORT}'"
    check_test          "  Management port $RABBITMQ_MGMT_PORT"  "ss -tlnp | grep -q ':${RABBITMQ_MGMT_PORT}'"
    echo ""
  fi

  if [[ "$INSTALL_REDIS" == true ]]; then
    echo -e "${BOLD}  Redis${RESET}"
    check_test          "  Service is running"                   "systemctl is-active redis-server || systemctl is-active redis"
    check_test          "  Port $REDIS_PORT open"                "ss -tlnp | grep -q ':${REDIS_PORT}'"
    check_test          "  Responds to PING"                     "redis-cli -p ${REDIS_PORT} ping | grep -qi pong"
    echo ""
  fi

  if [[ "$INSTALL_KEYCLOAK" == true ]]; then
    echo -e "${BOLD}  Keycloak${RESET}"
    check_test          "  Service is running"                   "systemctl is-active keycloak"
    check_test          "  Port $KEYCLOAK_PORT open"             "ss -tlnp | grep -q ':${KEYCLOAK_PORT}'"
    echo ""
  fi

  if [[ "$INSTALL_JASPER" == true ]]; then
    echo -e "${BOLD}  JasperReports${RESET}"
    check_optional_test "  Install directory exists"             "test -d /opt/jasperreports-server"
    echo ""
  fi

  echo -e "${BOLD}  System${RESET}"
  check_test            "  Java installed"                       "java -version 2>&1 | grep -qE '17|21|11'"

  echo ""
  echo -e "  ──────────────────────────────────────────────"
  local total=$(( PASS + FAIL ))
  if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All tests passed ($PASS/$total)${RESET}"
  else
    echo -e "  ${RED}${BOLD}$FAIL test(s) failed — $PASS/$total passed${RESET}"
    echo -e "  ${YELLOW}Tip:${RESET} journalctl -u <service-name> -n 50"
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
  echo -e "  ${BOLD}Service         URL / Port                              Credentials${RESET}"
  echo -e "  ──────────────────────────────────────────────────────────────────────"

  if [[ "$INSTALL_RABBITMQ" == true ]]; then
    echo -e "  ${CYAN}RabbitMQ${RESET}        AMQP  → localhost:${RABBITMQ_PORT}"
    echo -e "                  UI    → http://localhost:${RABBITMQ_MGMT_PORT}           guest / guest"
  fi
  if [[ "$INSTALL_REDIS" == true ]]; then
    echo -e "  ${CYAN}Redis${RESET}           Port  → localhost:${REDIS_PORT}                No password"
  fi
  if [[ "$INSTALL_KEYCLOAK" == true ]]; then
    echo -e "  ${CYAN}Keycloak${RESET}        UI    → http://localhost:${KEYCLOAK_PORT}               Set on first login"
  fi
  if [[ "$INSTALL_JASPER" == true ]]; then
    echo -e "  ${CYAN}JasperReports${RESET}   UI    → http://localhost:${JASPER_PORT}/jasperserver    jasperadmin / jasperadmin"
  fi

  echo -e "  ──────────────────────────────────────────────────────────────────────"
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
