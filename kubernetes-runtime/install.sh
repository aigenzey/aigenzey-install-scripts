#!/usr/bin/env bash
#
# Aigenzey Kubernetes Runtime Installer
# Deploys Agent Runtime Engine (ARE), AI Gateway, Redis, crawl4ai, and ingress
# into a target Kubernetes cluster.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

# Default configuration values
NAMESPACE="aigenzey-runtime"
CONFIG_FILE=""
KEY_FILE=""
JSON_KEY=""
USE_GCLOUD_TOKEN=false
SECRET_NAME="aigenzey-registry-secret"

AIGENZEY_API_URL="https://api.platform.aigenzey.com"
INSTANCE_NAME="aigenzey-k8s-runtime"
DEFAULT_ORG="default"
POD_REGION="us-central1"
INSTANCEADMIN_EMAIL="instanceadmin@aigenzey.com"
INSTANCEADMIN_PASSWORD="SecretPassword123"

GOOGLE_API_KEY=""
OPENAI_API_KEY=""
ANTHROPIC_API_KEY=""
SECRET_KEY=""

ARE_IMAGE="us-central1-docker.pkg.dev/aigenzey-dev/aigenzey-images/are-service:latest"
AI_GATEWAY_IMAGE="us-central1-docker.pkg.dev/aigenzey-dev/aigenzey-images/ai-gateway-service:latest"
CRAWL4AI_IMAGE="unclecode/crawl4ai:latest"
REDIS_IMAGE="redis:7-alpine"

ENABLE_AI_GATEWAY=true
ENABLE_NGINX=true
NGINX_HOST="${NGINX_HOST:-_}"
ENABLE_INGRESS=false
INGRESS_HOST="runtime.example.com"
TLS_CERT_FILE="${TLS_CERT_FILE:-}"
TLS_KEY_FILE="${TLS_KEY_FILE:-}"
DRY_RUN=false
WAIT_TIMEOUT="300s"

print_usage() {
    cat << 'EOF'
Aigenzey Kubernetes Runtime Installer

Usage:
  ./install.sh [options]

Target & Config Options:
  -n, --namespace <ns>          Kubernetes namespace (default: aigenzey-runtime)
  --config <file>               Path to environment config file (e.g. config.env)

Registry Authentication Options:
  --key-file <file>             Base64 service account key (e.g. aigenzey-image-access.txt)
  --json-key <file>             GCP service account JSON key file
  --gcloud-token                Use active gcloud token for registry auth
  --secret-name <name>          Image pull secret name (default: aigenzey-registry-secret)

Application Parameters:
  --api-url <url>               Aigenzey Management API URL (default: https://api.platform.aigenzey.com)
  --instance-name <name>        Runtime instance / pod name (default: aigenzey-k8s-runtime)
  --default-org <org>           Default organization name (default: default)
  --admin-email <email>         Instance admin email (default: instanceadmin@aigenzey.com)
  --admin-password <password>   Instance admin password
  --google-api-key <key>        Google Gemini API Key
  --openai-api-key <key>        OpenAI API Key
  --anthropic-api-key <key>     Anthropic API Key

Component Toggles:
  --with-gateway                Deploy AI Gateway alongside ARE (default: true)
  --no-gateway                  Skip AI Gateway deployment (deploy ARE only)
  --with-nginx                  Deploy Nginx reverse proxy on port 443 (default: true)
  --no-nginx                    Skip Nginx deployment
  --nginx-host <host>           Hostname for Nginx server_name (default: '_' for any host)
  --tls-cert <file>             Custom TLS certificate file for Nginx (PEM format)
  --tls-key <file>              Custom TLS private key file for Nginx (PEM format)
  --with-ingress                Deploy Ingress resource (default: false)
  --ingress-host <host>         Hostname for Ingress (default: runtime.example.com)

Execution Options:
  --dry-run                     Generate and display manifests without applying
  --timeout <seconds>           Timeout for pod readiness wait (default: 300s)
  -h, --help                    Show this help message

Examples:
  # Basic install using customer key file
  ./install.sh --key-file aigenzey-image-access.txt

  # Custom namespace and config file
  ./install.sh -n prod-runtime --config config.env --key-file aigenzey-image-access.txt

  # Dry run to preview generated resources
  ./install.sh --dry-run
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --key-file)
            KEY_FILE="$2"
            shift 2
            ;;
        --json-key)
            JSON_KEY="$2"
            shift 2
            ;;
        --gcloud-token)
            USE_GCLOUD_TOKEN=true
            shift 1
            ;;
        --secret-name)
            SECRET_NAME="$2"
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
        --default-org)
            DEFAULT_ORG="$2"
            shift 2
            ;;
        --admin-email)
            INSTANCEADMIN_EMAIL="$2"
            shift 2
            ;;
        --admin-password)
            INSTANCEADMIN_PASSWORD="$2"
            shift 2
            ;;
        --google-api-key)
            GOOGLE_API_KEY="$2"
            shift 2
            ;;
        --openai-api-key)
            OPENAI_API_KEY="$2"
            shift 2
            ;;
        --anthropic-api-key)
            ANTHROPIC_API_KEY="$2"
            shift 2
            ;;
        --with-gateway)
            ENABLE_AI_GATEWAY=true
            shift 1
            ;;
        --no-gateway)
            ENABLE_AI_GATEWAY=false
            shift 1
            ;;
        --with-nginx)
            ENABLE_NGINX=true
            shift 1
            ;;
        --no-nginx)
            ENABLE_NGINX=false
            shift 1
            ;;
        --nginx-host)
            NGINX_HOST="$2"
            shift 2
            ;;
        --tls-cert)
            TLS_CERT_FILE="$2"
            shift 2
            ;;
        --tls-key)
            TLS_KEY_FILE="$2"
            shift 2
            ;;
        --with-ingress)
            ENABLE_INGRESS=true
            shift 1
            ;;
        --ingress-host)
            INGRESS_HOST="$2"
            ENABLE_INGRESS=true
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift 1
            ;;
        --timeout)
            WAIT_TIMEOUT="$2"
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

