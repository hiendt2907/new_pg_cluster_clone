#!/bin/bash
# Setup application users with proper permissions
# Run from host: ./scripts/setup-app-users.sh
# Or: docker exec pg-1 bash -c "$(cat scripts/setup-app-users.sh)"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Default passwords (can be overridden by environment variables)
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgrespass}"
APP_READONLY_PASSWORD="${APP_READONLY_PASSWORD:-appreadonlypass}"
APP_READWRITE_PASSWORD="${APP_READWRITE_PASSWORD:-appreadwritepass}"

# Container name (default to pg-1)
CONTAINER_NAME="${CONTAINER_NAME:-pg-1}"

log "Setting up application users and permissions on ${CONTAINER_NAME}..."

# Check if running inside container or from host
if [ -f /.dockerenv ]; then
    # Running inside container
    log "Running inside container"
    
    # Wait for PostgreSQL to be ready
    for i in {1..30}; do
        if PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U postgres -d postgres -c '\q' 2>/dev/null; then
            log "PostgreSQL is ready"
            break
        fi
        warn "Waiting for PostgreSQL... (attempt $i/30)"
        sleep 2
    done
    
    # Execute SQL commands directly
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U postgres -d postgres <<EOF
-- ============================================
-- Application User Setup
-- ============================================

-- 1. Create or update app_readonly user (read-only access)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'app_readonly') THEN
        CREATE USER app_readonly WITH PASSWORD '${APP_READONLY_PASSWORD}';
        RAISE NOTICE 'User app_readonly created';
    ELSE
        ALTER USER app_readonly WITH PASSWORD '${APP_READONLY_PASSWORD}';
        RAISE NOTICE 'User app_readonly password updated';
    END IF;
END
\$\$;

-- 2. Create or update app_readwrite user (read-write access)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'app_readwrite') THEN
        CREATE USER app_readwrite WITH PASSWORD '${APP_READWRITE_PASSWORD}';
        RAISE NOTICE 'User app_readwrite created';
    ELSE
        ALTER USER app_readwrite WITH PASSWORD '${APP_READWRITE_PASSWORD}';
        RAISE NOTICE 'User app_readwrite password updated';
    END IF;
END
\$\$;

-- ============================================
-- Schema-level Permissions
-- ============================================

-- Grant CONNECT to database
GRANT CONNECT ON DATABASE postgres TO app_readonly;
GRANT CONNECT ON DATABASE postgres TO app_readwrite;

-- Grant USAGE on public schema
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT USAGE ON SCHEMA public TO app_readwrite;

-- ============================================
-- Table-level Permissions for app_readonly
-- ============================================

-- Grant SELECT on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;

-- Grant SELECT on all future tables (created by any user)
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT ON TABLES TO app_readonly;

-- Grant SELECT on all sequences (for reading SERIAL values)
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT ON SEQUENCES TO app_readonly;

-- ============================================
-- Table-level Permissions for app_readwrite
-- ============================================

-- Grant full CRUD on all existing tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_readwrite;

-- Grant full CRUD on all future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;

-- Grant USAGE and SELECT on all existing sequences (for SERIAL columns)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_readwrite;

-- Grant USAGE and SELECT on all future sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT USAGE, SELECT ON SEQUENCES TO app_readwrite;

-- Grant CREATE on public schema (for CREATE TABLE, etc.)
GRANT CREATE ON SCHEMA public TO app_readwrite;

-- ============================================
-- Function-level Permissions (optional)
-- ============================================

-- Grant EXECUTE on all existing functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_readonly;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_readwrite;

-- Grant EXECUTE on all future functions
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT EXECUTE ON FUNCTIONS TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT EXECUTE ON FUNCTIONS TO app_readwrite;

-- ============================================
-- Verify Permissions
-- ============================================

SELECT 
    'app_readonly' as username,
    has_schema_privilege('app_readonly', 'public', 'USAGE') as schema_usage,
    has_database_privilege('app_readonly', 'postgres', 'CONNECT') as db_connect;

SELECT 
    'app_readwrite' as username,
    has_schema_privilege('app_readwrite', 'public', 'USAGE') as schema_usage,
    has_schema_privilege('app_readwrite', 'public', 'CREATE') as schema_create,
    has_database_privilege('app_readwrite', 'postgres', 'CONNECT') as db_connect;

EOF

    log "✓ Application users setup completed successfully"
else
    # Running from host - use docker exec
    log "Running from host, executing in container ${CONTAINER_NAME}"
    
    docker exec -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
                -e APP_READONLY_PASSWORD="$APP_READONLY_PASSWORD" \
                -e APP_READWRITE_PASSWORD="$APP_READWRITE_PASSWORD" \
                "$CONTAINER_NAME" su - postgres -c "psql -d postgres" <<EOF
EOF
    
    log "✓ Application users setup completed successfully"
fi

log ""
log "Created users:"
log "  - app_readonly: SELECT on all tables"
log "  - app_readwrite: SELECT, INSERT, UPDATE, DELETE, CREATE on all tables"
log ""
log "Use these credentials in your application:"
log "  app_readonly / ${APP_READONLY_PASSWORD}"
log "  app_readwrite / ${APP_READWRITE_PASSWORD}"
