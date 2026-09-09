# Aigenzey Runtime - Virtual Machine (VM) Installation

This directory contains the production-grade installation scripts and systemd definitions to deploy the **Aigenzey Runtime Engine (ARE)** and supporting services onto Bring-Your-Own (BYO) Virtual Machines or bare-metal servers.

---

## 1. Overview & Architecture

The Aigenzey Runtime data plane executes AI agent workflows and tools. When deployed onto a VM, the runtime consists of:

```text
┌─────────────────────────────────────────────────────────────┐
│                       Virtual Machine                       │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │               ai-gateway (Port 8090)                │   │
│   │  - Edge proxy, token quota & API key enforcement     │   │
│   └──────────────────────────┬──────────────────────────┘   │
│                              │ proxy                        │
│   ┌──────────────────────────▼──────────────────────────┐   │
│   │                 ARE - Agent Runtime                 │   │
│   │                    (Port 8000)                      │   │
│   │  - ADK agent workflows, tools & session engine     │   │
│   └──────────┬───────────────────────────────┬──────────┘   │
│              │ cache / state                 │ scraping     │
│   ┌──────────▼──────────┐         ┌──────────▼──────────┐   │
│   │  Redis (Port 6379)  │         │ crawl4ai (Pt 11235) │   │
│   └─────────────────────┘         └─────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

- **ARE (Agent Runtime Engine)**: FastAPI agent execution engine (port `8000`).
- **AI Gateway**: Edge routing, rate limiting, and KMS authentication (port `8090`).
- **Redis Server**: High-throughput session storage and message cache (port `6379`).
- **crawl4ai**: Docker container providing browser automation and web content extraction for agents (port `11235`).
- **Systemd Management**: Controlled via `aigenzey-runtime.service` for automatic restart and persistence across reboots.

---

## 2. Required Setup Inputs

The installer configures `/opt/aigenzey/config.properties` during setup. The following inputs are required or recommended:

| Parameter | Key in `config.properties` | CLI Flag | Description |
| :--- | :--- | :--- | :--- |
| **Organization Name** | `DEFAULT_ORG` | `--default-org <name>` | Organization slug in Aigenzey (e.g. `acme-corp`). Isolates agent definitions, tools, and executions. |
| **Instance Name** | `INSTANCE_NAME` | `--instance-name <name>` | Unique hostname or identifier for this VM node (e.g. `vm-runtime-prod-01`). |
| **Instance Admin Email** | `INSTANCEADMIN_EMAIL` | `--instanceadmin-email <email>` | Admin email registered in central Aigenzey platform. |
| **Instance Admin Password** | `INSTANCEADMIN_PASSWORD` | `--instanceadmin-password <pw>` | Password for the admin account to authenticate synchronization. |
| **Gemini API Key** | `GOOGLE_API_KEY` | (set in config file) | Google Gemini API key used by the Agent Runtime Engine. |
| **Central API URL** | `AIGENZEY_API_URL` | `--api-url <url>` | URL of central Management API (default: `https://api.platform.aigenzey.com`). |
| **Artifact / GCR Access** | N/A | `--gcloud` | If pulling release tarballs from GCP Artifact Registry, the VM service account must have `roles/artifactregistry.reader`. |

---

## 3. Configuring the Setup

### Approach A: Using `config.properties` (Recommended)

1. Create a `config.properties` file from the example:
   ```bash
   cp config.properties.example config.properties
   ```

2. Fill in your environment parameters:
   ```properties
   # Central Control Plane URL
   AIGENZEY_API_URL=https://api.platform.aigenzey.com

   # Instance and Organization Identification
   INSTANCE_NAME=my-vm-runtime-01
   DEFAULT_ORG=my-org

   # Instance Administrator Credentials
   INSTANCEADMIN_EMAIL=admin@mycompany.com
   INSTANCEADMIN_PASSWORD=MySecurePassword123

   # Model Provider Keys
   GOOGLE_API_KEY=AIzaSyD...
   OPENAI_API_KEY=sk-...
   ANTHROPIC_API_KEY=
   ```

3. Run the installer pointing to your configuration file:
   ```bash
   sudo ./install.sh --version 1.0.0 --config ./config.properties
   ```

### Approach B: Passing Flags to `install.sh`

```bash
sudo ./install.sh \
  --version 1.0.0 \
  --default-org my-org \
  --instance-name my-vm-node-1 \
  --instanceadmin-email admin@mycompany.com \
  --instanceadmin-password MySecurePassword123 \
  --api-url https://api.platform.aigenzey.com
```

### Approach C: Google Cloud Compute Engine Metadata

When running on a GCP Compute Engine instance, `install.sh` will automatically query the GCP instance metadata server (`http://metadata.google.internal/computeMetadata/v1/instance/attributes`) for:
- `AIGENZEY_API_URL`
- `INSTANCE_NAME`
- `INSTANCEADMIN_EMAIL`
- `INSTANCEADMIN_PASSWORD`
- `DEFAULT_ORG`