# Load environment configuration file if specified
if [[ -n "${CONFIG_FILE}" ]]; then
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        exit 1
    fi
    log_info "Sourcing configuration from ${CONFIG_FILE}..."
    # shellcheck disable=SC1090
    set -a
    source "${CONFIG_FILE}"
    set +a
fi

echo "=========================================================="
echo "      Aigenzey Runtime - Kubernetes Installer             "
echo "=========================================================="
log_info "Target Namespace: ${NAMESPACE}"
log_info "Central API URL:  ${AIGENZEY_API_URL}"
log_info "AI Gateway:       ${ENABLE_AI_GATEWAY}"
log_info "Ingress Enabled:  ${ENABLE_INGRESS}"

# Check prerequisites
if ! command -v kubectl &>/dev/null; then
    log_error "kubectl is not installed or not in PATH."
    exit 1
fi

if [[ "${DRY_RUN}" == false ]]; then
    log_info "Verifying cluster connectivity..."
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Verify your kubeconfig context."
        exit 1
    fi
    log_success "Kubernetes cluster connection verified."
fi

# Step 1: Ensure namespace exists
if [[ "${DRY_RUN}" == false ]]; then
    if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_info "Creating namespace '${NAMESPACE}'..."
        kubectl create namespace "${NAMESPACE}"
    else
        log_info "Namespace '${NAMESPACE}' exists."
    fi
fi

# Step 2: Configure Image Pull Secret
if [[ -n "${KEY_FILE}" || -n "${JSON_KEY}" || "${USE_GCLOUD_TOKEN}" == true ]]; then
    log_info "Configuring image registry credentials..."
    SETUP_ARGS=("-n" "${NAMESPACE}" "--secret-name" "${SECRET_NAME}")
    if [[ -n "${KEY_FILE}" ]]; then
        SETUP_ARGS+=("--key-file" "${KEY_FILE}")
    elif [[ -n "${JSON_KEY}" ]]; then
        SETUP_ARGS+=("--json-key" "${JSON_KEY}")
    elif [[ "${USE_GCLOUD_TOKEN}" == true ]]; then
        SETUP_ARGS+=("--gcloud-token")
    fi

    if [[ "${DRY_RUN}" == false ]]; then
        bash "${SCRIPT_DIR}/setup-credentials.sh" "${SETUP_ARGS[@]}"
    else
        log_info "[DRY-RUN] Would run: setup-credentials.sh ${SETUP_ARGS[*]}"
    fi
else
    log_info "No registry credentials provided. Expecting secret '${SECRET_NAME}' to exist or images to be public."
fi

# Step 3: Deploy Redis Cache
log_info "Applying Redis deployment and service..."
if [[ "${DRY_RUN}" == false ]]; then
    kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/redis/redis-deployment.yaml"
    kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/redis/redis-service.yaml"
