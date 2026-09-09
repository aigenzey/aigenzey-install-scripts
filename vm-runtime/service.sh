#!/usr/bin/env bash
#
# Aigenzey Runtime VM Service Helper
# Manage and inspect Aigenzey Runtime services on the VM.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

USER_NAME="aigenzey"
USER_HOME="/opt/aigenzey"
RUNTIME_DIR="${USER_HOME}/aigenzey-runtime"
CONFIG_FILE="${USER_HOME}/config.properties"

has_systemd() {
    systemctl list-unit-files 2>/dev/null | grep -q "aigenzey-runtime.service"
}

print_usage() {
    cat << 'EOF'
Aigenzey Runtime Service Management

Usage:
  ./service.sh <command> [arguments]

Commands:
  start          Start runtime services
  stop           Stop runtime services
  restart        Restart runtime services
  status         Show status of runtime services, ports, and health checks
  logs [service] View logs (options: are, ai-gateway, systemd, all; default: all)
  health         Perform deep health and ping check
  test-agent     Execute a test ping/agent execution request
  help           Display this help message
EOF
}

cmd_start() {
    if has_systemd && [[ $EUID -eq 0 ]]; then
        echo -e "${BLUE}Starting via systemd...${NC}"
        systemctl start aigenzey-runtime
        systemctl status aigenzey-runtime --no-pager
    elif [[ -x "${RUNTIME_DIR}/aigenzey-service.sh" ]]; then
        echo -e "${BLUE}Starting runtime services...${NC}"
        sudo -u "${USER_NAME}" "${RUNTIME_DIR}/aigenzey-service.sh" start --runtime --no-arp -f "${CONFIG_FILE}"
    else
        echo -e "${RED}Error: Runtime installation not found at ${RUNTIME_DIR}${NC}"
        exit 1
    fi
}

cmd_stop() {
    if has_systemd && [[ $EUID -eq 0 ]]; then
        echo -e "${BLUE}Stopping via systemd...${NC}"
        systemctl stop aigenzey-runtime
    elif [[ -x "${RUNTIME_DIR}/aigenzey-service.sh" ]]; then
        echo -e "${BLUE}Stopping runtime services...${NC}"
        sudo -u "${USER_NAME}" "${RUNTIME_DIR}/aigenzey-service.sh" stop --runtime
    else
        echo -e "${RED}Error: Runtime installation not found at ${RUNTIME_DIR}${NC}"
        exit 1
    fi
}

cmd_restart() {
    if has_systemd && [[ $EUID -eq 0 ]]; then
        echo -e "${BLUE}Restarting via systemd...${NC}"
        systemctl restart aigenzey-runtime
    elif [[ -x "${RUNTIME_DIR}/aigenzey-service.sh" ]]; then
        echo -e "${BLUE}Restarting runtime services...${NC}"
        sudo -u "${USER_NAME}" "${RUNTIME_DIR}/aigenzey-service.sh" restart --runtime -f "${CONFIG_FILE}"
    else
        echo -e "${RED}Error: Runtime installation not found at ${RUNTIME_DIR}${NC}"
        exit 1
    fi
}

