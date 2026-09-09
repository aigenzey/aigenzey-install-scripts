#!/usr/bin/env bash
#
# Aigenzey Runtime VM Installation Script
# Installs runtime dependencies, creates the aigenzey user, downloads the runtime package,
# configures environment properties, and registers systemd services.
#
# This script must be run as root or with sudo.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
Aigenzey Runtime VM Installer

Usage:
  sudo ./install.sh [options]

Package Sourcing Options (one of):
  --version <version>           Release version to install (default: 1.0.0)
  --tarball <path>              Path to local runtime tar.gz package
  --url <url>                   Direct HTTP/S download URL for runtime package
  --gcloud                      Download package using Google Cloud Artifact Registry

Google Cloud Options (when using --gcloud):
  --project-id <id>             GCP Project ID (default: aigenzey-dev)
  --repo <repo>                 Artifact Registry generic repository (default: aigenzey-releases)
  --location <location>         Artifact Registry region (default: us-central1)
  --package <name>              Package name (default: runtime-vm-release)

Configuration Options:
  --config <file>               Path to existing config.properties file
  --api-url <url>               Aigenzey Management API URL (default: https://api.platform.aigenzey.com)
  --instance-name <name>        Runtime instance name
  --instanceadmin-email <email> Instance administrator email
  --instanceadmin-password <pw> Instance administrator password
  --default-org <org>           Default organization name (default: default)

Installation Flags:
  --skip-bootstrap              Skip machine OS/package bootstrap
  --skip-deps                   Alias for --skip-bootstrap
  --skip-docker                 Skip Docker installation
  --skip-crawl4ai               Skip crawl4ai container setup
  --python-version <ver>        Python version (default: 3.13)
  --no-systemd                  Do not install or start systemd service
  -h, --help                    Show this help message

Examples:
  # Install with local tarball and config file
  sudo ./install.sh --tarball /tmp/aigenzey-runtime-release-1.0.0.tar.gz --config ./config.properties

  # Install from public Cloud Storage URL
  sudo ./install.sh --version 1.0.0 --url https://storage.googleapis.com/aigenzey-releases/aigenzey-runtime-release-1.0.0.tar.gz

  # Install on GCP Compute Engine VM using metadata and Artifact Registry
  sudo ./install.sh --version 1.0.0 --gcloud
EOF
}

# Check for help before requiring root
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        print_usage
        exit 0
    fi
done

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (or with sudo)."
    echo "Usage: sudo $0 [options]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configurations
INSTALL_VERSION="1.0.0"
PYTHON_VERSION="3.13"
TARBALL_PATH=""
DOWNLOAD_URL=""
USE_GCLOUD=false
PROJECT_ID="${PROJECT_ID:-aigenzey-dev}"
ARTIFACT_REPO="${ARTIFACT_REGISTRY_REPO:-aigenzey-releases}"
ARTIFACT_LOCATION="${ARTIFACT_REGISTRY_LOCATION:-us-central1}"
PACKAGE_NAME="${PACKAGE_NAME:-runtime-vm-release}"

USER_NAME="aigenzey"
USER_HOME="/opt/aigenzey"
CONFIG_FILE_SOURCE=""

# Configuration properties
AIGENZEY_API_URL="https://api.platform.aigenzey.com"
INSTANCE_NAME=""
INSTANCEADMIN_EMAIL="instanceadmin@aigenzey.com"
INSTANCEADMIN_PASSWORD=""
DEFAULT_ORG="default"

