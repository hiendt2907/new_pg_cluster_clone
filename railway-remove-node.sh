#!/usr/bin/env bash
# railway-remove-node.sh - Xóa PostgreSQL node khỏi cluster
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check Railway CLI
if ! command -v railway &> /dev/null; then
    log_error "Railway CLI not found. Install: curl -fsSL https://railway.app/install.sh | sh"
    exit 1
fi

if ! railway whoami &> /dev/null; then
    log_error "Not logged in to Railway. Run: railway login"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Get node number from user
if [ -z "${1:-}" ]; then
    log_error "Usage: $0 <node_number>"
    log_info "Example: $0 5     # Removes pg-5"
    log_info "Example: $0 6     # Removes pg-6"
    exit 1
fi

NODE_NUM=$1
NODE_NAME="pg-${NODE_NUM}"
NODE_DIR="$PROJECT_DIR/$NODE_NAME"

# Validate node number
if ! [[ "$NODE_NUM" =~ ^[0-9]+$ ]]; then
    log_error "Node number must be a number. Got: '$NODE_NUM'"
    exit 1
fi

# Prevent removing core nodes
if [ "$NODE_NUM" -le 4 ]; then
    log_error "Cannot remove core nodes (pg-1 to pg-4)"
    log_error "These are essential for cluster quorum and availability"
    exit 1
fi

# Check if node directory exists
if [ ! -d "$NODE_DIR" ]; then
    log_warn "Node directory not found: $NODE_DIR"
    log_info "Node may have been already removed locally"
fi

log_warn "=== Removing PostgreSQL Node: $NODE_NAME ==="
log_warn "This will:"
log_warn "  1. Unregister node from repmgr cluster"
log_warn "  2. Delete Railway service (volume data will be deleted!)"
log_warn "  3. Remove from ProxySQL configuration"
log_warn "  4. Delete local directory"
log_warn ""
read -p "Are you sure? Type 'yes' to continue: " confirmation

if [ "$confirmation" != "yes" ]; then
    log_info "Operation cancelled"
    exit 0
fi

log_info "=== Removing $NODE_NAME ==="

# Step 1: Unregister from repmgr (if cluster is running)
log_info "Step 1: Unregistering from repmgr cluster..."
log_info "  Attempting to unregister via pg-1..."

# Try to unregister via pg-1 (primary)
railway service pg-1 2>/dev/null || true
UNREGISTER_CMD="gosu postgres repmgr -f /etc/repmgr/repmgr.conf primary unregister --node-id=$NODE_NUM --force"

if railway run bash -c "$UNREGISTER_CMD" 2>/dev/null; then
    log_success "  Node unregistered from repmgr"
else
    log_warn "  Failed to unregister (node may be already removed or cluster down)"
fi

# Step 2: Delete Railway service
log_info "Step 2: Deleting Railway service '$NODE_NAME'..."
railway service "$NODE_NAME" 2>/dev/null || {
    log_warn "  Service '$NODE_NAME' not found on Railway (may be already deleted)"
}

# Delete the service (this also deletes volumes)
if railway service delete --yes "$NODE_NAME" 2>/dev/null; then
    log_success "  Railway service deleted"
else
    log_warn "  Failed to delete service (may not exist or insufficient permissions)"
    log_info "  You can manually delete via Railway Dashboard"
fi

# Step 3: Remove from ProxySQL configuration
log_info "Step 3: Removing from ProxySQL configuration..."

for proxy in "proxysql" "proxysql-2"; do
    if [ -d "$PROJECT_DIR/$proxy" ]; then
        log_info "  Updating $proxy/entrypoint.sh..."
        
        # Remove node from PG_NODES list
        if grep -q "$NODE_NAME.railway.internal" "$PROJECT_DIR/$proxy/entrypoint.sh"; then
            # Remove the node (handle trailing comma or leading comma)
            sed -i "s/,$NODE_NAME\.railway\.internal//g" "$PROJECT_DIR/$proxy/entrypoint.sh"
            sed -i "s/$NODE_NAME\.railway\.internal,//g" "$PROJECT_DIR/$proxy/entrypoint.sh"
            log_success "  Removed from $proxy configuration"
            
            # Redeploy ProxySQL
            log_info "  Redeploying $proxy..."
            cd "$PROJECT_DIR/$proxy"
            railway service "$proxy" 2>/dev/null || true
            railway up --detach || {
                log_warn "  Failed to redeploy $proxy"
            }
        else
            log_info "  $NODE_NAME not found in $proxy configuration"
        fi
    fi
done

cd "$PROJECT_DIR"

# Step 4: Delete local directory
if [ -d "$NODE_DIR" ]; then
    log_info "Step 4: Deleting local directory..."
    rm -rf "$NODE_DIR"
    log_success "  Directory deleted: $NODE_DIR"
else
    log_info "Step 4: Local directory not found (skipping)"
fi

log_success ""
log_success "=== Node $NODE_NAME removed successfully! ==="
log_info ""
log_info "Verification steps:"
log_info "1. Check cluster status (should not show $NODE_NAME):"
log_info "   railway ssh --service pg-1"
log_info "   gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show"
log_info ""
log_info "2. Check ProxySQL (should not discover $NODE_NAME):"
log_info "   railway logs --service proxysql | grep -v '$NODE_NAME'"
log_info ""
log_info "3. Verify Railway services:"
log_info "   railway status"