else
    cat "${MANIFESTS_DIR}/redis/redis-deployment.yaml"
    cat "${MANIFESTS_DIR}/redis/redis-service.yaml"
fi

# Step 4: Deploy crawl4ai Scraper
log_info "Applying crawl4ai deployment and service..."
if [[ "${DRY_RUN}" == false ]]; then
    kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/crawl4ai/crawl4ai-deployment.yaml"
    kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/crawl4ai/crawl4ai-service.yaml"
else
    cat "${MANIFESTS_DIR}/crawl4ai/crawl4ai-deployment.yaml"
    cat "${MANIFESTS_DIR}/crawl4ai/crawl4ai-service.yaml"
fi

# Step 5: Configure and Deploy ARE
log_info "Preparing ARE ConfigMap and Secret..."
ARE_CONFIG_YAML=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: are-config
  namespace: ${NAMESPACE}
  labels:
    app: are
    app.kubernetes.io/part-of: aigenzey-runtime
data:
  PORT: "8000"
  HOST: "0.0.0.0"
  DEPLOYMENT: "LOCAL"
  API_KEY_CHECK: "false"
  ENABLE_SESSION_LOGGING: "true"
  GOOGLE_GENAI_USE_VERTEXAI: "false"
  DEPLOYMENT_SYNC: "true"
  AIGENZEY_API_URL: "${AIGENZEY_API_URL}"
  INSTANCE_NAME: "${INSTANCE_NAME}"
  POD_NAME: "${INSTANCE_NAME}"
  POD_REGION: "${POD_REGION}"
  SYNC_INTERVAL_SECONDS: "60"
  CLIENT_ID: "${DEFAULT_ORG}"
  LOAD_AGENTS_ON_START: "false"
  SESSION_SERVICE_TYPE: "${SESSION_SERVICE_TYPE:-redis}"
  REDIS_URL: "${REDIS_URL:-redis://redis-service:6379/0}"
  REDIS_HOST: "redis-service"
  REDIS_PORT: "6379"
  CRAWL4AI_BASE_URL: "http://crawl4ai-service:11235"
EOF
)

ARE_SECRET_YAML=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: are-secret
  namespace: ${NAMESPACE}
  labels:
    app: are
    app.kubernetes.io/part-of: aigenzey-runtime
type: Opaque
stringData:
  GOOGLE_API_KEY: "${GOOGLE_API_KEY}"
  OPENAI_API_KEY: "${OPENAI_API_KEY}"
  ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
  SECRET_KEY: "${SECRET_KEY:-AGZsecretKeySecure123456789}"
  INSTANCEADMIN_EMAIL: "${INSTANCEADMIN_EMAIL}"
  INSTANCEADMIN_PASSWORD: "${INSTANCEADMIN_PASSWORD}"
  PODADMIN_EMAIL: "${INSTANCEADMIN_EMAIL}"
  PODADMIN_PASSWORD: "${INSTANCEADMIN_PASSWORD}"
  PODADMIN_TOKEN_TTL: "900"
EOF
)

if [[ "${DRY_RUN}" == false ]]; then
    echo "${ARE_CONFIG_YAML}" | kubectl apply -f -
    echo "${ARE_SECRET_YAML}" | kubectl apply -f -
    kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/are/are-pvc.yaml"
    kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/are/are-deployment.yaml"
    kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/are/are-service.yaml"
else
    echo "${ARE_CONFIG_YAML}"
    echo "${ARE_SECRET_YAML}"
    cat "${MANIFESTS_DIR}/are/are-pvc.yaml"
    cat "${MANIFESTS_DIR}/are/are-deployment.yaml"
    cat "${MANIFESTS_DIR}/are/are-service.yaml"
fi

# Step 6: Deploy AI Gateway (optional)
if [[ "${ENABLE_AI_GATEWAY}" == true ]]; then
    log_info "Preparing AI Gateway resources..."
    GATEWAY_CONFIG_YAML=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-gateway-config
  namespace: ${NAMESPACE}
  labels:
    app: ai-gateway
    app.kubernetes.io/part-of: aigenzey-runtime
data:
  PORT: "8090"
  HOST: "0.0.0.0"
  AIGENZEY_API_URL: "${AIGENZEY_API_URL}"
  ARE_BASE_URL: "http://are-service:8000"
  KMS_BASE_URL: "http://127.0.0.1:8050"
  INSTANCE_NAME: "${INSTANCE_NAME}"
  POD_NAME: "${INSTANCE_NAME}"
  POD_REGION: "${POD_REGION}"
  REDIS_HOST: "redis-service"
  REDIS_PORT: "6379"
  SYNC_INTERVAL_SECONDS: "300"
  SERVICE_TIMEOUT: "1200.0"
  DEFAULT_ORG: "${DEFAULT_ORG}"
