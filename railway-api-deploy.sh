#!/bin/bash
set -e

# Railway API Deployment Script
# Uses Railway GraphQL API for automated service deployment

echo "=========================================="
echo "Railway API Deployment - PostgreSQL HA Cluster"
echo "=========================================="

# Configuration
PROJECT_ID="bde39110-2980-43cc-94aa-ac5a822a85cf"
ENVIRONMENT_NAME="production"
RAILWAY_API="https://backboard.railway.app/graphql/v2"

# Get Railway API token
RAILWAY_TOKEN=$(cat ~/.railway/config.json | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$RAILWAY_TOKEN" ]; then
    echo "❌ Error: Railway token not found. Please run 'railway login' first"
    exit 1
fi

echo "✅ Railway token found"
echo ""

# Get environment ID
echo "📡 Getting environment ID..."
ENVIRONMENT_ID=$(curl -s "$RAILWAY_API" \
  -H "Authorization: Bearer $RAILWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"query { project(id: \\\"$PROJECT_ID\\\") { environments { edges { node { id name } } } } }\"}" | \
  grep -o "\"id\":\"[^\"]*\"" | head -1 | cut -d'"' -f4)

if [ -z "$ENVIRONMENT_ID" ]; then
    echo "❌ Error: Could not get environment ID"
    exit 1
fi

echo "✅ Environment ID: $ENVIRONMENT_ID"
echo ""

# Function to create service via API
create_service_api() {
    local service_name=$1
    local service_dir=$2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 Creating service: $service_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Create service
    local mutation=$(cat <<EOF
mutation {
  serviceCreate(input: {
    name: "$service_name",
    projectId: "$PROJECT_ID",
    source: {
      repo: "hiendt2907/new_pg_cluster_clone",
      rootDirectory: "$service_dir"
    }
  }) {
    id
    name
  }
}
EOF
)
    
    local service_id=$(curl -s "$RAILWAY_API" \
      -H "Authorization: Bearer $RAILWAY_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"$(echo $mutation | sed 's/"/\\"/g')\"}" | \
      grep -o "\"id\":\"[^\"]*\"" | head -1 | cut -d'"' -f4)
    
    if [ -z "$service_id" ]; then
        echo "❌ Failed to create service $service_name"
        return 1
    fi
    
    echo "✅ Service created: $service_id"
    
    # Set environment variables
    echo "⚙️  Setting environment variables..."
    
    if [ -f "$service_dir/.env" ]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove quotes from value
            value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            
            echo "  Setting $key"
            
            # Set variable via API
            curl -s "$RAILWAY_API" \
              -H "Authorization: Bearer $RAILWAY_TOKEN" \
              -H "Content-Type: application/json" \
              -d "{\"query\":\"mutation { variableUpsert(input: { name: \\\"$key\\\", value: \\\"$value\\\", serviceId: \\\"$service_id\\\", environmentId: \\\"$ENVIRONMENT_ID\\\" }) { id } }\"}" > /dev/null
        done < "$service_dir/.env"
    fi
    
    # Create volume for PostgreSQL nodes
    if [[ "$service_name" =~ ^pg-[0-9]$ ]] || [[ "$service_name" == "witness" ]]; then
        echo "💾 Creating volume for $service_name..."
        
        local volume_mutation=$(cat <<EOF
mutation {
  volumeCreate(input: {
    name: "${service_name}-data",
    mountPath: "/var/lib/postgresql/data",
    serviceId: "$service_id",
    environmentId: "$ENVIRONMENT_ID"
  }) {
    id
    name
  }
}
EOF
)
        
        curl -s "$RAILWAY_API" \
          -H "Authorization: Bearer $RAILWAY_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"query\":\"$(echo $volume_mutation | sed 's/"/\\"/g')\"}" > /dev/null
        
        echo "✅ Volume created"
    fi
    
    # Deploy service
    echo "🚢 Deploying service..."
    curl -s "$RAILWAY_API" \
      -H "Authorization: Bearer $RAILWAY_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"mutation { deploymentTrigger(input: { serviceId: \\\"$service_id\\\", environmentId: \\\"$ENVIRONMENT_ID\\\" }) { id status } }\"}" > /dev/null
    
    echo "✅ Service $service_name deployed"
    echo ""
}

# Function to list all services
list_services_api() {
    echo "📋 Current services in project:"
    echo ""
    
    curl -s "$RAILWAY_API" \
      -H "Authorization: Bearer $RAILWAY_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"query { project(id: \\\"$PROJECT_ID\\\") { services { edges { node { id name } } } } }\"}" | \
      grep -o '"name":"[^"]*"' | cut -d'"' -f4
    
    echo ""
}

# Function to delete all services
delete_all_services_api() {
    echo "🗑️  Deleting all existing services..."
    echo ""
    
    local service_ids=$(curl -s "$RAILWAY_API" \
      -H "Authorization: Bearer $RAILWAY_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"query { project(id: \\\"$PROJECT_ID\\\") { services { edges { node { id name } } } } }\"}" | \
      grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    for service_id in $service_ids; do
        echo "  Deleting service: $service_id"
        curl -s "$RAILWAY_API" \
          -H "Authorization: Bearer $RAILWAY_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"query\":\"mutation { serviceDelete(id: \\\"$service_id\\\") }\"}" > /dev/null
    done
    
    echo "✅ All services deleted"
    echo ""
}

# Function to get service public URL
get_service_url() {
    local service_name=$1
    
    curl -s "$RAILWAY_API" \
      -H "Authorization: Bearer $RAILWAY_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"query { project(id: \\\"$PROJECT_ID\\\") { services(name: \\\"$service_name\\\") { edges { node { id domains { edges { node { domain } } } } } } } }\"}" | \
      grep -o '"domain":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Main menu
echo "Choose deployment option:"
echo "1. Deploy full cluster (pg-1/2/3/4 + witness + ProxySQL x2)"
echo "2. Delete all existing services"
echo "3. List current services"
echo "4. Deploy single service"
echo ""
read -p "Enter choice [1-4]: " choice

case $choice in
    1)
        echo ""
        echo "🚀 Starting full cluster deployment..."
        echo ""
        
        # Set shared environment variables first
        echo "⚙️  Setting shared environment variables..."
        ./railway-setup-shared-vars.sh
        echo ""
        
        # Deploy PostgreSQL nodes
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📦 Deploying PostgreSQL nodes"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        create_service_api "pg-1" "pg-1"
        echo "⏳ Waiting 30 seconds for pg-1 to initialize..."
        sleep 30
        
        create_service_api "witness" "witness"
        echo "⏳ Waiting 10 seconds for witness to register..."
        sleep 10
        
        # Deploy remaining PostgreSQL nodes in parallel
        echo "🔄 Deploying pg-2, pg-3, pg-4 in parallel..."
        create_service_api "pg-2" "pg-2" &
        create_service_api "pg-3" "pg-3" &
        create_service_api "pg-4" "pg-4" &
        wait
        
        echo "⏳ Waiting 60 seconds for cluster to form..."
        sleep 60
        
        # Deploy ProxySQL instances
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🔌 Deploying ProxySQL HA pair"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        create_service_api "proxysql" "proxysql" &
        create_service_api "proxysql-2" "proxysql-2" &
        wait
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ Deployment complete!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "📊 Deployed services:"
        list_services_api
        
        echo "⏳ Waiting 30 seconds for services to start..."
        sleep 30
        
        echo ""
        echo "🔗 ProxySQL Endpoints:"
        echo "  proxysql:   $(get_service_url 'proxysql')"
        echo "  proxysql-2: $(get_service_url 'proxysql-2')"
        echo ""
        echo "📝 Next steps:"
        echo "  1. Generate domains: railway service proxysql && railway domain"
        echo "  2. Check logs: railway logs --service proxysql"
        echo "  3. Verify cluster: railway ssh --service pg-1"
        echo ""
        ;;
        
    2)
        read -p "⚠️  Are you sure you want to delete ALL services? (yes/no): " confirm
        if [ "$confirm" == "yes" ]; then
            delete_all_services_api
        else
            echo "❌ Cancelled"
        fi
        ;;
        
    3)
        list_services_api
        ;;
        
    4)
        read -p "Enter service name (e.g., pg-1, proxysql): " service_name
        read -p "Enter service directory (e.g., pg-1, proxysql): " service_dir
        create_service_api "$service_name" "$service_dir"
        ;;
        
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "✅ Done!"
