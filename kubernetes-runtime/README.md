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
| **GCR / Registry Key** | N/A | `--key-file <file>` | **Yes** | Base64 Artifact Registry pull key file (e.g. `aigenzey-image-access.txt`) provided by Aigenzey to authenticate image downloads. |
| **Organization Name** | `DEFAULT_ORG` | `--default-org <name>` | **Yes** | Your organization identifier in Aigenzey. Isolates agent workflows, tools, and executions. |
| **Instance Name** | `INSTANCE_NAME` | `--instance-name <name>` | **Yes** | Unique identifier for this Kubernetes runtime node/cluster (e.g. `aigenzey-k8s-prod-1`). |
| **Instance Admin Email** | `INSTANCEADMIN_EMAIL` | `--admin-email <email>` | **Yes** | Administrator email registered in your Aigenzey platform. |
| **Instance Admin Password** | `INSTANCEADMIN_PASSWORD` | `--admin-password <pw>` | **Yes** | Password for the instance admin account to authenticate synchronization with the central API. |
| **Gemini API Key** | `GOOGLE_API_KEY` | `--google-api-key <key>` | **Yes** (for agents) | Google Gemini API key used by the Agent Runtime Engine (ADK agents). Obtain from [Google AI Studio](https://aistudio.google.com). |
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

   # LLM Provider API Keys
   GOOGLE_API_KEY=AIzaSyD...
   OPENAI_API_KEY=sk-...
   ANTHROPIC_API_KEY=

   # Deployment & Session Secret Key (Must match Aigenzey UI/Platform)
   SECRET_KEY=AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do
   ```

3. Deploy using `config.env` and your Artifact Registry key file:
   ```bash
   ./install.sh --config config.env --key-file aigenzey-image-access.txt
   ```

---

### Approach B: Passing Flags to `install.sh`

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
  --api-url https://api.platform.aigenzey.com
```

---

## 4. Image Pull Credentials Setup

The runtime images reside in Google Artifact Registry (`us-central1-docker.pkg.dev/aigenzey-dev/aigenzey-images/`). You can authenticate using any of the following methods:

### Option 1: Base64 Service Account Key (`aigenzey-image-access.txt`)
If you received the `aigenzey-image-access.txt` key file from Aigenzey:
```bash
./setup-credentials.sh --key-file aigenzey-image-access.txt -n aigenzey-runtime
```
*Note: `install.sh --key-file aigenzey-image-access.txt` performs this automatically.*

### Option 2: GCP Service Account JSON Key
If you have a Google Cloud service account JSON key file with `roles/artifactregistry.reader`:
```bash
./setup-credentials.sh --json-key my-sa-key.json -n aigenzey-runtime
```

### Option 3: Active `gcloud` Token
For short-lived development or testing:
```bash
./setup-credentials.sh --gcloud-token -n aigenzey-runtime
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

## 6. Verification & Health Checking

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

## 7. Teardown and Cleanup

To remove the runtime deployment and services:
```bash
./uninstall.sh -n aigenzey-runtime
```

To delete the entire namespace and all associated resources:
```bash
./uninstall.sh -n aigenzey-runtime --delete-namespace
```
