# Aigenzey Runtime - Kubernetes Installation

This directory contains the production-grade Kubernetes installation scripts and manifests to deploy the **Aigenzey Runtime Engine (ARE)** data plane stack into any standard Kubernetes cluster (GKE, EKS, AKS, or on-premise Kubernetes).

---

## 1. Architecture Overview

When deployed in Kubernetes, the Aigenzey Runtime runs as microservices inside a dedicated namespace (default: `aigenzey-runtime`):

```text
                                  ┌───────────────────────────────┐
                                  │   nginx-service (Port 443)    │  <-- HTTPS / SSL Termination
                                  └───────────────┬───────────────┘
                                                  │ proxy_pass
                                                  ▼
                                     ┌─────────────────────────┐
                                     │   ai-gateway-service    │  <-- Edge Gateway
                                     │       (Port 8090)       │
                                     │  - Token quotas & auth  │
                                     └────────────┬────────────┘
                                                  │ internal proxy
                                                  ▼
                                     ┌─────────────────────────┐
                                     │       are-service       │  <-- Agent Runtime Engine
                                     │       (Port 8000)       │
                                     │  - Agent executions     │
                                     └────────────┬────────────┘
                                                  │
                                  ┌───────────────┴───────────────┐
                                  │                               │
                                  ▼                               ▼
                     ┌─────────────────────────┐     ┌─────────────────────────┐
                     │      redis-service      │     │    crawl4ai-service     │
                     │       (Port 6379)       │     │      (Port 11235)       │
                     │  - Session cache        │     │  - Headless web scraper │
                     └─────────────────────────┘     └─────────────────────────┘
```

- **Nginx (`nginx-service`)**: Reverse proxy listening on port `443` (HTTPS) with TLS termination, forwarding traffic to `ai-gateway-service:8090` with SSE streaming, WebSocket upgrade, and buffering optimizations.
- **AI Gateway (`ai-gateway-service`)**: Edge proxy handling KMS rate limits, token quotas, and proxying downstream to ARE.
- **ARE (`are-service`)**: Core Agent Runtime Engine executing ADK agent workflows and tools.
- **Redis (`redis-service`)**: High performance session memory and state caching.
- **crawl4ai (`crawl4ai-service`)**: Containerized Chromium web scraping service enabling search and browser tools.
- **Storage (`are-pvc`)**: Persistent storage volume for persistent organization files, workspaces, and logs.

---

## 2. Required Setup Inputs

Before installing, make sure you have the following information and credentials:

