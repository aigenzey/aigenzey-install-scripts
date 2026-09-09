#!/usr/bin/env bash
#
# Aigenzey Kubernetes Image Registry Credentials Setup
# Creates or updates the image pull secret in Kubernetes for private Artifact Registry access.
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

NAMESPACE="aigenzey-runtime"
SECRET_NAME="aigenzey-registry-secret"
REGISTRY_SERVER="https://us-central1-docker.pkg.dev"

KEY_FILE=""
JSON_FILE=""
USE_GCLOUD_TOKEN=false
USERNAME=""
PASSWORD=""

print_usage() {
    cat << 'EOF'
Aigenzey Kubernetes Registry Credentials Setup

Usage:
  ./setup-credentials.sh [options]

Authentication Modes (one required):
  --key-file <file>        Base64-encoded GCP service account key (e.g. aigenzey-image-access.txt)
  --json-key <file>        Plain GCP service account JSON key file
  --gcloud-token           Use current gcloud OAuth2 access token
  --username <user>        Standard docker registry username (must provide with --password)
  --password <pass>        Standard docker registry password/token

Configuration Options:
  -n, --namespace <ns>     Target Kubernetes namespace (default: aigenzey-runtime)
  --secret-name <name>     Kubernetes secret name (default: aigenzey-registry-secret)
  --server <url>           Registry server (default: https://us-central1-docker.pkg.dev)
  -h, --help               Show this help message

Examples:
  # Using the customer base64 key file provided by Aigenzey
  ./setup-credentials.sh --key-file aigenzey-image-access.txt

  # Using a standard GCP service account JSON key
  ./setup-credentials.sh --json-key sa-key.json -n aigenzey-runtime

  # Using active gcloud CLI credentials
  ./setup-credentials.sh --gcloud-token
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --key-file)
            KEY_FILE="$2"
            shift 2
            ;;
        --json-key)
            JSON_FILE="$2"
            shift 2
            ;;
        --gcloud-token)
            USE_GCLOUD_TOKEN=true
            shift 1
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --secret-name)
            SECRET_NAME="$2"
            shift 2
            ;;
        --server)
            REGISTRY_SERVER="$2"
            shift 2
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

# Validate kubectl
if ! command -v kubectl &>/dev/null; then
    log_error "kubectl is not installed or not in PATH."
    exit 1
fi

# Ensure namespace exists
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    log_info "Creating namespace '${NAMESPACE}'..."
    kubectl create namespace "${NAMESPACE}"
fi

log_info "Configuring secret '${SECRET_NAME}' in namespace '${NAMESPACE}'..."

if [[ -n "${KEY_FILE}" ]]; then
    if [[ ! -f "${KEY_FILE}" ]]; then
        log_error "Key file not found: ${KEY_FILE}"
        exit 1
    fi
    log_info "Creating secret from base64 key file..."
    B64_KEY="$(tr -d '\r\n' < "${KEY_FILE}")"
    kubectl create secret docker-registry "${SECRET_NAME}" \
        --docker-server="${REGISTRY_SERVER}" \
        --docker-username="_json_key_base64" \
        --docker-password="${B64_KEY}" \
        --docker-email="serviceaccount@aigenzey.internal" \
        --namespace="${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -

elif [[ -n "${JSON_FILE}" ]]; then
    if [[ ! -f "${JSON_FILE}" ]]; then
        log_error "JSON key file not found: ${JSON_FILE}"
        exit 1
    fi
    log_info "Creating secret from GCP service account JSON..."
    JSON_KEY="$(cat "${JSON_FILE}")"
    kubectl create secret docker-registry "${SECRET_NAME}" \
        --docker-server="${REGISTRY_SERVER}" \
        --docker-username="_json_key" \
        --docker-password="${JSON_KEY}" \
        --docker-email="serviceaccount@aigenzey.internal" \
        --namespace="${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -

elif [[ "${USE_GCLOUD_TOKEN}" == true ]]; then
    if ! command -v gcloud &>/dev/null; then
        log_error "gcloud CLI is required for --gcloud-token."
        exit 1
    fi
    log_info "Retrieving access token from gcloud..."
    ACCESS_TOKEN="$(gcloud auth print-access-token)"
    kubectl create secret docker-registry "${SECRET_NAME}" \
        --docker-server="${REGISTRY_SERVER}" \
        --docker-username="oauth2accesstoken" \
        --docker-password="${ACCESS_TOKEN}" \
        --docker-email="not-used@example.com" \
        --namespace="${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -
    log_warn "Note: gcloud OAuth2 tokens are short-lived (~60 minutes). Consider using a service account key for persistent workloads."

elif [[ -n "${USERNAME}" && -n "${PASSWORD}" ]]; then
    log_info "Creating secret with username and password..."
    kubectl create secret docker-registry "${SECRET_NAME}" \
        --docker-server="${REGISTRY_SERVER}" \
        --docker-username="${USERNAME}" \
        --docker-password="${PASSWORD}" \
        --docker-email="admin@example.com" \
        --namespace="${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -

else
    log_error "No authentication method provided. Use --key-file, --json-key, --gcloud-token, or --username/--password."
    print_usage
    exit 1
fi

log_success "Image pull secret '${SECRET_NAME}' successfully created/updated in namespace '${NAMESPACE}'."
