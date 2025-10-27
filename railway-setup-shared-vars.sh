#!/usr/bin/env bash
# railway-setup-shared-vars.sh - Tạo shared variables cho cluster
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

log_info "Setting up shared variables for PostgreSQL HA Cluster..."
echo ""

# Generate secure passwords if not provided
if [ -z "${POSTGRES_PASSWORD:-}" ]; then
    log_info "Generating secure POSTGRES_PASSWORD..."
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    log_success "Generated: ${POSTGRES_PASSWORD:0:8}... (32 characters)"
else
    log_info "Using provided POSTGRES_PASSWORD"
fi

if [ -z "${REPMGR_PASSWORD:-}" ]; then
    log_info "Generating secure REPMGR_PASSWORD..."
    REPMGR_PASSWORD=$(openssl rand -base64 32)
    log_success "Generated: ${REPMGR_PASSWORD:0:8}... (32 characters)"
else
    log_info "Using provided REPMGR_PASSWORD"
fi

echo ""
log_warn "⚠️  IMPORTANT: Save these passwords securely!"
log_warn "   POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
log_warn "   REPMGR_PASSWORD: $REPMGR_PASSWORD"
echo ""

# Set shared variables in Railway
log_info "Setting Railway environment variables..."

railway variables --set "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
railway variables --set "REPMGR_PASSWORD=$REPMGR_PASSWORD"
railway variables --set "PRIMARY_HINT=pg-1"

log_success "Shared variables set successfully!"
log_info "These variables are now available to all services in this environment."
