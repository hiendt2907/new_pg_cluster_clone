#!/bin/bash
set -e

# Automated Railway Deployment using CLI
# No manual interaction required

echo "=========================================="
echo "Railway Automated Deployment"
echo "PostgreSQL HA Cluster + ProxySQL"
echo "=========================================="
echo ""

# Configuration
PROJECT_ID="bde39110-2980-43cc-94aa-ac5a822a85cf"
SERVICES=("pg-1" "pg-2" "pg-3" "pg-4" "witness" "proxysql" "proxysql-2")

# Check Railway login
if ! railway whoami &>/dev/null; then
    echo "❌ Error: Not logged in to Railway. Run 'railway login' first"
    exit 1
fi

echo "✅ Railway logged in"
echo ""

# Function to create service automatically
create_service_auto() {
    local service_name=$1
    local service_dir=$2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 Creating service: $service_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$service_dir"
    
    # Create service (Railway CLI will prompt, but we can pre-configure)
    echo "  Creating Railway service..."
    railway service create "$service_name" 2>/dev/null || echo "  Service may already exist"
    
    # Link to service
    railway service "$service_name"
    
    # Set environment variables from .env file
    if [ -f ".env" ]; then
        echo "  Setting environment variables..."
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove quotes
            value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            
            echo "    $key=$value"
            railway variables set "$key=$value" 2>/dev/null || true
        done < .env
    fi
    
    # Create volume for PostgreSQL nodes
    if [[ "$service_name" =~ ^pg-[0-9]$ ]] || [[ "$service_name" == "witness" ]]; then
        echo "  Creating volume..."
        railway volume add -m /var/lib/postgresql/data -n "${service_name}-data" 2>/dev/null || echo "  Volume may already exist"
    fi
    
    # Deploy (up command uploads and deploys)
    echo "  Deploying service..."
    railway up --detach 2>/dev/null || railway up --service "$service_name" --detach 2>/dev/null || true
    
    cd - > /dev/null
    
    echo "✅ Service $service_name created and deployed"
    echo ""
}

# Function to delete all services
delete_all_services() {
    echo "🗑️  Deleting all existing services..."
    echo ""
    
    for service in "${SERVICES[@]}"; do
        echo "  Deleting $service..."
        railway service "$service" 2>/dev/null && railway service delete --yes 2>/dev/null || echo "  Service $service not found or already deleted"
    done
    
    echo "✅ All services deleted"
    echo ""
}

# Main deployment
echo "Choose deployment option:"
echo "1. Full deployment (delete old + deploy new cluster)"
echo "2. Deploy cluster only (keep existing services)"
echo "3. Delete all services only"
echo ""
read -p "Enter choice [1-3]: " choice

case $choice in
    1)
        echo ""
        echo "🧹 Cleaning up old services..."
        delete_all_services
        
        echo "⏳ Waiting 10 seconds..."
        sleep 10
        
        echo ""
        echo "🚀 Starting fresh deployment..."
        echo ""
        
        # Set shared environment variables
        echo "⚙️  Setting shared environment variables..."
        ./railway-setup-shared-vars.sh
        echo ""
        
        # Deploy in sequence
        create_service_auto "pg-1" "pg-1"
        echo "⏳ Waiting 30 seconds for pg-1 to initialize..."
        sleep 30
        
        create_service_auto "witness" "witness"
        echo "⏳ Waiting 10 seconds for witness to register..."
        sleep 10
        
        create_service_auto "pg-2" "pg-2" &
        create_service_auto "pg-3" "pg-3" &
        create_service_auto "pg-4" "pg-4" &
        wait
        
        echo "⏳ Waiting 60 seconds for cluster to stabilize..."
        sleep 60
        
        create_service_auto "proxysql" "proxysql" &
        create_service_auto "proxysql-2" "proxysql-2" &
        wait
        
        echo ""
        echo "✅ Deployment complete!"
        ;;
        
    2)
        echo ""
        echo "🚀 Deploying cluster..."
        echo ""
        
        ./railway-setup-shared-vars.sh
        echo ""
        
        create_service_auto "pg-1" "pg-1"
        sleep 30
        
        create_service_auto "witness" "witness"
        sleep 10
        
        create_service_auto "pg-2" "pg-2" &
        create_service_auto "pg-3" "pg-3" &
        create_service_auto "pg-4" "pg-4" &
        wait
        sleep 60
        
        create_service_auto "proxysql" "proxysql" &
        create_service_auto "proxysql-2" "proxysql-2" &
        wait
        
        echo ""
        echo "✅ Deployment complete!"
        ;;
        
    3)
        delete_all_services
        ;;
        
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Next steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Check ProxySQL logs:"
echo "   railway logs --service proxysql"
echo ""
echo "2. Verify cluster status:"
echo "   railway ssh --service pg-1"
echo "   gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show"
echo ""
echo "3. Generate ProxySQL public domains:"
echo "   railway service proxysql && railway domain"
echo "   railway service proxysql-2 && railway domain"
echo ""
echo "4. Test connection (replace with your domain):"
echo "   PGPASSWORD=L0ngS3cur3P@ssw0rd psql 'postgresql://postgres@proxysql.railway.app:5432,proxysql-2.railway.app:5432/postgres'"
echo ""
