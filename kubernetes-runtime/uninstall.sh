#!/usr/bin/env bash
#
# Aigenzey Kubernetes Runtime Teardown Script
# Cleans up deployed runtime resources from a Kubernetes cluster.
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
DELETE_NAMESPACE=false
FORCE=false

print_usage() {
    cat << 'EOF'
Aigenzey Kubernetes Runtime Teardown

Usage:
  ./uninstall.sh [options]

Options:
  -n, --namespace <ns>    Target Kubernetes namespace (default: aigenzey-runtime)
  --delete-namespace      Delete the entire namespace and all resources within it
  -y, --yes, --force      Skip confirmation prompts
  -h, --help              Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --delete-namespace)
            DELETE_NAMESPACE=true
            shift 1
            ;;
        -y|--yes|--force)
            FORCE=true
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

if ! command -v kubectl &>/dev/null; then
    log_error "kubectl is not installed or not in PATH."
    exit 1
fi

if [[ "${FORCE}" == false ]]; then
    echo -e "${YELLOW}WARNING: This will delete Aigenzey runtime resources in namespace '${NAMESPACE}'.${NC}"
    read -rp "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" && "${CONFIRM}" != "y" ]]; then
        log_info "Uninstallation aborted."
        exit 0
    fi
fi

if [[ "${DELETE_NAMESPACE}" == true ]]; then
    log_info "Deleting entire namespace '${NAMESPACE}'..."
    kubectl delete namespace "${NAMESPACE}" --ignore-not-found
    log_success "Namespace '${NAMESPACE}' and all resources deleted."
    exit 0
fi

log_info "Removing Aigenzey Runtime components from namespace '${NAMESPACE}'..."

# Delete Ingress
kubectl delete ingress aigenzey-runtime-ingress -n "${NAMESPACE}" --ignore-not-found

# Delete Nginx SSL Reverse Proxy
kubectl delete deployment nginx-deployment -n "${NAMESPACE}" --ignore-not-found
kubectl delete service nginx-service -n "${NAMESPACE}" --ignore-not-found
kubectl delete configmap nginx-config -n "${NAMESPACE}" --ignore-not-found
kubectl delete secret are-nginx-tls -n "${NAMESPACE}" --ignore-not-found

# Delete AI Gateway
kubectl delete deployment ai-gateway-deployment -n "${NAMESPACE}" --ignore-not-found
kubectl delete service ai-gateway-service -n "${NAMESPACE}" --ignore-not-found
kubectl delete configmap ai-gateway-config -n "${NAMESPACE}" --ignore-not-found
kubectl delete secret ai-gateway-secret -n "${NAMESPACE}" --ignore-not-found

# Delete ARE
kubectl delete deployment are-deployment -n "${NAMESPACE}" --ignore-not-found
kubectl delete service are-service -n "${NAMESPACE}" --ignore-not-found
kubectl delete configmap are-config -n "${NAMESPACE}" --ignore-not-found
kubectl delete secret are-secret -n "${NAMESPACE}" --ignore-not-found
kubectl delete pvc are-pvc -n "${NAMESPACE}" --ignore-not-found

# Delete crawl4ai
kubectl delete deployment crawl4ai -n "${NAMESPACE}" --ignore-not-found
kubectl delete service crawl4ai-service -n "${NAMESPACE}" --ignore-not-found

# Delete Redis
kubectl delete deployment redis -n "${NAMESPACE}" --ignore-not-found
kubectl delete service redis-service -n "${NAMESPACE}" --ignore-not-found

log_success "Aigenzey Runtime resources successfully uninstalled from namespace '${NAMESPACE}'."