EOF
)

    GATEWAY_SECRET_YAML=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ai-gateway-secret
  namespace: ${NAMESPACE}
  labels:
    app: ai-gateway
    app.kubernetes.io/part-of: aigenzey-runtime
type: Opaque
stringData:
  INSTANCEADMIN_EMAIL: "${INSTANCEADMIN_EMAIL}"
  INSTANCEADMIN_PASSWORD: "${INSTANCEADMIN_PASSWORD}"
  PODADMIN_EMAIL: "${INSTANCEADMIN_EMAIL}"
  PODADMIN_PASSWORD: "${INSTANCEADMIN_PASSWORD}"
EOF
)

    if [[ "${DRY_RUN}" == false ]]; then
        echo "${GATEWAY_CONFIG_YAML}" | kubectl apply -f -
        echo "${GATEWAY_SECRET_YAML}" | kubectl apply -f -
        kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/ai-gateway/ai-gateway-deployment.yaml"
        kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/ai-gateway/ai-gateway-service.yaml"
    else
        echo "${GATEWAY_CONFIG_YAML}"
        echo "${GATEWAY_SECRET_YAML}"
        cat "${MANIFESTS_DIR}/ai-gateway/ai-gateway-deployment.yaml"
        cat "${MANIFESTS_DIR}/ai-gateway/ai-gateway-service.yaml"
    fi
fi

# Step 7: Deploy Nginx Reverse Proxy (Port 443 with TLS -> are-service:8000)
if [[ "${ENABLE_NGINX}" == true ]]; then
    log_info "Configuring Nginx reverse proxy on port 443 (HTTPS)..."

    NGINX_CONFIG_YAML=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: ${NAMESPACE}
  labels:
    app: nginx
    app.kubernetes.io/component: reverse-proxy
    app.kubernetes.io/part-of: aigenzey-runtime
data:
  default.conf: |
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen 443 ssl;
        server_name ${NGINX_HOST};

        ssl_certificate     /etc/nginx/certs/tls.crt;
        ssl_certificate_key /etc/nginx/certs/tls.key;

        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        client_max_body_size 64M;
        proxy_read_timeout 1800s;
        proxy_send_timeout 1800s;
        proxy_connect_timeout 60s;

        location / {
            proxy_pass http://ai-gateway-service:8090;

            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            # Streaming, SSE, and WebSocket support for agent responses
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_buffering off;
            proxy_cache off;
            chunked_transfer_encoding on;
        }
    }

    server {
        listen 80;
        server_name ${NGINX_HOST};
        return 301 https://\$host\$request_uri;
    }
EOF
)

    # Ensure TLS secret exists or create it
    if [[ "${DRY_RUN}" == false ]]; then
        if [[ -n "${TLS_CERT_FILE}" && -n "${TLS_KEY_FILE}" ]]; then
            if [[ ! -f "${TLS_CERT_FILE}" || ! -f "${TLS_KEY_FILE}" ]]; then
                log_error "Specified TLS cert (${TLS_CERT_FILE}) or key (${TLS_KEY_FILE}) not found."
                exit 1
            fi
            log_info "Applying are-nginx-tls secret from provided certificate files..."
            kubectl create secret tls are-nginx-tls \
                --cert="${TLS_CERT_FILE}" \
                --key="${TLS_KEY_FILE}" \
                -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
            log_success "Applied custom are-nginx-tls secret."
        elif ! kubectl get secret are-nginx-tls -n "${NAMESPACE}" &>/dev/null; then
            SAN_NAME="${NGINX_HOST}"
            [[ "${SAN_NAME}" == "_" ]] && SAN_NAME="localhost"
            log_info "Generating self-signed TLS certificate for ${SAN_NAME}..."
            TMP_CERT_DIR="$(mktemp -d)"
            openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
                -keyout "${TMP_CERT_DIR}/tls.key" \
                -out "${TMP_CERT_DIR}/tls.crt" \
                -subj "/CN=${SAN_NAME}" \
                -addext "subjectAltName=DNS:${SAN_NAME},DNS:localhost,IP:127.0.0.1,DNS:ai-gateway-service,DNS:are-service,DNS:nginx-service" &>/dev/null
            kubectl create secret tls are-nginx-tls \
                --cert="${TMP_CERT_DIR}/tls.crt" \
                --key="${TMP_CERT_DIR}/tls.key" \
                -n "${NAMESPACE}"
            rm -rf "${TMP_CERT_DIR}"
            log_success "Created are-nginx-tls secret with self-signed certificate."
        else
            log_info "Secret are-nginx-tls already exists in namespace ${NAMESPACE}."
        fi

        echo "${NGINX_CONFIG_YAML}" | kubectl apply -f -
        kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/nginx/nginx-deployment.yaml"
        kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/nginx/nginx-service.yaml"
    else
        log_info "[DRY-RUN] Would ensure secret are-nginx-tls exists in namespace ${NAMESPACE}."
        echo "${NGINX_CONFIG_YAML}"
        cat "${MANIFESTS_DIR}/nginx/nginx-deployment.yaml"
        cat "${MANIFESTS_DIR}/nginx/nginx-service.yaml"
    fi