| Input Parameter | Variable in `config.env` | CLI Flag | Required? | Description & Instructions |
| :--- | :--- | :--- | :--- | :--- |
| **GCR / Registry Key** | `KEY_FILE` or `JSON_KEY` | `--key-file <file>` or `--json-key <file>` | **Yes** | Authentication credentials for Google Artifact Registry. Specify either:<br>• **Base64 key**: `--key-file aigenzey-image-access.txt`<br>• **Service Account JSON key**: `--json-key my-sa-key.json` |
| **Organization Name** | `DEFAULT_ORG` | `--default-org <name>` | **Yes** | Your organization identifier in Aigenzey. Isolates agent workflows, tools, and executions. |
| **Instance Name** | `INSTANCE_NAME` | `--instance-name <name>` | **Yes** | Unique identifier for this Kubernetes runtime node/cluster (e.g. `aigenzey-k8s-prod-1`). |
| **Deployment Secret Key** | `SECRET_KEY` | `--secret-key <key>` | **Yes** | Secret key for agent deployment authentication. Must match the secret key used by the Aigenzey Control Plane / UI (default: `AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do`). |
| **Instance Admin Email** | `INSTANCEADMIN_EMAIL` | `--admin-email <email>` | **Yes** | Administrator email registered in your Aigenzey platform. |
| **Instance Admin Password** | `INSTANCEADMIN_PASSWORD` | `--admin-password <pw>` | **Yes** | Password for the instance admin account to authenticate synchronization with the central API. |
| **Gemini API Key** | `GOOGLE_API_KEY` | `--google-api-key <key>` | **Yes** (if not using Vertex AI) | Google Gemini API key used by the Agent Runtime Engine (ADK agents). Obtain from [Google AI Studio](https://aistudio.google.com). |
| **Vertex AI Enabled** | `GOOGLE_GENAI_USE_VERTEXAI` | `--vertex-ai` | Optional | Set to `true` to use Google Cloud Vertex AI instead of Google AI Studio API key (default: `false`). |
| **GCP Project ID** | `GOOGLE_CLOUD_PROJECT` | `--gcp-project <id>` | Optional (for Vertex AI) | Google Cloud Project ID hosting Vertex AI models (e.g. `aigenzey-cyberhoot`). |
| **GCP Location/Region** | `GOOGLE_CLOUD_LOCATION` | `--gcp-location <loc>` | Optional (for Vertex AI) | Google Cloud region for Vertex AI endpoints (default: `global` or `us-central1`). |
| **GCP Credentials / ADC** | `GCP_KEY_FILE` / `GOOGLE_APPLICATION_CREDENTIALS` | `--gcp-key-file <file>` | Optional (for Vertex AI) | GCP Service Account JSON key mounted into ARE to provide Application Default Credentials (`GOOGLE_APPLICATION_CREDENTIALS=/etc/gcp/key.json`). Auto-configured if `--json-key` is supplied. |
| **Enable Nginx Proxy** | `ENABLE_NGINX` | `--with-nginx` / `--no-nginx` | Optional | Deploy dedicated Nginx reverse proxy on port 443 (HTTPS) with TLS termination (default: `true`). |
| **Nginx Hostname** | `NGINX_HOST` | `--nginx-host <host>` | Optional | Domain name for Nginx `server_name` directive (default: `_` for catch-all). |
| **TLS Certificate File** | `TLS_CERT_FILE` | `--tls-cert <file>` | Optional | Path to custom SSL/TLS certificate in PEM format. If omitted, self-signed certificate is auto-generated. |
| **TLS Private Key File** | `TLS_KEY_FILE` | `--tls-key <file>` | Optional | Path to custom SSL/TLS private key in PEM format. |
| **Central API URL** | `AIGENZEY_API_URL` | `--api-url <url>` | Optional | URL of the central Aigenzey Management API (default: `https://api.platform.aigenzey.com`). |
| **Namespace** | `NAMESPACE` | `-n, --namespace <ns>` | Optional | Target Kubernetes namespace (default: `aigenzey-runtime`). |
| **Other LLM Keys** | `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | `--openai-api-key`, `--anthropic-api-key` | Optional | API keys if your agent workflows utilize OpenAI or Anthropic models. |

---

## 3. Configuring the Setup

### Approach A: Using `config.env` (Recommended)

1. Copy the sample environment file:
   ```bash
   cp config.env.example config.env
   ```

2. Edit `config.env` with your values:
   ```bash
   # Kubernetes Namespace
   NAMESPACE=aigenzey-runtime

   # Central Management API
   AIGENZEY_API_URL=https://api.platform.aigenzey.com

   # Instance & Organization Information
   INSTANCE_NAME=my-k8s-runtime-1
   DEFAULT_ORG=my-org
   POD_REGION=us-central1

   # Instance Admin Credentials (for synchronizing with central API)
   INSTANCEADMIN_EMAIL=admin@mycompany.com
   INSTANCEADMIN_PASSWORD=MySecurePassword123

   # LLM Provider API Keys & Vertex AI Settings
   GOOGLE_API_KEY=AIzaSyD...       # Leave blank if using Vertex AI
   GOOGLE_GENAI_USE_VERTEXAI=true   # Set true for Vertex AI
   GOOGLE_CLOUD_PROJECT=aigenzey-cyberhoot
   GOOGLE_CLOUD_LOCATION=global
   GCP_KEY_FILE=/path/to/my-sa-key.json # Auto-mounts as /etc/gcp/key.json for ADC

   OPENAI_API_KEY=sk-...
   ANTHROPIC_API_KEY=

   # Deployment & Session Secret Key (Must match Aigenzey UI/Platform)
   SECRET_KEY=AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do

   # Crawl4AI Internal Scraper Bearer Token
   CRAWL4AI_API_TOKEN=aigenzey-crawl4ai-internal-token

   # Nginx Reverse Proxy & TLS Configuration
   ENABLE_NGINX=true
   NGINX_HOST="_"           # Custom domain (e.g. api.yourcompany.com) or "_" for catch-all
   TLS_CERT_FILE=          # Path to fullchain.pem (leave blank for auto self-signed)
   TLS_KEY_FILE=           # Path to privkey.pem (leave blank for auto self-signed)
   ```

3. Deploy using `config.env`:

   **Using a Base64 key file (`aigenzey-image-access.txt`):**
   ```bash
   ./install.sh --config config.env --key-file aigenzey-image-access.txt
   ```

   **Using a Google Cloud Service Account JSON key file (`my-sa-key.json`):**
   ```bash
   ./install.sh --config config.env --json-key /path/to/my-sa-key.json
   ```

---

### Approach B: Passing Flags to `install.sh`

**Using Base64 key (`--key-file`):**
```bash
./install.sh \
  -n aigenzey-runtime \
  --key-file aigenzey-image-access.txt \
  --default-org my-org \
  --instance-name my-k8s-cluster \
  --admin-email admin@mycompany.com \
  --admin-password MySecurePassword123 \
  --secret-key AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do \
  --google-api-key "AIzaSyD..." \
  --api-url https://api.platform.aigenzey.com \
  --with-nginx \
  --nginx-host "_"
```

**Using GCP Service Account JSON key (`--json-key`) with Vertex AI:**
```bash
./install.sh \
  -n aigenzey-runtime \
  --json-key /path/to/my-sa-key.json \
  --default-org my-org \
  --instance-name my-k8s-cluster \
  --admin-email admin@mycompany.com \
  --admin-password MySecurePassword123 \
  --secret-key AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do \
  --vertex-ai \
  --gcp-project aigenzey-cyberhoot \
  --gcp-location global \
  --api-url https://api.platform.aigenzey.com \
  --with-nginx \
  --nginx-host "_"
```

---

## 4. Image Pull Credentials Setup

The runtime images reside in Google Artifact Registry (`us-central1-docker.pkg.dev/aigenzey-dev/aigenzey-images/`). You can authenticate using any of the following methods:

### Option 1: Base64 Service Account Key (`aigenzey-image-access.txt`)
If you received the `aigenzey-image-access.txt` key file from Aigenzey:
```bash
# Standalone secret creation:
./setup-credentials.sh --key-file aigenzey-image-access.txt -n aigenzey-runtime

# Or directly during installation:
./install.sh --key-file aigenzey-image-access.txt --config config.env
```

### Option 2: GCP Service Account JSON Key (`--json-key`)
If you have a Google Cloud service account JSON key file (`my-sa-key.json`) with Artifact Registry reader permissions (`roles/artifactregistry.reader`):
```bash
# Standalone secret creation:
./setup-credentials.sh --json-key my-sa-key.json -n aigenzey-runtime

# Or directly during installation with config.env:
./install.sh --config config.env --json-key my-sa-key.json

# Or directly during installation with CLI flags:
./install.sh \
  -n aigenzey-runtime \
  --json-key my-sa-key.json \
  --default-org my-org \
  --instance-name my-k8s-cluster \
  --admin-email admin@mycompany.com \
  --admin-password MySecurePassword123 \
  --secret-key AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do \
  --google-api-key "AIzaSyD..."
```

### Option 3: Active `gcloud` Token
For short-lived development or testing using your active `gcloud auth print-access-token`:
```bash
# Standalone secret creation:
./setup-credentials.sh --gcloud-token -n aigenzey-runtime

# Or directly during installation:
./install.sh --gcloud-token --config config.env
```

---

## 5. Deployment Options

### Preview Manifests (Dry Run)
Inspect the generated Kubernetes manifests without applying them:
```bash
./install.sh --config config.env --dry-run
```

### Expose External Traffic with Ingress
To configure TLS Ingress:
```bash
./install.sh \
  --config config.env \
  --key-file aigenzey-image-access.txt \
  --with-ingress \
  --ingress-host runtime.mycompany.com
```

### Deploy via Native Kustomize / GitOps
If your team uses GitOps (ArgoCD, Flux) or Kustomize directly:
1. Create the namespace and registry secret:
   ```bash
   kubectl apply -f manifests/namespace.yaml
   ./setup-credentials.sh --key-file aigenzey-image-access.txt -n aigenzey-runtime
   ```
2. Apply manifests with Kustomize:
   ```bash
   kubectl apply -k manifests/
   ```

---

## 6. Nginx Reverse Proxy & TLS Configuration

### Overview & Architecture
In the Kubernetes runtime stack, Nginx runs as a dedicated application deployment (`nginx-deployment`) fronted by a Kubernetes service (`nginx-service`). It is **not** an Ingress Controller or Gateway API Controller; instead, it is a lightweight, self-contained reverse proxy that terminates TLS on port 443 (HTTPS) and forwards traffic downstream to `ai-gateway-service:8090`.

Key architectural capabilities configured in Nginx:
- **TLS Termination**: Listens on port `443` with TLS 1.2 and 1.3 encryption.
- **HTTP/1.1 Streaming & SSE**: Disables proxy buffering (`proxy_buffering off; chunked_transfer_encoding on;`) to ensure token-by-token agent streaming responses work without latency or buffering.
- **WebSocket Upgrade**: Passes `Upgrade` and `Connection` headers for real-time bi-directional agent communications.
- **Generous Timeouts**: Configured with `proxy_read_timeout 1800s;` and `proxy_send_timeout 1800s;` to prevent premature gateway timeouts during complex, multi-step agent executions.
- **Large Payload Capacity**: `client_max_body_size 64M;` to support agent definition and artifact uploads.

### Configuration Settings

| Parameter | `config.env` Variable | CLI Flag | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Enable Proxy** | `ENABLE_NGINX` | `--with-nginx` / `--no-nginx` | `true` | When `true`, deploys Nginx Deployment, Service, ConfigMap, and TLS Secret. Set to `false` if using an external cloud Ingress controller. |
| **Server Name / Hostname** | `NGINX_HOST` | `--nginx-host <host>` | `_` | The domain name used in Nginx `server_name`. `_` acts as a wildcard catch-all matching any host header or IP address. |
| **TLS Certificate** | `TLS_CERT_FILE` | `--tls-cert <file>` | *(None)* | Path to an existing PEM certificate file (`fullchain.pem` or `tls.crt`). If omitted, a self-signed certificate is auto-generated. |
| **TLS Private Key** | `TLS_KEY_FILE` | `--tls-key <file>` | *(None)* | Path to the matching PEM private key (`privkey.pem` or `tls.key`). |

### Domain & Hostname Setup

- **Catch-All (Default)**: Leaving `NGINX_HOST="_"` allows Nginx to accept requests directed to any IP or hostname (ideal for local testing, Docker Desktop, or IP-based load balancers).
- **Custom FQDN**: To bind to a specific domain (e.g. `api.yourcompany.com`):
  ```bash
  # In config.env:
  NGINX_HOST=api.yourcompany.com

  # Or via CLI:
  ./install.sh k8s --nginx-host api.yourcompany.com ...
  ```

### SSL/TLS Certificate Scenarios

#### Scenario 1: Automatic Self-Signed Certificate (Default)
If `TLS_CERT_FILE` and `TLS_KEY_FILE` are omitted, `install.sh` automatically generates a 4096-bit RSA certificate with `Subject Alternative Name (SAN)` matching your `NGINX_HOST` and mounts it into the `are-nginx-tls` Kubernetes secret.

#### Scenario 2: Providing Custom Certificates at Install Time
To use certificates issued by your enterprise CA or Let's Encrypt:
```bash
./install.sh k8s \
  --config config.env \
  --key-file aigenzey-image-access.txt \
  --nginx-host api.yourcompany.com \
  --tls-cert /path/to/fullchain.pem \
  --tls-key /path/to/privkey.pem
```

#### Scenario 3: Updating Certificates on an Already-Running Cluster (Zero Reinstall)
To replace or renew certificates without re-running the full installer:
```bash
# Update the TLS secret
kubectl create secret tls are-nginx-tls \
  --cert=/path/to/new-fullchain.pem \
  --key=/path/to/new-privkey.pem \
  -n aigenzey-runtime \
  --dry-run=client -o yaml | kubectl apply -f -

# Reload Nginx
kubectl rollout restart deployment/nginx-deployment -n aigenzey-runtime
```

#### Scenario 4: Disabling Nginx (Using Cloud Ingress / Gateway API Instead)
If your Kubernetes cluster already runs an ingress controller (e.g., AWS ALB Controller, GCP Ingress, Traefik, or Istio) and you prefer routing directly to `ai-gateway-service:8090`:
```bash
# In config.env:
ENABLE_NGINX=false
ENABLE_INGRESS=true
INGRESS_HOST=agents.mycompany.com

# Or via CLI:
./install.sh k8s --no-nginx --with-ingress --ingress-host agents.mycompany.com ...
```

---

## 7. Verification & Health Checking

### 1. Check Pod Status
```bash
kubectl get pods -n aigenzey-runtime
```
Expected output:
```text
NAME                                     READY   STATUS    RESTARTS   AGE
nginx-deployment-xxxx-yyyy               1/1     Running   0          1m
are-deployment-xxxx-yyyy                 1/1     Running   0          1m
ai-gateway-deployment-xxxx-yyyy          1/1     Running   0          1m
crawl4ai-xxxx-yyyy                       1/1     Running   0          1m
redis-xxxx-yyyy                          1/1     Running   0          1m
```

### 2. Verify Nginx HTTPS on Port 443
If using Docker Desktop, Minikube (with `minikube tunnel`), or a cloud LoadBalancer, `nginx-service` is accessible directly on host port `443`.

When using `kubectl port-forward`:
- **Option 1 (Recommended - No `sudo` needed)**: Forward to an unprivileged local port like `8443`:
  ```bash
  kubectl port-forward -n aigenzey-runtime svc/nginx-service 8443:443
  ```
  Then test:
  ```bash
  # AI Gateway Swagger Docs through Nginx
  curl -k https://localhost:8443/docs
  ```

- **Option 2 (Privileged port 443)**: On macOS and Linux, ports below 1024 require root/administrator privileges:
  ```bash
  sudo kubectl port-forward -n aigenzey-runtime svc/nginx-service 443:443
  ```
  Then test:
  ```bash
  curl -k https://localhost/docs
  ```

### 3. Trust Self-Signed TLS Certificate for Local UI / Browser Testing

When calling the runtime from the Aigenzey Web UI, browsers (Chrome, Edge, Safari) block requests to self-signed HTTPS endpoints with `net::ERR_CERT_AUTHORITY_INVALID`.

To trust the certificate locally on your Mac:

1. Export the TLS certificate from the Kubernetes secret:
   ```bash
   kubectl get secret are-nginx-tls -n aigenzey-runtime -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/aigenzey-k8s.crt
   ```

2. (Optional) Inspect the certificate:
   ```bash
   vi /tmp/aigenzey-k8s.crt
   ```

3. Add the certificate to the macOS System Keychain as a trusted root:
   ```bash
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/aigenzey-k8s.crt
   ```

4. Restart your browser or visit `https://localhost:8443/docs` to verify that the certificate is trusted.

> **Quick Browser Bypass**: Alternatively, open a new tab in the same browser, visit `https://localhost:8443/docs`, click **Advanced** -> **Proceed to localhost (unsafe)** (or type `thisisunsafe` in Chrome). Once accepted, subsequent UI calls will succeed.

### 4. Test Agent Execution over HTTPS
```bash
curl -k -X POST \
  "https://localhost:8443/api/agents/execute?client_id=my-kube-test&agent_name=poem&apikey=my-kube-test-test-key-WO78KD59H06HO8WMNW" \
  -H "Content-Type: application/json" \
  -d '{"topic": "The Ocean"}'
```

---

## 8. Teardown and Cleanup

To remove the runtime deployment and services:
```bash
./uninstall.sh -n aigenzey-runtime
```

To delete the entire namespace and all associated resources:
```bash
./uninstall.sh -n aigenzey-runtime --delete-namespace
```
