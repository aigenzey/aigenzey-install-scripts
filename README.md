# Aigenzey Install Scripts

Public installation scripts and Kubernetes manifests to deploy the **Aigenzey Runtime Engine** on Bring-Your-Own (BYO) hardware and private cloud infrastructure.

---

## 1. Required Configuration Inputs

Whether installing on a Virtual Machine or deploying to a Kubernetes cluster, the installer needs specific parameters to connect your runtime node to your Aigenzey organization, authenticate image downloads, and enable LLM reasoning for agents.

| Input Parameter | Config Variable | CLI Flag / Argument | Required? | Description | Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Organization Name** | `DEFAULT_ORG` | `--default-org <name>` | **Yes** | Organization identifier in Aigenzey. Isolates agent workflows, tools, and execution permissions. | `acme-corp`, `default` |
| **Instance Name** | `INSTANCE_NAME` | `--instance-name <name>` | **Yes** | Unique hostname or identifier for this runtime node/pod cluster. | `byo-runtime-01`, `k8s-us-east-1` |
| **Deployment Secret Key** | `SECRET_KEY` | `--secret-key <key>` | **Yes** | Secret key for agent deployment authentication. Must match the secret key used by the Aigenzey Control Plane / UI. | `AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do` |
| **Registry / GCR Key** | `KEY_FILE` or `JSON_KEY` | `--key-file <file>` or `--json-key <file>` | **Yes** (for K8s & private pulls) | Access credentials for Google Artifact Registry. Specify either Base64 key (`aigenzey-image-access.txt`) or GCP service account JSON key (`my-sa-key.json`). | `aigenzey-image-access.txt`, `my-sa-key.json` |
| **Gemini API Key** | `GOOGLE_API_KEY` | `--google-api-key <key>` | **Yes** (for agents) | Google Gemini API key used by the Agent Runtime Engine (ADK agents). Obtain from [Google AI Studio](https://aistudio.google.com). | `AIzaSyD...` |
| **Instance Admin Email** | `INSTANCEADMIN_EMAIL` | `--instanceadmin-email <email>` | **Yes** | Admin email registered in your Aigenzey platform. Used by runtime to authenticate and sync agent workflows. | `instanceadmin@aigenzey.com` |
| **Instance Admin Password** | `INSTANCEADMIN_PASSWORD` | `--instanceadmin-password <pass>` | **Yes** | Password for the Instance Admin account to authorize synchronization with the central API. | `YourSecretPassword123` |
| **Enable Nginx Proxy** | `ENABLE_NGINX` | `--with-nginx` / `--no-nginx` | Optional | Deploy dedicated Nginx reverse proxy on port 443 with TLS termination (Kubernetes runtime, default: `true`). | `true` |
| **Nginx Hostname** | `NGINX_HOST` | `--nginx-host <host>` | Optional | Custom domain name for Nginx `server_name` (default: `_` for catch-all wildcard). | `agents.company.com` |
| **TLS Cert & Key** | `TLS_CERT_FILE`, `TLS_KEY_FILE` | `--tls-cert`, `--tls-key` | Optional | Custom SSL/TLS certificate and private key paths in PEM format (auto self-signs if omitted). | `/path/to/cert.pem` |
| **Central API URL** | `AIGENZEY_API_URL` | `--api-url <url>` | Optional | URL of the central Aigenzey Management API (Control Plane). Defaults to SaaS endpoint. | `https://api.platform.aigenzey.com` |
| **Other LLM Keys** | `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | `--openai-api-key`, `--anthropic-api-key` | Optional | API keys for OpenAI or Claude if your agent definitions use multi-provider LLMs. | `sk-...` |

---

## 2. Configuration Setup Methods

You can supply these inputs using either a **Configuration File** (recommended for production and version control) or **Command-Line Flags**.

### Method A: Using a Configuration File (Recommended)

#### For VM Runtime (`config.properties`):
1. Copy the sample template:
   ```bash
   cp vm-runtime/config.properties.example config.properties
   ```
2. Edit `config.properties`:
   ```properties
   AIGENZEY_API_URL=https://api.platform.aigenzey.com
   INSTANCE_NAME=my-vm-runtime
   DEFAULT_ORG=my-org
   INSTANCEADMIN_EMAIL=admin@mycompany.com
   INSTANCEADMIN_PASSWORD=MySecurePassword123
   GOOGLE_API_KEY=AIzaSyD...
   SECRET_KEY=AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do
   ```
3. Run installer with the config file:
   ```bash
   sudo ./install.sh vm --config ./config.properties --version 1.0.0
   ```

#### For Kubernetes Runtime (`config.env`):
1. Copy the sample template:
   ```bash
   cp kubernetes-runtime/config.env.example config.env
   ```
2. Edit `config.env`:
   ```bash
   NAMESPACE=aigenzey-runtime
   AIGENZEY_API_URL=https://api.platform.aigenzey.com
   INSTANCE_NAME=my-k8s-runtime
   DEFAULT_ORG=my-org
   INSTANCEADMIN_EMAIL=admin@mycompany.com
   INSTANCEADMIN_PASSWORD=MySecurePassword123
   GOOGLE_API_KEY=AIzaSyD...
   SECRET_KEY=AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do

   # Nginx Reverse Proxy Settings
   ENABLE_NGINX=true
   NGINX_HOST="_"
   TLS_CERT_FILE=
   TLS_KEY_FILE=
   ```
3. Run installer with the config file and your registry key:
   ```bash
   # Using Base64 key file:
   ./install.sh k8s --config ./config.env --key-file aigenzey-image-access.txt

   # Using GCP Service Account JSON key:
   ./install.sh k8s --config ./config.env --json-key /path/to/my-sa-key.json
   ```

---

### Method B: Using Command-Line Flags

Pass parameters directly on the command line:

```bash
# VM Installation:
sudo ./install.sh vm \
  --version 1.0.0 \
  --default-org my-org \
  --instance-name my-vm-node-1 \
  --instanceadmin-email admin@mycompany.com \
  --instanceadmin-password MySecret123

# Kubernetes Installation (with Base64 key):
./install.sh k8s \
  --key-file aigenzey-image-access.txt \
  --default-org my-org \
  --instance-name my-k8s-node-1 \
  --admin-email admin@mycompany.com \
  --admin-password MySecret123 \
  --secret-key AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do \
  --google-api-key "AIzaSyD..." \
  --with-nginx \
  --nginx-host "_"

# Kubernetes Installation (with GCP Service Account JSON key):
./install.sh k8s \
  --json-key /path/to/my-sa-key.json \
  --default-org my-org \
  --instance-name my-k8s-node-1 \
  --admin-email admin@mycompany.com \
  --admin-password MySecret123 \
  --secret-key AGZalfjei0eowfpiBv4iu3h0f7j0hfcna8do \
  --google-api-key "AIzaSyD..." \
  --with-nginx \
  --nginx-host "_"
```

---

## 3. Architecture Overview

Aigenzey cleanly separates the SaaS **Control Plane** (Management API, PostgreSQL, Platform UI) from the private **Data Plane / Runtime Engine**:

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        Central Control Plane                           │
│     (Platform UI, Management API, PostgreSQL, Workflow Design)         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Configuration & Sync
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     BYO Hardware Runtime Stack                         │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                 nginx Reverse Proxy (Port 443)                 │   │
│   │   - TLS termination (HTTPS), SSE streaming, WebSocket upgrade  │   │
│   └───────────────────────────────┬────────────────────────────────┘   │
│                                   │ proxy_pass                         │
│   ┌───────────────────────────────▼────────────────────────────────┐   │
│   │                     ai-gateway (Port 8090)                     │   │
│   │   - Quota enforcement, KMS token validation, edge routing      │   │
│   └───────────────────────────────┬────────────────────────────────┘   │
│                                   │ proxy                              │
│   ┌───────────────────────────────▼────────────────────────────────┐   │
│   │                  ARE - Agent Runtime Engine                    │   │
│   │                         (Port 8000)                            │   │
│   │   - ADK agent execution, streaming, tool integrations          │   │
│   └───────────────┬────────────────────────────────┬───────────────┘   │
│                   │ session state                  │ scraping          │
│   ┌───────────────▼────────────────┐   ┌───────────▼───────────────┐   │
│   │       Redis (Port 6379)        │   │    crawl4ai (Port 11235)  │   │
│   └────────────────────────────────┘   └───────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

The runtime stack consists of:
- **Nginx Reverse Proxy**: Reverse proxy terminating HTTPS on port `443` with TLS encryption, HTTP/1.1 SSE unbuffered streaming, and WebSocket support.
- **AI Gateway**: Edge proxy managing token accounting, KMS authentication, rate limiting, and request routing (port `8090`).
- **ARE (Agent Runtime Engine)**: FastAPI engine running Google Agent Development Kit (ADK) workflows, tools, and multi-turn sessions (port `8000`).
- **crawl4ai**: Headless browser scraping container providing web research tools to agents (port `11235`).
- **Redis**: In-memory caching and session state management (port `6379`).

---

## 4. Repository Structure

```text
aigenzey-install-scripts/
├── install.sh                     # Unified installer dispatcher
├── README.md                      # This documentation
├── vm-runtime/                    # Virtual Machine runtime installer
│   ├── README.md                  # Detailed VM installation guide
│   ├── bootstrap.sh               # Machine & OS bootstrap (Python 3.13, Redis, Docker, crawl4ai)
│   ├── bootstrap-ubuntu.sh        # Alias symlink to bootstrap.sh
│   ├── install.sh                 # VM installer (invokes bootstrap.sh, configures & starts runtime)
│   ├── uninstall.sh               # VM uninstallation and cleanup script
│   ├── service.sh                 # Service lifecycle helper (start/stop/logs)
│   ├── aigenzey-runtime.service   # Systemd unit file
│   └── config.properties.example  # Configuration template
└── kubernetes-runtime/            # Kubernetes runtime installer & manifests
    ├── README.md                  # Detailed Kubernetes deployment guide
    ├── install.sh                 # Kubernetes automated installer
    ├── uninstall.sh               # Kubernetes teardown script
    ├── setup-credentials.sh       # Image pull secret configuration helper
    ├── config.env.example         # Kubernetes environment configuration
    └── manifests/                 # Kubernetes YAML resources & Kustomization
        ├── namespace.yaml
        ├── kustomization.yaml
        ├── redis/
        ├── crawl4ai/
        ├── are/
        ├── ai-gateway/
        └── ingress/
```

---

## 5. Verification & Health Checking

Once deployed, verify your runtime health:

```bash
# Direct HTTP check (or via kubectl port-forward)
curl -f http://localhost:8000/docs
```

Execute an agent test workflow:
```bash
curl -X POST "http://localhost:8000/api/agents/execute?client_id=default&agent_name=joke" \
  -H "Content-Type: multipart/form-data" \
  -F "message=Tell me a developer joke"
```

For complete details on each runtime environment and local SSL/TLS certificate trust setup, consult:
- [Virtual Machine Runtime Guide](file:///Users/rajesh/aigenzey-install-scripts/vm-runtime/README.md)
- [Kubernetes Runtime Guide](file:///Users/rajesh/aigenzey-install-scripts/kubernetes-runtime/README.md) (includes local macOS Keychain cert trust commands)

---

## License

Apache 2.0. See [LICENSE](file:///Users/rajesh/aigenzey-install-scripts/LICENSE) for details.