If these attributes are set on the VM during `gcloud compute instances create`, the script automatically detects and populates them!

---

## 4. Machine Bootstrap vs. Runtime Install

The VM installation is cleanly decoupled into two stages:

```text
┌─────────────────────────────────────────────────────────────┐
│ 1. Machine Bootstrap (bootstrap.sh / bootstrap-ubuntu.sh)   │
│    - Installs OS packages, native build tools (gcc, libssl) │
│    - Installs Python 3.13 (deadsnakes PPA / dnf) & pip      │
│    - Installs and starts Redis server                       │
│    - Installs Docker CE & launches crawl4ai container       │
│    - Disables systemd nginx daemon (prevents port conflicts)│
│    - Creates 'aigenzey' system user and sudoers entry       │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Runtime Installation (install.sh)                        │
│    - Calls bootstrap.sh (unless --skip-bootstrap is set)    │
│    - Configures /opt/aigenzey/config.properties             │
│    - Fetches and unpacks runtime release tarball            │
│    - Runs ./aigenzey-service.sh setup --runtime & env prod  │
│    - Registers & activates aigenzey-runtime.service         │
│    - Performs end-to-end health check                       │
└─────────────────────────────────────────────────────────────┘
```

### Running the Machine Bootstrap Standalone
If you are pre-baking VM machine images (Packer / Golden AMI) or provisioning through Cloud-Init:
```bash
# Run bootstrap for runtime profile
sudo ./bootstrap.sh --mode runtime

# Or using the alias:
sudo ./bootstrap-ubuntu.sh --mode runtime
```

### Running Full Installation
`install.sh` automatically invokes `bootstrap.sh` as Step 1:
```bash
sudo ./install.sh --version 1.0.0 --config ./config.properties
```
*If you already ran `bootstrap.sh` earlier, add `--skip-bootstrap` to skip OS package re-installation.*

---

## 5. Prerequisites

### Supported Operating Systems
- **Ubuntu**: 22.04 LTS, 24.04 LTS
- **Debian**: 11, 12
- **RHEL / Rocky Linux / AlmaLinux / CentOS Stream**: 8, 9
- **Fedora**: 38+

### Minimum Hardware
- **CPU**: 2 vCPUs (4 vCPUs recommended for production workloads)
- **RAM**: 4 GB RAM (8 GB+ recommended)
- **Disk**: 20 GB available SSD storage
- **Network**: Outbound internet connectivity for package downloads, LLM APIs (OpenAI, Gemini, Anthropic), and model dependencies.

### Firewall Ports
Ensure the following ports are open internally or externally as required:
- `8000`: ARE REST and streaming endpoints
- `8090`: AI Gateway HTTP proxy (if external access routes through gateway)
- `11235`: crawl4ai local scraping service (internal only)
- `6379`: Redis service (internal only)

---

## 6. Package Sourcing Options

The VM installer can fetch the runtime package from several sources:

### Option 1: Public Cloud Storage URL
```bash
sudo ./install.sh \
  --version 1.0.0 \
  --url https://storage.googleapis.com/aigenzey-releases/aigenzey-runtime-release-1.0.0.tar.gz \
  --config ./config.properties
```

### Option 2: Pre-Downloaded Local Tarball
```bash
sudo ./install.sh \
  --tarball /tmp/aigenzey-runtime-release-1.0.0.tar.gz \
  --config ./config.properties
```

### Option 3: Google Artifact Registry (GCP VM)
```bash
sudo ./install.sh \
  --version 1.0.0 \
  --gcloud \
  --project-id aigenzey-dev \
  --repo aigenzey-releases \
  --location us-central1 \
  --config ./config.properties
```

---

## 6. Service Management

Use the included `service.sh` helper or standard `systemctl` commands:

```bash
# Check runtime status
./service.sh status

# Start / Stop / Restart
sudo ./service.sh start
sudo ./service.sh stop
sudo ./service.sh restart

# Follow logs
./service.sh logs
./service.sh logs are
./service.sh logs ai-gateway
./service.sh logs systemd

# Verify health endpoint
./service.sh health
```

Or directly via `systemctl`:
```bash
sudo systemctl status aigenzey-runtime
sudo systemctl restart aigenzey-runtime
sudo journalctl -u aigenzey-runtime -f
```

---

## 7. Verification

Once the service is active, test the ARE health endpoint:

```bash
curl -f http://localhost:8000/docs
```

Execute a test query against an agent:

```bash
curl -X POST "http://localhost:8000/api/agents/execute?client_id=default&agent_name=joke" \
  -H "Content-Type: multipart/form-data" \
  -F "message=Tell me a short programming joke"
```

---

## 8. Uninstallation

To cleanly stop all services and remove configuration:

```bash
sudo ./uninstall.sh
```

To preserve logs and agent configurations while uninstalling binaries:
```bash
sudo ./uninstall.sh --keep-data
```
