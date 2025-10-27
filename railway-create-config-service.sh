#!/usr/bin/env bash
# railway-create-config-service.sh - Tạo config service cho shared variables
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

log_info "Creating config service for shared variables..."

# Tạo một empty service để chứa shared config
railway add --service "cluster-config" 2>&1 || true

sleep 2

# Link to config service
railway service "cluster-config"

# Set shared variables
log_info "Setting shared variables in cluster-config service..."

railway variables --set "POSTGRES_PASSWORD=L0ngS3cur3P@ssw0rd"
railway variables --set "REPMGR_PASSWORD=L0ngS3cur3P@ssw0rd"  
railway variables --set "PRIMARY_HINT=pg-1"

log_success "Config service created with shared variables!"
log_info ""
log_info "Now you need to reference these in other services:"
log_info "In each service's variables, set:"
log_info '  POSTGRES_PASSWORD=${{cluster-config.POSTGRES_PASSWORD}}'
log_info '  REPMGR_PASSWORD=${{cluster-config.REPMGR_PASSWORD}}'
log_info '  PRIMARY_HINT=${{cluster-config.PRIMARY_HINT}}'
