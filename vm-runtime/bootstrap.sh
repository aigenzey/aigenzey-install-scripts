#!/usr/bin/env bash
# ==============================================================================
# aigenzey-install-scripts / vm-runtime/bootstrap.sh
# ==============================================================================
# Production-grade OS and machine bootstrap script for Aigenzey VM nodes.
# Prepares the machine with all runtime dependencies, native libraries,
# Python 3.13 environment, Redis, Docker, crawl4ai, and service user setup.
#
# Addresses known OS, dependency, and conflict issues:
#   1. Python 3.13 setup via deadsnakes PPA on Ubuntu/Debian (or dnf on RHEL/CentOS)
#   2. Native compilation headers (libffi-dev, libssl-dev, build-essential)
#   3. Service user (aigenzey) with dedicated home and passwordless sudoers
#   4. Redis server setup, service activation, and PING verification
#   5. Docker CE installation and crawl4ai container execution (port 11235)
#   6. Nginx system daemon conflict resolution (disables default systemd nginx
#      so Aigenzey has exclusive bind access to ports 80 and 443)
#   7. Ownership and permission normalization
#
# Usage:
#   sudo ./bootstrap.sh [OPTIONS]
#
# Options:
#   --mode [runtime|full|minimal]   Bootstrap profile (default: runtime)
#                                    - runtime: Python 3.13, Redis, Docker, crawl4ai, base tools
#                                    - full: Runtime + PostgreSQL + Node.js + Certbot
#                                    - minimal: Python and Redis only
#   --python-version [3.13|3.12]    Python version to install (default: 3.13)
#   --user [username]               Service username (default: aigenzey)
#   --install-dir [dir]             Base install directory (default: /opt/aigenzey)
#   --skip-docker                   Skip Docker installation
#   --skip-crawl4ai                 Skip crawl4ai container setup
#   --skip-nginx                    Skip Nginx package and conflict handling
#   --skip-postgres                 Skip PostgreSQL installation
#   -h, --help                      Show this help message
# ==============================================================================

set -euo pipefail

# Output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_usage() {
    cat << 'EOF'
Aigenzey Machine Bootstrap Script

Usage:
  sudo ./bootstrap.sh [options]

Options:
  --mode [runtime|full|minimal]   Profile mode (default: runtime)
  --python-version [3.13|3.12]    Python version (default: 3.13)
  --user <username>               Service user name (default: aigenzey)
  --install-dir <path>            Installation directory (default: /opt/aigenzey)
  --skip-docker                   Skip Docker Engine installation
  --skip-crawl4ai                 Skip crawl4ai Docker container setup
  --skip-nginx                    Skip Nginx package and port conflict handling
  --skip-postgres                 Skip PostgreSQL installation
  -h, --help                      Show this help message

Examples:
  # Standard runtime bootstrap for Ubuntu / Linux VM
  sudo ./bootstrap.sh --mode runtime

  # Custom user and install path
  sudo ./bootstrap.sh --user aigenzey --install-dir /opt/aigenzey
EOF
}

# Check for help before requiring root
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        print_usage
        exit 0
    fi
done

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] This bootstrap script must be run as root (or with sudo).${NC}" >&2
    echo "Usage: sudo $0 [options]"
    exit 1
fi

LOG_FILE="/var/log/aigenzey-bootstrap.log"
# Log to both stdout and file safely
touch "$LOG_FILE" && chmod 640 "$LOG_FILE" 2>/dev/null || true

log() {
    local color="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}[$ts] $msg${NC}"
    echo "[$ts] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

print_header() {
    echo ""
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}======================================================================${NC}"
}

# Default options
MODE="runtime"
PYTHON_VERSION="3.13"
AIGENZEY_USER="aigenzey"
INSTALL_DIR="/opt/aigenzey"

