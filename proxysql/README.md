# ProxySQL 3.0.2 for PostgreSQL (BETA)

## ⚠️ WARNING
ProxySQL 3.0.x PostgreSQL module is **still in BETA**. Use with caution in production.

## Features
- **Native PostgreSQL Protocol Support** (BETA in ProxySQL 3.0.x)
- **Query Routing**: Write to primary (hostgroup 1), reads to standbys (hostgroup 2)
- **Connection Pooling**: Multiplexing to reduce backend connections
- **Auto-discovery**: Monitors PostgreSQL nodes and updates topology automatically
- **High Availability**: Deploy 2 instances for redundancy
- **Persistent Configuration**: Volume mount at `/var/lib/proxysql` preserves config after restart

## Ports
- **6132**: Admin interface (PostgreSQL protocol)
- **5432**: PostgreSQL traffic proxy (standard PostgreSQL port)

## Volume Mount (Important!)
ProxySQL requires a **persistent volume** to store configuration:
- **Mount Path**: `/var/lib/proxysql`
- **Purpose**: 
  - Stores ProxySQL.db (SQLite database)
  - Persists server lists, query rules, users
  - Prevents reconfiguration on container restart
- **Size**: 1-5GB recommended

**⚠️ Without volume**: ProxySQL loses all configuration on restart!

## Configuration
Environment variables (set via Railway):
- `PROXYSQL_ADMIN_USER=admin`
- `PROXYSQL_ADMIN_PASSWORD=YOUR_SECURE_PASSWORD`
- `PG_NODES=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal`
- `MONITOR_INTERVAL=5`

## Connect to ProxySQL
```bash
# Via Railway SSH
railway ssh --service proxysql

# Connect to admin interface
PGPASSWORD=YOUR_SECURE_PASSWORD psql -h 127.0.0.1 -p 6132 -U admin -d proxysql

# Check server status
SELECT hostgroup_id,hostname,port,status FROM stats_pgsql_connection_pool;

# Check query rules
SELECT * FROM pgsql_query_rules;
```

## Connect Your Application
```bash
# Get ProxySQL public URL from Railway Dashboard
# Connect to port 6133 (PostgreSQL traffic)

# Example connection string:
postgresql://postgres:YOUR_SECURE_PASSWORD@proxysql.railway.internal:6133/postgres
```

## Monitoring
```bash
# Check logs
railway logs --service proxysql

# View stats
PGPASSWORD=YOUR_SECURE_PASSWORD psql -h proxysql.railway.internal -p 6132 -U admin -d proxysql \
  -c "SELECT * FROM stats_pgsql_global;"
```

## Known Limitations (ProxySQL 3.0 PostgreSQL BETA)
- Prepared statements and COPY in binary format: Not yet supported
- Still undergoing active development and testing
- Report bugs to: https://github.com/sysown/proxysql/issues

## HA Setup
Deploy 2 instances (proxysql, proxysql-2) for redundancy. Applications should:
1. Use Railway's load balancer (if available)
2. Or implement client-side failover between both instances
3. Or use DNS round-robin

## References
- [ProxySQL 3.0.2 Release Notes](https://github.com/sysown/proxysql/releases/tag/v3.0.2)
- [ProxySQL Documentation](https://proxysql.com/documentation/)
- [PostgreSQL Support (BETA)](https://proxysql.com/documentation/postgresql-support/)
