#!/usr/bin/env bash
#
# Aigenzey Universal Runtime Installer
# Dispatches installation to VM runtime or Kubernetes runtime.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_banner() {
    echo -e "${BOLD}${BLUE}"
    echo "=========================================================="
    echo "            Aigenzey Runtime Installer                    "
    echo "     Bring-Your-Own (BYO) Infrastructure Deployments     "
    echo "=========================================================="
    echo -e "${NC}"
}

print_usage() {
    print_banner
    cat << 'EOF'
Usage:
  ./install.sh <target> [options]

Targets:
  vm, virtual-machine    Install Aigenzey Runtime on a Linux Virtual Machine / Server
  k8s, kubernetes        Deploy Aigenzey Runtime onto a Kubernetes Cluster

Help for Targets:
  ./install.sh vm --help
  ./install.sh k8s --help

Examples:
  # Install on a Linux VM
  sudo ./install.sh vm --version 1.0.0

  # Deploy to Kubernetes with credentials key file
  ./install.sh k8s --key-file aigenzey-image-access.txt
EOF
}

TARGET="${1:-}"

if [[ -z "${TARGET}" ]]; then
    print_usage
    echo ""
    echo -e "${YELLOW}Please select an installation target:${NC}"
    echo "  1) Virtual Machine (Linux VM / Bare-Metal)"
    echo "  2) Kubernetes Cluster"
    echo "  3) Exit"
    read -rp "Enter choice [1-3]: " CHOICE
    case "${CHOICE}" in
        1)
            TARGET="vm"
            ;;
        2)
            TARGET="k8s"
            ;;
        *)
            echo "Exiting."
            exit 0
            ;;
    esac
else
    shift
fi

case "${TARGET}" in
    vm|virtual-machine)
        exec bash "${SCRIPT_DIR}/vm-runtime/install.sh" "$@"
        ;;
    k8s|kubernetes)
        exec bash "${SCRIPT_DIR}/kubernetes-runtime/install.sh" "$@"
        ;;
    -h|--help|help)
        print_usage
        exit 0
        ;;
    *)
        echo -e "${RED}Error: Unknown target '${TARGET}'${NC}" >&2
        print_usage
        exit 1
        ;;
esac
