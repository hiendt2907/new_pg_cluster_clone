#!/usr/bin/env bash
# railway-deploy.sh - Tự động deploy PostgreSQL HA cluster lên Railway
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    log_error "Railway CLI not found. Install it first:"
    echo "curl -fsSL https://railway.app/install.sh | sh"
    exit 1
fi

# Check if logged in
if ! railway whoami &> /dev/null; then
    log_error "Not logged in to Railway. Please run: railway login"
    exit 1
fi

# Project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

log_info "Current directory: $PROJECT_DIR"

# Check if project is linked
if ! railway status &> /dev/null; then
    log_warn "Project not linked. Linking to Railway project..."
    railway link || {
        log_error "Failed to link project. Please run 'railway link' manually."
        exit 1
    }
fi

log_info "Getting project info..."
PROJECT_INFO=$(railway status --json 2>/dev/null || echo "")
if [ -z "$PROJECT_INFO" ]; then
    log_error "Could not get project info. Is the project linked?"
    exit 1
fi

# Extract project ID and name using more robust parsing
PROJECT_ID=$(echo "$PROJECT_INFO" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
PROJECT_NAME=$(echo "$PROJECT_INFO" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$PROJECT_ID" ]; then
    log_error "Could not parse project ID from Railway status"
    log_error "Raw output:"
    echo "$PROJECT_INFO"
    exit 1
fi

log_success "Project: $PROJECT_NAME (ID: $PROJECT_ID)"

# Function to create a service
create_service() {
    local service_name=$1
    local service_dir=$2
    
    log_info "Creating service: $service_name from directory: $service_dir"
    
    # Change to service directory
    cd "$PROJECT_DIR/$service_dir"
    
    # Add service
    log_info "  Adding service to Railway..."
    ADD_OUTPUT=$(railway add --service "$service_name" 2>&1)
    
    if echo "$ADD_OUTPUT" | grep -qi "already exists"; then
        log_warn "  Service '$service_name' already exists"
    elif echo "$ADD_OUTPUT" | grep -qi "created"; then
        log_success "  Service '$service_name' created successfully"
    else
        log_info "  Railway add output: $ADD_OUTPUT"
    fi
    
    # Wait for service to register
    sleep 3
    
    # Link to this service
    log_info "  Linking to service..."
    if railway service "$service_name" 2>/dev/null; then
        log_success "  Linked to service $service_name"
    else
        log_error "  Failed to link to service $service_name"
        log_info "  Try linking manually: railway service $service_name"
        return 1
    fi
    
    # Set environment variables from .env file
    if [ -f ".env" ]; then
        log_info "  Setting environment variables..."
        while IFS='=' read -r key value; do
            # Skip empty lines and comments
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            
            # Remove any quotes from value
            value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            
            log_info "    Setting $key"
            railway variables --set "$key=$value" --skip-deploys || {
                log_warn "    Failed to set $key, continuing..."
            }
        done < .env
        log_success "  Environment variables set"
    else
        log_warn "  No .env file found for $service_name"
    fi
    
    cd "$PROJECT_DIR"
}

# Function to add volume to a service
add_volume() {
    local service_name=$1
    local mount_path=$2
    
    log_info "Adding volume to $service_name at $mount_path"
    
    cd "$PROJECT_DIR/${service_name}"
    railway service "$service_name"
    
    # Check if volume already exists
    EXISTING_VOLUMES=$(railway volume list 2>&1 || echo "")
    if echo "$EXISTING_VOLUMES" | grep -q "$mount_path"; then
        log_warn "  Volume for $service_name already exists at $mount_path"
    else
        # Add volume - Railway CLI will prompt for mount path
        echo "$mount_path" | railway volume add || {
            log_warn "  Failed to add volume to $service_name"
            log_info "  You may need to add it manually via Dashboard"
        }
        log_success "  Volume added to $service_name"
    fi
    
    cd "$PROJECT_DIR"
}

# Function to deploy a service
deploy_service() {
    local service_name=$1
    local service_dir=$2
    
    log_info "Deploying service: $service_name"
    
    cd "$PROJECT_DIR/$service_dir"
    railway service "$service_name"
    
    # Deploy using railway up
    log_info "  Starting deployment..."
    railway up --detach || {
        log_error "  Failed to deploy $service_name"
        return 1
    }
    
    log_success "  Deployment started for $service_name"
    cd "$PROJECT_DIR"
}

# Main deployment flow
main() {
    log_info "=== Starting Railway PostgreSQL HA Cluster Deployment ==="
    
    # Array of services in deployment order
    declare -a SERVICES=(
        "pg-1:pg-1"
        "pg-2:pg-2"
        "pg-3:pg-3"
        "pg-4:pg-4"
        "witness:witness"
    )
    
    # Ask user if they want to deploy proxy
    log_info ""
    log_info "Do you want to deploy a proxy layer?"
    echo "  1) No proxy (default)"
    echo "  2) ProxySQL 3.0 BETA (2 instances for HA) - PostgreSQL native support"
    echo "  3) pgpool-II (PostgreSQL-native load balancer)"
    read -p "Enter choice [1-3]: " proxy_choice
    
    case "$proxy_choice" in
        2)
            log_info "ProxySQL 3.0 BETA selected (2 instances for HA)"
            SERVICES+=("proxysql:proxysql")
            SERVICES+=("proxysql-2:proxysql-2")
            ;;
        3)
            log_info "pgpool-II selected"
            SERVICES+=("pgpool:pgpool")
            ;;
        *)
            log_info "No proxy selected"
            ;;
    esac
    
    log_info "Step 1: Creating all services..."
    for service_def in "${SERVICES[@]}"; do
        IFS=':' read -r name dir <<< "$service_def"
        create_service "$name" "$dir"
    done
    
    log_info ""
    log_info "Step 2: Adding volumes to PostgreSQL nodes..."
    add_volume "pg-1" "/var/lib/postgresql"
    add_volume "pg-2" "/var/lib/postgresql"
    add_volume "pg-3" "/var/lib/postgresql"
    add_volume "pg-4" "/var/lib/postgresql"
    log_info "  Witness does not need a volume"
    
    log_info ""
    log_info "Step 3: Deploying services in correct order..."
    
    # Deploy primary first
    log_info "Deploying primary node (pg-1)..."
    deploy_service "pg-1" "pg-1"
    
    log_info "Waiting 30 seconds for pg-1 to initialize..."
    sleep 30
    
    # Deploy witness
    log_info "Deploying witness node..."
    deploy_service "witness" "witness"
    
    log_info "Waiting 10 seconds for witness to connect..."
    sleep 10
    
    # Deploy standby nodes
    log_info "Deploying standby nodes (pg-2, pg-3, pg-4)..."
    deploy_service "pg-2" "pg-2" &
    PID2=$!
    deploy_service "pg-3" "pg-3" &
    PID3=$!
    deploy_service "pg-4" "pg-4" &
    PID4=$!
    
    # Wait for all standby deployments
    wait $PID2 $PID3 $PID4
    
    # Deploy proxy if selected
    if [ "$proxy_choice" = "2" ]; then
        log_info ""
        log_info "Waiting 10 seconds before deploying ProxySQL HA pair..."
        sleep 10
        log_info "Deploying ProxySQL instances (2 for HA)..."
        deploy_service "proxysql" "proxysql" &
        PIDP1=$!
        deploy_service "proxysql-2" "proxysql-2" &
        PIDP2=$!
        wait $PIDP1 $PIDP2
        log_success "ProxySQL HA pair deployed!"
    elif [ "$proxy_choice" = "3" ]; then
        log_info ""
        log_info "Waiting 10 seconds before deploying pgpool-II..."
        sleep 10
        log_info "Deploying pgpool-II..."
        deploy_service "pgpool" "pgpool"
    fi
    
    log_success "=== All services deployed! ==="
    log_info ""
    log_info "Next steps:"
    log_info "1. Check deployment status: railway status"
    log_info "2. View logs: railway logs --service pg-1"
    log_info "3. SSH into pg-1: railway ssh --service pg-1"
    log_info "4. Check cluster: gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show"
    log_info ""
    log_info "Opening Railway Dashboard..."
    railway open || true
}

# Run main function
main "$@"