SKIP_BOOTSTRAP=false
SKIP_DOCKER=false
SKIP_CRAWL4AI=false
ENABLE_SYSTEMD=true

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            INSTALL_VERSION="${2#v}" # strip leading 'v' if provided
            shift 2
            ;;
        --python-version)
            PYTHON_VERSION="$2"
            shift 2
            ;;
        --tarball)
            TARBALL_PATH="$2"
            shift 2
            ;;
        --url)
            DOWNLOAD_URL="$2"
            shift 2
            ;;
        --gcloud)
            USE_GCLOUD=true
            shift 1
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --repo)
            ARTIFACT_REPO="$2"
            shift 2
            ;;
        --location)
            ARTIFACT_LOCATION="$2"
            shift 2
            ;;
        --package)
            PACKAGE_NAME="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE_SOURCE="$2"
            shift 2
            ;;
        --api-url)
            AIGENZEY_API_URL="$2"
            shift 2
            ;;
        --instance-name)
            INSTANCE_NAME="$2"
            shift 2
            ;;
        --instanceadmin-email)
            INSTANCEADMIN_EMAIL="$2"
            shift 2
            ;;
        --instanceadmin-password)
            INSTANCEADMIN_PASSWORD="$2"
            shift 2
            ;;
        --default-org)
            DEFAULT_ORG="$2"
            shift 2
            ;;
        --skip-bootstrap|--skip-deps)
            SKIP_BOOTSTRAP=true
            shift 1
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift 1
            ;;
        --skip-crawl4ai)
            SKIP_CRAWL4AI=true
            shift 1
            ;;
        --no-systemd)
            ENABLE_SYSTEMD=false
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

echo "=========================================================="
echo "         Aigenzey Runtime Engine - VM Installer           "
echo "=========================================================="
log_info "Target version: ${INSTALL_VERSION}"
log_info "Installation directory: ${USER_HOME}"

# Step 1: Bootstrap machine dependencies via bootstrap.sh
if [[ "${SKIP_BOOTSTRAP}" == false ]]; then
    log_info "Bootstrapping machine environment via ${SCRIPT_DIR}/bootstrap.sh..."
    BOOTSTRAP_CMD=("bash" "${SCRIPT_DIR}/bootstrap.sh" "--mode" "runtime" "--user" "${USER_NAME}" "--install-dir" "${USER_HOME}" "--python-version" "${PYTHON_VERSION}")
    if [[ "${SKIP_DOCKER}" == true ]]; then
        BOOTSTRAP_CMD+=("--skip-docker")
    fi
    if [[ "${SKIP_CRAWL4AI}" == true ]]; then
        BOOTSTRAP_CMD+=("--skip-crawl4ai")
    fi
    "${BOOTSTRAP_CMD[@]}"
    log_success "Machine bootstrap complete."
else
    log_info "Skipping machine bootstrap (--skip-bootstrap specified)."
fi

# Step 4: Configure config.properties
TARGET_CONFIG="${USER_HOME}/config.properties"

if [[ -n "${CONFIG_FILE_SOURCE}" && -f "${CONFIG_FILE_SOURCE}" ]]; then
    log_info "Copying configuration from ${CONFIG_FILE_SOURCE}..."
    cp "${CONFIG_FILE_SOURCE}" "${TARGET_CONFIG}"
else
    # Check if running on GCP Compute Engine to load metadata attributes if available
    METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
    METADATA_HEADER="Metadata-Flavor: Google"
    if curl -sf --connect-timeout 2 -H "${METADATA_HEADER}" "${METADATA_URL}/" &>/dev/null; then
        log_info "Discovered Google Cloud metadata service. Reading instance attributes..."
        AIGENZEY_API_URL=$(curl -sf -H "${METADATA_HEADER}" "${METADATA_URL}/AIGENZEY_API_URL" || echo "${AIGENZEY_API_URL}")
        INSTANCE_NAME=$(curl -sf -H "${METADATA_HEADER}" "${METADATA_URL}/INSTANCE_NAME" || echo "${INSTANCE_NAME}")
        INSTANCEADMIN_EMAIL=$(curl -sf -H "${METADATA_HEADER}" "${METADATA_URL}/INSTANCEADMIN_EMAIL" || echo "${INSTANCEADMIN_EMAIL}")
        INSTANCEADMIN_PASSWORD=$(curl -sf -H "${METADATA_HEADER}" "${METADATA_URL}/INSTANCEADMIN_PASSWORD" || echo "${INSTANCEADMIN_PASSWORD}")
        DEFAULT_ORG=$(curl -sf -H "${METADATA_HEADER}" "${METADATA_URL}/DEFAULT_ORG" || echo "${DEFAULT_ORG}")
    fi

    # Fallback to hostname if instance name is still empty
    if [[ -z "${INSTANCE_NAME}" ]]; then
        INSTANCE_NAME="$(hostname -s 2>/dev/null || echo "runtime-node-1")"
    fi

    log_info "Generating configuration file at ${TARGET_CONFIG}..."
    cat > "${TARGET_CONFIG}" <<EOF