cmd_status() {
    echo "=========================================================="
    echo "           Aigenzey Runtime Status Inspection             "
    echo "=========================================================="

    # Systemd status
    if has_systemd; then
        if systemctl is-active --quiet aigenzey-runtime; then
            echo -e "Systemd Service:       ${GREEN}ACTIVE${NC}"
        else
            echo -e "Systemd Service:       ${RED}INACTIVE / FAILED${NC}"
        fi
    fi

    # Port and process check
    echo "Service Ports:"
    # ARE (8000)
    if curl -sf http://localhost:8000/docs &>/dev/null || curl -sf http://localhost:8000/api/health &>/dev/null; then
        echo -e "  ARE Service (:8000):   ${GREEN}HEALTHY (Docs / API responsive)${NC}"
    else
        echo -e "  ARE Service (:8000):   ${RED}DOWN or NOT RESPONSIVE${NC}"
    fi

    # AI Gateway (8090)
    if curl -sf http://localhost:8090/docs &>/dev/null || curl -sf http://localhost:8090/health &>/dev/null; then
        echo -e "  AI Gateway (:8090):    ${GREEN}HEALTHY${NC}"
    else
        echo -e "  AI Gateway (:8090):    ${YELLOW}DOWN or NOT RUNNING (Optional)${NC}"
    fi

    # crawl4ai (11235)
    if curl -sf http://localhost:11235/health &>/dev/null || (command -v docker &>/dev/null && docker ps | grep -q crawl4ai); then
        echo -e "  crawl4ai (:11235):     ${GREEN}HEALTHY (Docker container active)${NC}"
    else
        echo -e "  crawl4ai (:11235):     ${RED}NOT RUNNING${NC}"
    fi

    # Redis (6379)
    if command -v redis-cli &>/dev/null && redis-cli ping 2>/dev/null | grep -q PONG; then
        echo -e "  Redis (:6379):         ${GREEN}HEALTHY (PONG)${NC}"
    elif systemctl is-active --quiet redis || systemctl is-active --quiet redis-server; then
        echo -e "  Redis (:6379):         ${GREEN}ACTIVE${NC}"
    else
        echo -e "  Redis (:6379):         ${YELLOW}CHECK STATUS${NC}"
    fi

    echo "=========================================================="
}

cmd_logs() {
    local TARGET="${1:-all}"
    case "${TARGET}" in
        systemd)
            journalctl -u aigenzey-runtime -f -n 100
            ;;
        are)
            if [[ -d "${RUNTIME_DIR}/are/logs" ]]; then
                tail -f -n 100 "${RUNTIME_DIR}/are/logs"/*.log
            elif [[ -f "${RUNTIME_DIR}/logs/are.log" ]]; then
                tail -f -n 100 "${RUNTIME_DIR}/logs/are.log"
            else
                journalctl -u aigenzey-runtime -f -n 100
            fi
            ;;
        ai-gateway)
            if [[ -d "${RUNTIME_DIR}/ai-gateway/logs" ]]; then
                tail -f -n 100 "${RUNTIME_DIR}/ai-gateway/logs"/*.log
            elif [[ -f "${RUNTIME_DIR}/logs/ai-gateway.log" ]]; then
                tail -f -n 100 "${RUNTIME_DIR}/logs/ai-gateway.log"
            else
                journalctl -u aigenzey-runtime -f -n 100
            fi
            ;;
        *)
            if has_systemd; then
                journalctl -u aigenzey-runtime -f -n 100
            else
                tail -f -n 100 "${RUNTIME_DIR}/logs"/*.log 2>/dev/null || echo "No log files found in ${RUNTIME_DIR}/logs"
            fi
            ;;
    esac
}

cmd_health() {
    echo -e "${BLUE}Testing ARE health check...${NC}"
    local STATUS_CODE
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/docs || echo "000")
    if [[ "${STATUS_CODE}" == "200" ]]; then
        echo -e "${GREEN}ARE HTTP 200 OK${NC}"
    else
        echo -e "${RED}ARE Health Check Failed (HTTP ${STATUS_CODE})${NC}"
    fi
}

COMMAND="${1:-status}"
shift || true

case "${COMMAND}" in
    start)
        cmd_start "$@"
        ;;
    stop)
        cmd_stop "$@"
        ;;
    restart)
        cmd_restart "$@"
        ;;
    status)
        cmd_status "$@"
        ;;
    logs)
        cmd_logs "$@"
        ;;
    health)
        cmd_health "$@"
        ;;
    -h|--help|help)
        print_usage
        exit 0
        ;;
    *)
        echo -e "${RED}Unknown command: ${COMMAND}${NC}"
        print_usage
        exit 1
        ;;
esac
