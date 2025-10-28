#!/bin/bash
# Setup monitoring user for PostgreSQL cluster
# This user has read-only access to statistics and catalog tables

set -e

# Get password from .env or use default
source "$(dirname "$0")/../.env" 2>/dev/null || true
MONITORING_PASSWORD=${MONITORING_PASSWORD:-CHANGE_ME_RUN_GENERATE_PASSWORDS}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-CHANGE_ME}

if [ "$MONITORING_PASSWORD" = "CHANGE_ME_RUN_GENERATE_PASSWORDS" ]; then
    echo "❌ Error: MONITORING_PASSWORD not set in .env"
    echo "Run: ./scripts/generate-passwords.sh"
    exit 1
fi

echo "Creating monitoring user on PostgreSQL nodes..."

for NODE in pg-1 pg-2 pg-3 pg-4; do
    echo ""
    echo "📊 Setting up monitoring user on $NODE..."
    
    # Create monitoring user
    docker exec -i $NODE gosu postgres psql << EOF
-- Create monitoring user if not exists
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'monitoring') THEN
        CREATE USER monitoring WITH PASSWORD '${MONITORING_PASSWORD}';
    END IF;
END
\$\$;

-- Grant connection privilege
GRANT CONNECT ON DATABASE postgres TO monitoring;

-- Grant usage on schema
GRANT USAGE ON SCHEMA public TO monitoring;

-- Grant select on all tables in public schema (for custom queries)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO monitoring;

-- Grant select on system catalogs and statistics views
-- These are needed for postgres_exporter default metrics
GRANT pg_monitor TO monitoring;

-- For custom queries on replication stats (requires superuser or pg_monitor)
-- pg_monitor role already includes these, but being explicit:
GRANT SELECT ON pg_stat_replication TO monitoring;
GRANT SELECT ON pg_replication_slots TO monitoring;

-- Display created user
\du monitoring

-- Verify permissions
SELECT 
    grantee, 
    privilege_type 
FROM information_schema.role_table_grants 
WHERE grantee = 'monitoring' 
LIMIT 5;

EOF
    
    if [ $? -eq 0 ]; then
        echo "✅ Monitoring user configured on $NODE"
    else
        echo "❌ Failed to configure monitoring user on $NODE"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Monitoring user setup completed!"
echo ""
echo "User: monitoring"
echo "Password: ${MONITORING_PASSWORD}"
echo ""
echo "Granted roles:"
echo "  • pg_monitor (read all stats)"
echo "  • CONNECT on database postgres"
echo "  • SELECT on public schema tables"
echo ""
echo "Next step: Update docker-compose.yml to use monitoring user"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