# Aigenzey Runtime Configuration
AIGENZEY_API_URL=${AIGENZEY_API_URL}
INSTANCE_NAME=${INSTANCE_NAME}
INSTANCEADMIN_EMAIL=${INSTANCEADMIN_EMAIL}
INSTANCEADMIN_PASSWORD=${INSTANCEADMIN_PASSWORD}
DEFAULT_ORG=${DEFAULT_ORG}
EOF
fi

chown "${USER_NAME}:${USER_NAME}" "${TARGET_CONFIG}"
chmod 600 "${TARGET_CONFIG}"
log_success "Configuration written to ${TARGET_CONFIG}"

# Step 5: Acquire and extract release tarball
TAR_FILENAME="aigenzey-runtime-release-${INSTALL_VERSION}.tar.gz"
DEST_TARBALL="${USER_HOME}/${TAR_FILENAME}"

if [[ -n "${TARBALL_PATH}" ]]; then
    if [[ ! -f "${TARBALL_PATH}" ]]; then
        log_error "Specified tarball not found at: ${TARBALL_PATH}"
        exit 1
    fi
    log_info "Using local tarball from ${TARBALL_PATH}..."
    cp "${TARBALL_PATH}" "${DEST_TARBALL}"
elif [[ -n "${DOWNLOAD_URL}" ]]; then
    log_info "Downloading package from URL: ${DOWNLOAD_URL}..."
    curl -fSL "${DOWNLOAD_URL}" -o "${DEST_TARBALL}"
elif [[ "${USE_GCLOUD}" == true ]]; then
    log_info "Downloading package from Google Artifact Registry..."
    if ! command -v gcloud &>/dev/null; then
        log_error "gcloud CLI is required for Artifact Registry downloads."
        exit 1
    fi
    gcloud artifacts generic download \
      --destination="${USER_HOME}" \
      --location="${ARTIFACT_LOCATION}" \
      --project="${PROJECT_ID}" \
      --repository="${ARTIFACT_REPO}" \
      --package="${PACKAGE_NAME}" \
      --version="${INSTALL_VERSION}" \
      --name="${TAR_FILENAME}"
else
    # Default: attempt download from public releases bucket
    DEFAULT_BUCKET_URL="https://storage.googleapis.com/aigenzey-releases/${TAR_FILENAME}"
    log_info "Attempting download from default releases repository: ${DEFAULT_BUCKET_URL}..."
    if curl -fSL "${DEFAULT_BUCKET_URL}" -o "${DEST_TARBALL}" 2>/dev/null; then
        log_success "Downloaded ${TAR_FILENAME} from releases repository."
    else
        log_warn "Could not download from default repository. Checking if ${DEST_TARBALL} already exists..."
        if [[ ! -f "${DEST_TARBALL}" ]]; then
            log_error "No runtime archive found. Provide package via --tarball <path>, --url <url>, or --gcloud."
            exit 1
        fi
    fi
fi

chown "${USER_NAME}:${USER_NAME}" "${DEST_TARBALL}"

# Step 6: Extract archive and setup symlink
EXTRACT_DIR="aigenzey-release-${INSTALL_VERSION}"
log_info "Extracting ${DEST_TARBALL} into ${USER_HOME}..."
sudo -u "${USER_NAME}" tar -xzf "${DEST_TARBALL}" -C "${USER_HOME}"

cd "${USER_HOME}"
if [[ -L "aigenzey-runtime" || -e "aigenzey-runtime" ]]; then
    rm -rf "aigenzey-runtime"
fi
ln -s "${EXTRACT_DIR}" "aigenzey-runtime"
log_success "Package extracted and symlinked at ${USER_HOME}/aigenzey-runtime"

# Step 7: Run aigenzey setup as aigenzey user
RUNTIME_DIR="${USER_HOME}/aigenzey-runtime"
if [[ ! -f "${RUNTIME_DIR}/aigenzey-service.sh" ]]; then
    log_error "aigenzey-service.sh not found inside extracted archive at ${RUNTIME_DIR}"
    exit 1
fi

chmod +x "${RUNTIME_DIR}/aigenzey-service.sh"

