#!/usr/bin/env bash
# generate-security-info.sh - Generate comprehensive security information after cluster initialization
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Get Railway environment variables
get_railway_var() {
    local var_name=$1
    railway variables | grep "^${var_name}=" | cut -d'=' -f2- || echo ""
}

# Main function
generate_security_info() {
    local output_file="${1:-cluster-security-info.txt}"
    local timestamp=$(date -Iseconds)
    
    log_info "Generating comprehensive security information..."
    
    # Fetch passwords from Railway
    log_info "Fetching credentials from Railway environment..."
    POSTGRES_PASSWORD=$(get_railway_var "POSTGRES_PASSWORD")
    REPMGR_PASSWORD=$(get_railway_var "REPMGR_PASSWORD")
    APP_READONLY_PASSWORD=$(get_railway_var "APP_READONLY_PASSWORD")
    APP_READWRITE_PASSWORD=$(get_railway_var "APP_READWRITE_PASSWORD")
    PROXYSQL_ADMIN_PASSWORD=$(get_railway_var "PROXYSQL_ADMIN_PASSWORD")
    
    cat > "$output_file" <<EOF
================================================================================
POSTGRESQL HA CLUSTER - SECURITY INFORMATION
================================================================================
Generated: $timestamp
Environment: Railway Platform
Architecture: PostgreSQL 17 + repmgr 5.5.0 + ProxySQL 3.0.2 BETA

⚠️  WARNING: STORE THIS FILE SECURELY AND DELETE AFTER SAVING TO PASSWORD MANAGER
⚠️  DO NOT COMMIT THIS FILE TO VERSION CONTROL
⚠️  DO NOT SHARE THIS FILE VIA INSECURE CHANNELS

================================================================================
SECTION 1: DATABASE CREDENTIALS
================================================================================

PostgreSQL Superuser
--------------------
Username: postgres
Password: ${POSTGRES_PASSWORD}
Usage:    Administrative tasks only (NOT for applications)
Notes:    Full database access. Use app_readonly/app_readwrite for applications.

Replication User
----------------
Username: repmgr
Password: ${REPMGR_PASSWORD}
Usage:    Internal replication and repmgr operations
Notes:    Used by repmgr for cluster management. Do not use in applications.

Application Read-Only User
---------------------------
Username: app_readonly
Password: ${APP_READONLY_PASSWORD}
Usage:    Read-only access for applications (SELECT only)
Notes:    Can connect to 'postgres' database, read all tables in 'public' schema.
          Routes through ProxySQL hostgroup 2 (standby nodes).

Application Read-Write User
----------------------------
Username: app_readwrite
Password: ${APP_READWRITE_PASSWORD}
Usage:    Read-write access for applications (SELECT, INSERT, UPDATE, DELETE)
Notes:    Can connect to 'postgres' database, modify data in 'public' schema.
          Routes through ProxySQL hostgroup 1 (primary node).

ProxySQL Admin Interface
-------------------------
Username: admin
Password: ${PROXYSQL_ADMIN_PASSWORD}
Port:     6132 (LOCALHOST ONLY - NOT PUBLICLY ACCESSIBLE)
Usage:    ProxySQL administration and monitoring
Notes:    ⚠️  Admin interface is bound to 127.0.0.1 (localhost) for security.
          Can only be accessed via 'railway ssh --service proxysql' then:
          PGPASSWORD='${PROXYSQL_ADMIN_PASSWORD}' psql -h 127.0.0.1 -p 6132 -U admin -d proxysql

================================================================================
SECTION 2: CONNECTION STRINGS
================================================================================

IMPORTANT: Replace <proxysql-domain> with actual Railway domain after running:
  railway service proxysql && railway domain
  railway service proxysql-2 && railway domain

Production Connection (via ProxySQL HA)
----------------------------------------
Primary ProxySQL Instance:
  postgresql://app_readwrite:${APP_READWRITE_PASSWORD}@<proxysql-domain>:5432/postgres

Secondary ProxySQL Instance (HA failover):
  postgresql://app_readwrite:${APP_READWRITE_PASSWORD}@<proxysql-2-domain>:5432/postgres

Read-Only Connection (optimized for standby nodes):
  postgresql://app_readonly:${APP_READONLY_PASSWORD}@<proxysql-domain>:5432/postgres

Connection String Format for Applications:
  psql "postgresql://app_readwrite:${APP_READWRITE_PASSWORD}@<proxysql-domain>:5432/postgres"
  
Python (psycopg2):
  import psycopg2
  conn = psycopg2.connect(
      host="<proxysql-domain>",
      port=5432,
      database="postgres",
      user="app_readwrite",
      password="${APP_READWRITE_PASSWORD}"
  )

Node.js (pg):
  const { Pool } = require('pg');
  const pool = new Pool({
      host: '<proxysql-domain>',
      port: 5432,
      database: 'postgres',
      user: 'app_readwrite',
      password: '${APP_READWRITE_PASSWORD}'
  });

Direct PostgreSQL Node Access (Internal Only)
----------------------------------------------
pg-1 (primary): pg-1.railway.internal:5432
pg-2 (standby): pg-2.railway.internal:5432
pg-3 (standby): pg-3.railway.internal:5432
pg-4 (standby): pg-4.railway.internal:5432

Note: Direct node access should only be used for maintenance via Railway SSH.
      All application traffic should go through ProxySQL.

================================================================================
SECTION 3: SECURITY CONFIGURATION
================================================================================

Network Security
----------------
✅ PostgreSQL nodes: Internal Railway network only (not publicly accessible)
✅ ProxySQL admin port (6132): Localhost only (127.0.0.1)
✅ ProxySQL PostgreSQL port (5432): Public (requires password authentication)
⚠️  SSL/TLS: Currently DISABLED (plaintext connections)
   Action: Enable SSL/TLS for production (see SECURITY_CHECKLIST.md)

Authentication
--------------
✅ Password authentication (md5) required for all connections
✅ Strong auto-generated passwords (32 characters, base64)
✅ Separate users for different privilege levels
✅ No default passwords in production
⚠️  Brute force protection: NOT CONFIGURED
   Action: Implement rate limiting at application or infrastructure level

Access Control (pg_hba.conf)
-----------------------------
Current configuration allows connections from any IP (0.0.0.0/0) with valid password.
For production, consider:
  1. Restricting to specific IP ranges
  2. Requiring SSL/TLS (change 'host' to 'hostssl' in pg_hba.conf)
  3. Implementing IP allowlisting at Railway or application level

Audit Logging
-------------
✅ Connection logging enabled (log_connections = on)
✅ Disconnection logging enabled (log_disconnections = on)
✅ DDL statement logging enabled (log_statement = 'ddl')
✅ Slow query logging enabled (log_min_duration_statement = 1000ms)

View logs:
  railway logs --service pg-1
  railway logs --service proxysql

ProxySQL Security
-----------------
✅ Admin interface on localhost only (cannot be accessed externally)
✅ Query routing based on SQL pattern matching
✅ Connection pooling (max 30,000 connections per ProxySQL instance)
✅ Read/write splitting (writes to primary, reads to standbys)

Query Timeouts
--------------
✅ Statement timeout: 300 seconds (5 minutes)
   Prevents long-running queries from blocking resources.
   Adjust via: ALTER DATABASE postgres SET statement_timeout = '300s';

================================================================================
SECTION 4: SECURITY CHECKLIST (ACTION REQUIRED)
================================================================================

Before Production Deployment:
------------------------------
[ ] Enable SSL/TLS for client connections (see SECURITY_CHECKLIST.md)
[ ] Review and restrict pg_hba.conf access rules
[ ] Set up monitoring and alerting for failed login attempts
[ ] Configure automated backups and test recovery
[ ] Implement application-level rate limiting
[ ] Review ProxySQL query rules for SQL injection prevention
[ ] Set up security scanning (e.g., vulnerability scanning)
[ ] Document incident response procedures
[ ] Train team on security best practices
[ ] Rotate passwords every 90 days

Security Audit:
---------------
[ ] Run penetration tests (see SECURITY_CHECKLIST.md - Phase 1-7)
[ ] Verify ProxySQL admin port is NOT publicly accessible
[ ] Test password strength and authentication
[ ] Verify SSL/TLS configuration (if enabled)
[ ] Review audit logs for suspicious activity
[ ] Test disaster recovery procedures

Compliance:
-----------
[ ] Data retention policy defined and implemented
[ ] Data encryption at rest verified (Railway volumes)
[ ] Access control logs maintained
[ ] Regular security audits scheduled

================================================================================
SECTION 5: OPERATIONAL PROCEDURES
================================================================================

Password Rotation
-----------------
To rotate passwords:
  1. Generate new password: openssl rand -base64 32
  2. Update Railway variable: railway variables --set "APP_READWRITE_PASSWORD=<new_password>"
  3. Update ProxySQL user config:
     railway ssh --service proxysql
     PGPASSWORD='${PROXYSQL_ADMIN_PASSWORD}' psql -h 127.0.0.1 -p 6132 -U admin -d proxysql
     UPDATE pgsql_users SET password='<new_password>' WHERE username='app_readwrite';
     LOAD PGSQL USERS TO RUNTIME;
     SAVE PGSQL USERS TO DISK;
  4. Update application connection strings
  5. Repeat for proxysql-2

Emergency Access Revocation
----------------------------
To immediately revoke a compromised user:
  railway ssh --service pg-1
  gosu postgres psql -U postgres
  ALTER USER app_readwrite WITH PASSWORD 'temporary_strong_password';
  -- Or completely revoke access:
  REVOKE ALL ON DATABASE postgres FROM app_readwrite;

Monitoring Security Events
---------------------------
Check failed login attempts:
  railway ssh --service pg-1
  gosu postgres psql -U postgres -c "SELECT * FROM pg_stat_database WHERE datname='postgres';"

ProxySQL connection errors:
  railway ssh --service proxysql
  PGPASSWORD='${PROXYSQL_ADMIN_PASSWORD}' psql -h 127.0.0.1 -p 6132 -U admin -d proxysql \
    -c "SELECT * FROM stats_pgsql_connection_pool WHERE status='OFFLINE';"

Backup and Recovery
-------------------
Manual backup:
  railway ssh --service pg-1
  gosu postgres pg_dump -Fc postgres > /tmp/backup_\$(date +%Y%m%d).dump
  
Restore from backup:
  railway ssh --service pg-1
  gosu postgres pg_restore -d postgres /tmp/backup_<date>.dump

Note: Railway provides automated volume snapshots. Verify backup schedule:
  https://railway.app/dashboard

================================================================================
SECTION 6: CONTACT AND SUPPORT
================================================================================

Railway Support:
  https://railway.app/help
  Discord: https://discord.gg/railway

PostgreSQL Documentation:
  https://www.postgresql.org/docs/17/

ProxySQL Documentation:
  https://proxysql.com/documentation/

Repmgr Documentation:
  https://www.repmgr.org/docs/current/

Security Incident Response:
  1. Immediately revoke compromised credentials
  2. Review audit logs for unauthorized access
  3. Notify team via designated communication channel
  4. Follow incident response plan (document separately)
  5. Report to Railway if platform security issue

================================================================================
SECTION 7: IMPORTANT REMINDERS
================================================================================

🔴 DO NOT:
  - Commit this file to version control (add to .gitignore)
  - Share passwords via email or unencrypted channels
  - Use postgres superuser for application connections
  - Expose ProxySQL admin port (6132) publicly
  - Skip security audits before production deployment

🟢 DO:
  - Store this file in a secure password manager
  - Use app_readonly for read-only operations
  - Use app_readwrite for data modification
  - Rotate passwords regularly (every 90 days)
  - Monitor logs for security events
  - Test disaster recovery procedures
  - Keep PostgreSQL and ProxySQL updated

================================================================================
END OF SECURITY INFORMATION
================================================================================

Generated by: railway-deploy.sh
For questions or issues, refer to: SECURITY_CHECKLIST.md, README.md
EOF
    
    log_success "Security information saved to: $output_file"
    
    # Create .gitignore entry if not exists
    if [ -f "../.gitignore" ]; then
        if ! grep -q "cluster-security-info.txt" "../.gitignore"; then
            echo "cluster-security-info.txt" >> "../.gitignore"
            log_success "Added cluster-security-info.txt to .gitignore"
        fi
    fi
    
    log_warn ""
    log_warn "⚠️  IMPORTANT SECURITY NOTICE:"
    log_warn "  1. Save $output_file to a secure password manager"
    log_warn "  2. Delete this file after saving: rm $output_file"
    log_warn "  3. Never commit this file to Git"
    log_warn "  4. Review SECURITY_CHECKLIST.md before production deployment"
    log_warn ""
    
    # Display summary
    cat "$output_file"
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    generate_security_info "$@"
fi
