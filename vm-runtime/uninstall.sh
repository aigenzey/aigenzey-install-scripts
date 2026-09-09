#!/usr/bin/env bash
#
# Aigenzey Runtime VM Uninstallation Script
# Stops services, removes systemd configuration, cleans up Docker containers,
# and optionally purges user files and permissions.
#
# Must be run as root or with sudo.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_usage() {
    cat << 'EOF'
Aigenzey Runtime VM Uninstaller

Usage:
  sudo ./uninstall.sh [options]

Options:
  -y, --yes, --force     Skip confirmation prompts and uninstall immediately
  --keep-data            Retain runtime data and logs in /opt/aigenzey
  -h, --help             Show this help message
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
    log_error "This script must be run as root (or with sudo)."
    echo "Usage: sudo $0 [options]"
    exit 1
fi

FORCE=false
KEEP_DATA=false
USER_NAME="aigenzey"
USER_HOME="/opt/aigenzey"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--force)
            FORCE=true
            shift 1
            ;;
        --keep-data)
            KEEP_DATA=true
            shift 1
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            print_usage
            exit 1
            ;;
    esac
done

if [[ "${FORCE}" == false ]]; then
    echo -e "${YELLOW}WARNING: This will stop all Aigenzey runtime services and remove runtime system configurations.${NC}"
    read -rp "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" && "${CONFIRM}" != "y" ]]; then
        log_info "Uninstallation aborted."
        exit 0
    fi
fi

# 1. Stop and disable systemd service
if systemctl list-unit-files | grep -q "aigenzey-runtime.service"; then
    log_info "Stopping and disabling aigenzey-runtime systemd service..."
    systemctl stop aigenzey-runtime 2>/dev/null || true
    systemctl disable aigenzey-runtime 2>/dev/null || true
    rm -f /etc/systemd/system/aigenzey-runtime.service
    systemctl daemon-reload
    log_success "Systemd service removed."
fi

# 2. Stop running services directly if aigenzey-service.sh exists
if [[ -x "${USER_HOME}/aigenzey-runtime/aigenzey-service.sh" ]]; then
    log_info "Stopping Aigenzey runtime services..."
    sudo -u "${USER_NAME}" "${USER_HOME}/aigenzey-runtime/aigenzey-service.sh" stop --runtime 2>/dev/null || true
fi

# 3. Clean up crawl4ai container
if command -v docker &>/dev/null; then
    if docker ps -a --format '{{.Names}}' | grep -q '^crawl4ai$'; then
        log_info "Stopping and removing crawl4ai container..."
        docker stop crawl4ai 2>/dev/null || true
        docker rm crawl4ai 2>/dev/null || true
        log_success "crawl4ai container removed."
    fi
fi

# 4. Remove sudoers rule
if [[ -f "/etc/sudoers.d/${USER_NAME}" ]]; then
    log_info "Removing /etc/sudoers.d/${USER_NAME}..."
    rm -f "/etc/sudoers.d/${USER_NAME}"
fi

# 5. Clean up user data
if [[ "${KEEP_DATA}" == true ]]; then
    log_info "Preserving user data in ${USER_HOME} (--keep-data enabled)."
else
    if [[ -d "${USER_HOME}" ]]; then
        log_info "Removing ${USER_HOME}..."
        rm -rf "${USER_HOME}"
        log_success "${USER_HOME} removed."
    fi

    # Delete user and group if present
    if id -u "${USER_NAME}" &>/dev/null; then
        log_info "Removing system user ${USER_NAME}..."
        userdel "${USER_NAME}" 2>/dev/null || true
    fi
    if getent group "${USER_NAME}" &>/dev/null; then
        groupdel "${USER_NAME}" 2>/dev/null || true
    fi
fi

log_success "Aigenzey Runtime uninstallation completed."