log_info "Executing Aigenzey runtime environment setup..."
sudo -u "${USER_NAME}" bash -c "cd '${RUNTIME_DIR}' && ./aigenzey-service.sh setup --runtime"

log_info "Configuring production environment profile..."
sudo -u "${USER_NAME}" bash -c "cd '${RUNTIME_DIR}' && ./aigenzey-service.sh env prod"

# Step 8: Configure systemd service
if [[ "${ENABLE_SYSTEMD}" == true ]]; then
    log_info "Installing systemd service unit (aigenzey-runtime.service)..."
    SERVICE_UNIT_SRC="${SCRIPT_DIR}/aigenzey-runtime.service"
    if [[ -f "${SERVICE_UNIT_SRC}" ]]; then
        cp "${SERVICE_UNIT_SRC}" /etc/systemd/system/aigenzey-runtime.service
    else
        cat > /etc/systemd/system/aigenzey-runtime.service <<EOF
[Unit]
Description=Aigenzey Agent Runtime Engine and Services
After=network.target docker.service redis.service
Wants=docker.service redis.service

[Service]
Type=forking
User=${USER_NAME}
Group=${USER_NAME}
WorkingDirectory=${RUNTIME_DIR}
EnvironmentFile=-${TARGET_CONFIG}
ExecStart=${RUNTIME_DIR}/aigenzey-service.sh start --runtime --no-arp -f ${TARGET_CONFIG}
ExecStop=${RUNTIME_DIR}/aigenzey-service.sh stop --runtime
ExecReload=${RUNTIME_DIR}/aigenzey-service.sh restart --runtime -f ${TARGET_CONFIG}
Restart=on-failure
RestartSec=10s
TimeoutStartSec=180
TimeoutStopSec=60
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable aigenzey-runtime
    log_info "Starting aigenzey-runtime systemd service..."
    systemctl restart aigenzey-runtime
    log_success "Systemd service aigenzey-runtime started."
else
    log_info "Starting runtime services directly without systemd..."
    sudo -u "${USER_NAME}" bash -c "cd '${RUNTIME_DIR}' && ./aigenzey-service.sh start --runtime --no-arp -f '${TARGET_CONFIG}'"
fi

# Step 9: Verify running services
log_info "Verifying runtime health..."
sleep 5

# Check ARE health endpoint (port 8000)
ARE_HEALTH=false
for i in {1..12}; do
    if curl -sf http://localhost:8000/docs &>/dev/null || curl -sf http://localhost:8000/api/health &>/dev/null; then
        ARE_HEALTH=true
        break
    fi
    sleep 3
done

echo ""
echo "=========================================================="
echo "          Aigenzey Runtime Installation Summary           "
echo "=========================================================="
echo "Status:"
if [[ "${ARE_HEALTH}" == true ]]; then
    echo -e "  ARE Service (Port 8000):        ${GREEN}RUNNING (Healthy)${NC}"
else
    echo -e "  ARE Service (Port 8000):        ${YELLOW}STARTING (Check logs)${NC}"
fi

if curl -sf http://localhost:11235/health &>/dev/null || docker ps | grep -q crawl4ai; then
    echo -e "  crawl4ai (Port 11235):          ${GREEN}RUNNING${NC}"
else
    echo -e "  crawl4ai (Port 11235):          ${YELLOW}NOT RUNNING${NC}"
fi

if systemctl is-active --quiet redis || systemctl is-active --quiet redis-server; then
    echo -e "  Redis Server (Port 6379):       ${GREEN}ACTIVE${NC}"
else
    echo -e "  Redis Server (Port 6379):       ${YELLOW}CHECK STATUS${NC}"
fi

echo ""
echo "Files & Paths:"
echo "  Runtime directory:  ${USER_HOME}/aigenzey-runtime"
echo "  Configuration:      ${TARGET_CONFIG}"
echo "  Logs:               ${USER_HOME}/aigenzey-runtime/logs/"
echo ""
echo "Management Commands:"
echo "  sudo systemctl status aigenzey-runtime"
echo "  sudo systemctl restart aigenzey-runtime"
echo "  sudo systemctl stop aigenzey-runtime"
echo "  ${SCRIPT_DIR}/service.sh logs"
echo "=========================================================="
log_success "Aigenzey Runtime installation finished successfully!"
