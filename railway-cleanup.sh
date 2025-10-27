#!/usr/bin/env bash
# railway-cleanup.sh - Xóa services trong project (flexibly)
# Usage: 
#   ./railway-cleanup.sh                    # Remove all default services
#   ./railway-cleanup.sh pg-1 pg-2          # Remove specific services
#   ./railway-cleanup.sh --all              # Remove all services (with confirmation)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

show_help() {
    cat << EOF
Railway Cleanup Script - Delete services from Railway project

Usage:
  ./railway-cleanup.sh                    Remove default services (pg-1..pg-4, witness)
  ./railway-cleanup.sh SERVICE1 SERVICE2  Remove specific services
  ./railway-cleanup.sh --all              Remove ALL services in project
  ./railway-cleanup.sh --help             Show this help

Examples:
  ./railway-cleanup.sh                    # Remove pg-1, pg-2, pg-3, pg-4, witness
  ./railway-cleanup.sh pg-1 pg-2          # Remove only pg-1 and pg-2
  ./railway-cleanup.sh --all              # Remove all services

EOF
    exit 0
}

# Default services
DEFAULT_SERVICES=("pg-1" "pg-2" "pg-3" "pg-4" "witness")

# Parse arguments
SERVICES_TO_REMOVE=()
SKIP_CONFIRM=false

if [ $# -eq 0 ]; then
    # No args: use default services
    SERVICES_TO_REMOVE=("${DEFAULT_SERVICES[@]}")
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
elif [ "$1" = "--all" ]; then
    # --all flag: get all services from Railway
    log_info "Fetching all services from Railway..."
    mapfile -t SERVICES_TO_REMOVE < <(railway status --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for svc in data.get('services', {}).get('edges', []):
        print(svc['node']['name'])
except: pass
" || echo "")
    
    if [ ${#SERVICES_TO_REMOVE[@]} -eq 0 ]; then
        log_warn "No services found in Railway project"
        exit 0
    fi
else
    # Custom service names provided
    SERVICES_TO_REMOVE=("$@")
    SKIP_CONFIRM=true
fi

# Show what will be removed
log_warn "The following services will be DELETED:"
for svc in "${SERVICES_TO_REMOVE[@]}"; do
    echo "  - $svc"
done

# Confirmation (unless skipped)
if [ "$SKIP_CONFIRM" = false ]; then
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled."
        exit 0
    fi
fi

# Remove services one by one
SUCCESS_COUNT=0
FAIL_COUNT=0

for service in "${SERVICES_TO_REMOVE[@]}"; do
    log_info "Removing service: $service"
    
    # Try to select service first
    if railway service "$service" 2>/dev/null; then
        # Service exists, auto-confirm delete using 'yes' command
        log_info "  Deleting $service..."
        if echo "y" | railway service delete 2>&1 | grep -qi "deleted\|removed"; then
            log_success "  ✓ Deleted $service"
            ((SUCCESS_COUNT++))
        else
            log_error "  ✗ Failed to delete $service"
            ((FAIL_COUNT++))
        fi
    else
        log_warn "  Service $service not found (skipping)"
        ((FAIL_COUNT++))
    fi
    
    # Small delay to avoid rate limiting
    sleep 2
done

log_info ""
log_info "Cleanup summary:"
log_success "  Removed: $SUCCESS_COUNT services"
if [ $FAIL_COUNT -gt 0 ]; then
    log_warn "  Failed/Skipped: $FAIL_COUNT services"
fi
log_info "Cleanup complete!"