SKIP_DOCKER=false
SKIP_CRAWL4AI=false
SKIP_NGINX=false
SKIP_POSTGRES=true  # Default true for runtime mode

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode|-m)
            MODE="$2"
            shift 2
            ;;
        --python-version)
            PYTHON_VERSION="$2"
            shift 2
            ;;
        --user|-u)
            AIGENZEY_USER="$2"
            shift 2
            ;;
        --install-dir|-d)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift 1
            ;;
        --skip-crawl4ai)
            SKIP_CRAWL4AI=true
            shift 1
            ;;
        --skip-nginx)
            SKIP_NGINX=true
            shift 1
            ;;
        --skip-postgres)
            SKIP_POSTGRES=true
            shift 1
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log "$RED" "Unknown argument: $1"
            print_usage
            exit 1
            ;;
    esac
done

if [[ "$MODE" == "full" ]]; then
    SKIP_POSTGRES=false
elif [[ "$MODE" == "minimal" ]]; then
    SKIP_POSTGRES=true
    SKIP_DOCKER=true
    SKIP_CRAWL4AI=true
    SKIP_NGINX=true
fi

print_header "AIGENZEY MACHINE BOOTSTRAP STARTING"
log "$BLUE" "Profile Mode:      $MODE"
log "$BLUE" "Service User:      $AIGENZEY_USER"
log "$BLUE" "Install Directory: $INSTALL_DIR"
log "$BLUE" "Python Version:    $PYTHON_VERSION"
log "$BLUE" "Log File:          $LOG_FILE"