fi

# Step 8: Deploy Ingress (optional)
if [[ "${ENABLE_INGRESS}" == true ]]; then
    log_info "Configuring Ingress for host: ${INGRESS_HOST}..."
    INGRESS_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aigenzey-runtime-ingress
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/part-of: aigenzey-runtime
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "1800"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "1800"
spec:
  ingressClassName: nginx
  rules:
  - host: ${INGRESS_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: are-service
            port:
              number: 8000
  tls:
  - hosts:
    - ${INGRESS_HOST}
    secretName: aigenzey-runtime-tls
EOF
)
    if [[ "${DRY_RUN}" == false ]]; then
        echo "${INGRESS_YAML}" | kubectl apply -f -
    else
        echo "${INGRESS_YAML}"
    fi
fi

if [[ "${DRY_RUN}" == true ]]; then
    log_success "Dry run completed. Manifests generated above."
    exit 0
fi

# Step 9: Wait for deployments to be ready
log_info "Waiting for deployments to roll out in namespace '${NAMESPACE}'..."

wait_for_deployment() {
    local DEP="$1"
    log_info "Checking rollout status for deployment/${DEP}..."
    if kubectl rollout status deployment/"${DEP}" -n "${NAMESPACE}" --timeout="${WAIT_TIMEOUT}"; then
        log_success "Deployment ${DEP} is ready."
    else
        log_warn "Deployment ${DEP} rollout did not complete within ${WAIT_TIMEOUT}."
    fi
}

wait_for_deployment redis
wait_for_deployment crawl4ai
wait_for_deployment are-deployment
if [[ "${ENABLE_AI_GATEWAY}" == true ]]; then
    wait_for_deployment ai-gateway-deployment
fi
if [[ "${ENABLE_NGINX}" == true ]]; then
    wait_for_deployment nginx-deployment
fi

echo ""
echo "=========================================================="
echo "    Aigenzey Kubernetes Runtime Deployment Summary        "
echo "=========================================================="
echo "Cluster Namespace: ${NAMESPACE}"
echo ""
echo "Pods Status:"
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "Services:"
kubectl get services -n "${NAMESPACE}"
echo ""
echo "Accessing the Runtime over HTTPS (Port 443):"
if [[ "${ENABLE_NGINX}" == true ]]; then
    echo "  Nginx SSL Reverse Proxy: nginx-service:443 -> ai-gateway-service:8090 (-> are-service:8000)"
    echo "  Forward port to host (Option 1: unprivileged port 8443, no sudo required):"
    echo "    kubectl port-forward -n ${NAMESPACE} svc/nginx-service 8443:443"
    echo "    curl -k https://localhost:8443/docs"
    echo ""
    echo "  Forward port to host (Option 2: standard port 443, requires sudo on macOS/Linux):"
    echo "    sudo kubectl port-forward -n ${NAMESPACE} svc/nginx-service 443:443"
    echo "    curl -k https://localhost/docs"
fi
echo ""
echo "Direct Internal Services (ClusterIP):"
echo "  kubectl port-forward -n ${NAMESPACE} svc/are-service 8000:8000"
if [[ "${ENABLE_AI_GATEWAY}" == true ]]; then
    echo "  kubectl port-forward -n ${NAMESPACE} svc/ai-gateway-service 8090:8090"
fi
echo "=========================================================="
log_success "Aigenzey Runtime successfully deployed to Kubernetes!"