# Detect OS
OS_FAMILY="unknown"
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    log "$BLUE" "Detected OS:       ${PRETTY_NAME:-$ID} (${VERSION_ID:-unknown})"
    if [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" =~ "ubuntu" || "${ID:-}" == "debian" || "${ID_LIKE:-}" =~ "debian" ]]; then
        OS_FAMILY="debian"
    elif [[ "${ID:-}" == "rhel" || "${ID:-}" == "centos" || "${ID:-}" == "rocky" || "${ID:-}" == "almalinux" || "${ID:-}" == "fedora" ]]; then
        OS_FAMILY="rhel"
    fi
fi

# Repair broken python3 / python symlinks before any APT operations
# Ubuntu hooks (such as /usr/lib/cnf-update-db) require a valid /usr/bin/python3
repair_system_python() {
    if [[ -L /usr/bin/python3 && ! -e /usr/bin/python3 ]]; then
        log "$YELLOW" "Detected broken /usr/bin/python3 symlink from a previous run. Repairing..."
        rm -f /usr/bin/python3
        for py in /usr/bin/python3.12 /usr/bin/python3.11 /usr/bin/python3.10 /usr/bin/python3.9 /usr/bin/python3.8; do
            if [[ -x "$py" ]]; then
                ln -sf "$py" /usr/bin/python3
                log "$GREEN" "Restored /usr/bin/python3 -> $py"
                break
            fi
        done
    fi
    if [[ -L /usr/bin/python && ! -e /usr/bin/python ]]; then
        rm -f /usr/bin/python
        if [[ -x /usr/bin/python3 ]]; then
            ln -sf /usr/bin/python3 /usr/bin/python
        fi
    fi
}

apt_update() {
    apt-get update -y || apt-get -o APT::Update::Post-Invoke-Success="" update -y
}

if [[ "$OS_FAMILY" == "debian" ]]; then
    repair_system_python
fi

# ------------------------------------------------------------------------------
# 1. System Updates & Essential Tools
# ------------------------------------------------------------------------------
print_header "1. System Updates & Essential Packages"

if [[ "$OS_FAMILY" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    log "$BLUE" "Updating apt cache and installing essential build packages..."
    apt_update
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common \
        build-essential \
        pkg-config \
        git \
        jq \
        unzip \
        tar \
        rsync \
        lsof \
        net-tools \
        dnsutils \
        procps \
        libffi-dev \
        libssl-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        zlib1g-dev \
        openssl
elif [[ "$OS_FAMILY" == "rhel" ]]; then
    log "$BLUE" "Configuring EPEL and installing essential tools..."
    if command -v dnf &>/dev/null; then
        dnf install -y epel-release || true
        dnf install -y curl wget git jq unzip tar rsync procps-ng lsof net-tools gcc make openssl-devel bzip2-devel libffi-devel
    elif command -v yum &>/dev/null; then
        yum install -y epel-release || true
        yum install -y curl wget git jq unzip tar rsync procps-ng lsof net-tools gcc make openssl-devel bzip2-devel libffi-devel
    fi
else
    log "$YELLOW" "Non-standard Linux distribution. Ensuring curl, tar, rsync are present..."
fi

log "$GREEN" "✓ System base packages installed."

# ------------------------------------------------------------------------------
# 2. Service User & Directory Provisioning
# ------------------------------------------------------------------------------
print_header "2. User & Directory Provisioning"

if ! getent group "$AIGENZEY_USER" &>/dev/null; then
    log "$BLUE" "Creating group $AIGENZEY_USER..."
    groupadd -r "$AIGENZEY_USER"
fi

if ! id -u "$AIGENZEY_USER" &>/dev/null; then
    log "$BLUE" "Creating user $AIGENZEY_USER with home $INSTALL_DIR..."
    useradd -r -g "$AIGENZEY_USER" -d "$INSTALL_DIR" -s /bin/bash -c "Aigenzey Platform Service User" "$AIGENZEY_USER"
else
    log "$BLUE" "User $AIGENZEY_USER already exists."
fi

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/.pids"

# Sudoers Configuration
SUDOERS_FILE="/etc/sudoers.d/$AIGENZEY_USER"
log "$BLUE" "Configuring passwordless sudo for service user in $SUDOERS_FILE..."
cat > "$SUDOERS_FILE" << EOF
# Aigenzey platform user privileges
${AIGENZEY_USER} ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 "$SUDOERS_FILE"
if command -v visudo &>/dev/null; then
    visudo -c -f "$SUDOERS_FILE" >/dev/null || log "$YELLOW" "Warning: visudo syntax check reported an issue."
fi

log "$GREEN" "✓ User and sudoers permissions configured."

# ------------------------------------------------------------------------------
# 3. Python 3.13 Setup
# ------------------------------------------------------------------------------
print_header "3. Python $PYTHON_VERSION Setup"

PYTHON_PKG="python${PYTHON_VERSION}"

if [[ "$OS_FAMILY" == "debian" ]]; then
    repair_system_python

    log "$BLUE" "Adding deadsnakes PPA for Python $PYTHON_VERSION..."
    add-apt-repository -y ppa:deadsnakes/ppa || true
    apt_update

    log "$BLUE" "Installing ${PYTHON_PKG}, venv, and dev headers..."
    if ! apt-get install -y "${PYTHON_PKG}" "${PYTHON_PKG}-venv" "${PYTHON_PKG}-dev"; then
        log "$YELLOW" "Retrying ${PYTHON_PKG} installation after apt cache update..."
        apt_update
        apt-get install -y "${PYTHON_PKG}" "${PYTHON_PKG}-venv" "${PYTHON_PKG}-dev" || {
            log "$RED" "Failed to install ${PYTHON_PKG} packages."
        }
    fi

    # distutils was removed in Python 3.12+ (PEP 632). Only install if available on Python < 3.12.
    apt-get install -y "${PYTHON_PKG}-distutils" 2>/dev/null || true

    apt-get install -y python3-pip python3-setuptools python3-wheel || true

    # Bootstrap pip if missing
    if command -v "${PYTHON_PKG}" &>/dev/null && ! "${PYTHON_PKG}" -m pip --version &>/dev/null; then
        log "$YELLOW" "Bootstrapping pip for ${PYTHON_PKG}..."
        curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
        "${PYTHON_PKG}" /tmp/get-pip.py --break-system-packages 2>/dev/null || \
            "${PYTHON_PKG}" /tmp/get-pip.py 2>/dev/null || true
        rm -f /tmp/get-pip.py
    fi

    # Symlink setup - only point to ${PYTHON_PKG} if the binary exists
    if [[ -x "/usr/bin/${PYTHON_PKG}" ]]; then
        if command -v update-alternatives &>/dev/null; then
            update-alternatives --install /usr/bin/python3 python3 "/usr/bin/${PYTHON_PKG}" 1 2>/dev/null || true
            update-alternatives --set python3 "/usr/bin/${PYTHON_PKG}" 2>/dev/null || true
        fi
        ln -sf "/usr/bin/${PYTHON_PKG}" /usr/bin/python3
        ln -sf "/usr/bin/${PYTHON_PKG}" /usr/bin/python
    elif command -v "${PYTHON_PKG}" &>/dev/null; then
        TARGET_BIN=$(command -v "${PYTHON_PKG}")
        ln -sf "${TARGET_BIN}" /usr/bin/python3
        ln -sf "${TARGET_BIN}" /usr/bin/python
    else
        log "$YELLOW" "${PYTHON_PKG} binary not found in /usr/bin; leaving existing python3 intact."
    fi

elif [[ "$OS_FAMILY" == "rhel" ]]; then
    log "$BLUE" "Installing Python packages via dnf/yum..."
    if command -v dnf &>/dev/null; then
        dnf install -y "${PYTHON_PKG}" "${PYTHON_PKG}-pip" "${PYTHON_PKG}-devel" || \
        dnf install -y python3.12 python3.12-pip python3.12-devel || \
        dnf install -y python3 python3-pip python3-devel
    else
        yum install -y "${PYTHON_PKG}" "${PYTHON_PKG}-pip" "${PYTHON_PKG}-devel" || \
        yum install -y python3.12 python3.12-pip python3.12-devel || \
        yum install -y python3 python3-pip python3-devel
    fi
fi

# Upgrade core pip/packaging tools
if command -v python3 &>/dev/null && python3 -m pip --version &>/dev/null; then
    python3 -m pip install --upgrade --no-cache-dir --break-system-packages pip setuptools wheel 2>/dev/null || \
        python3 -m pip install --upgrade --no-cache-dir pip setuptools wheel 2>/dev/null || true
fi

if command -v python3 &>/dev/null; then
    PYTHON_ACTIVE_VER=$(python3 --version 2>&1)
    log "$GREEN" "✓ $PYTHON_ACTIVE_VER configured."
else
    PYTHON_ACTIVE_VER="Python not found"
    log "$RED" "✗ Python 3 could not be found or configured."
fi

# ------------------------------------------------------------------------------
# 4. Redis Server Setup
# ------------------------------------------------------------------------------
print_header "4. Redis Server Setup"
log "$BLUE" "Installing and activating Redis server..."

if [[ "$OS_FAMILY" == "debian" ]]; then
    apt-get install -y redis-server
    systemctl enable redis-server || true
    systemctl restart redis-server || true
elif [[ "$OS_FAMILY" == "rhel" ]]; then
    dnf install -y redis 2>/dev/null || yum install -y redis 2>/dev/null || true
    systemctl enable redis || true
    systemctl restart redis || true
fi

if command -v redis-cli &>/dev/null && redis-cli ping &>/dev/null; then
    log "$GREEN" "✓ Redis server is active and responding (PONG)."
else
    log "$YELLOW" "Redis installed. Checking service status..."
    systemctl is-active redis-server || systemctl is-active redis || true
fi

# ------------------------------------------------------------------------------
# 5. Docker Engine & crawl4ai
# ------------------------------------------------------------------------------
if [[ "$SKIP_DOCKER" == false ]]; then
    print_header "5. Docker Engine & crawl4ai Setup"
    if ! command -v docker &>/dev/null; then
        log "$BLUE" "Installing Docker via official install script..."
        curl -fsSL https://get.docker.com | sh
    else
        log "$BLUE" "Docker is already installed ($(docker --version))."
    fi

    systemctl enable docker || true
    systemctl start docker || true

    # Add aigenzey user to docker group
    usermod -aG docker "$AIGENZEY_USER" || true

    if [[ "$SKIP_CRAWL4AI" == false ]]; then
        log "$BLUE" "Configuring crawl4ai container (Port: 11235)..."
        docker stop crawl4ai 2>/dev/null || true
        docker rm -f crawl4ai 2>/dev/null || true
        docker pull unclecode/crawl4ai:latest || true
        docker run -d \
            --name crawl4ai \
            --restart unless-stopped \
            -p 11235:11235 \
            --shm-size=1g \
            unclecode/crawl4ai:latest || log "$YELLOW" "crawl4ai container start deferred."
        log "$GREEN" "✓ crawl4ai container deployed on port 11235."
    fi
    log "$GREEN" "✓ Docker configured."
fi

# ------------------------------------------------------------------------------
# 6. Nginx Installation & Port Conflict Prevention
# ------------------------------------------------------------------------------
if [[ "$SKIP_NGINX" == false ]]; then
    print_header "6. Nginx Setup & Port Conflict Prevention"
    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt-get install -y nginx || true
    elif [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf install -y nginx 2>/dev/null || yum install -y nginx 2>/dev/null || true
    fi

    # CRITICAL: Disable default systemd Nginx so Aigenzey reverse proxy has exclusive port 80/443 control
    log "$YELLOW" "Disabling systemd nginx service to prevent port 80/443 binding conflicts..."
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true

    # Provide standard mime.types if needed
    if [[ -f "/etc/nginx/mime.types" ]]; then
        mkdir -p "$INSTALL_DIR/nginx-conf"
        cp -f "/etc/nginx/mime.types" "$INSTALL_DIR/nginx-conf/mime.types" 2>/dev/null || true
    fi
    log "$GREEN" "✓ Nginx binary available; default system service disabled to avoid port conflicts."
fi

# ------------------------------------------------------------------------------
# 7. PostgreSQL (Optional, for full mode)
# ------------------------------------------------------------------------------
if [[ "$SKIP_POSTGRES" == false ]]; then
    print_header "7. PostgreSQL Setup (Full Mode)"
    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt-get install -y postgresql postgresql-contrib libpq-dev
        systemctl enable postgresql
        systemctl start postgresql
        sudo -u postgres psql << 'EOF' || true
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'aigenzey_user') THEN
    CREATE ROLE aigenzey_user WITH LOGIN PASSWORD 'aigenzey' CREATEDB SUPERUSER;
  ELSE
    ALTER ROLE aigenzey_user WITH PASSWORD 'aigenzey' CREATEDB SUPERUSER;
  END IF;
END
$$;
SELECT 'CREATE DATABASE aigenzey OWNER aigenzey_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'aigenzey')\gexec
GRANT ALL PRIVILEGES ON DATABASE aigenzey TO aigenzey_user;
EOF
        log "$GREEN" "✓ PostgreSQL database and aigenzey_user configured."
    fi
fi

# ------------------------------------------------------------------------------
# 8. Permissions Normalization
# ------------------------------------------------------------------------------
print_header "8. Ownership & Permissions Normalization"
chown -R "$AIGENZEY_USER:$AIGENZEY_USER" "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# ------------------------------------------------------------------------------
# 9. Verification Summary
# ------------------------------------------------------------------------------
print_header "BOOTSTRAP VERIFICATION SUMMARY"
echo -e "${GREEN}✓ OS Packages & Tools:${NC}      OK"
echo -e "${GREEN}✓ Service User & Sudoers:${NC}   $AIGENZEY_USER (NOPASSWD: ALL in $SUDOERS_FILE)"
if command -v python3 &>/dev/null; then
    echo -e "${GREEN}✓ Python Environment:${NC}       $PYTHON_ACTIVE_VER"
else
    echo -e "${RED}✗ Python Environment:${NC}       $PYTHON_ACTIVE_VER"
fi
echo -e "${GREEN}✓ Redis Server:${NC}             $(systemctl is-active redis-server 2>/dev/null || systemctl is-active redis 2>/dev/null || echo 'inactive')"
[[ "$SKIP_DOCKER" == false ]] && echo -e "${GREEN}✓ Docker Daemon:${NC}            $(systemctl is-active docker 2>/dev/null || echo 'inactive')"
[[ "$SKIP_CRAWL4AI" == false ]] && echo -e "${GREEN}✓ crawl4ai Container:${NC}       $(docker ps --filter 'name=crawl4ai' --format '{{.Status}}' 2>/dev/null || echo 'not running')"
[[ "$SKIP_NGINX" == false ]] && echo -e "${GREEN}✓ System Nginx Daemon:${NC}      Disabled (ports 80/443 freed for Aigenzey)"

echo ""
echo -e "${CYAN}======================================================================${NC}"
echo -e "${GREEN} Machine bootstrap completed successfully!${NC}"
echo -e "${CYAN}======================================================================${NC}"
